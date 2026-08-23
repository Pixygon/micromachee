//! The machine: a 128×128 screen with eight colours, and the handful of
//! drawing operations a game gets.
//!
//! Everything clips. A game that draws off the edge — and every game does,
//! constantly, because that is what moving things do — must not panic and must
//! not wrap around to the far side of the screen. That is checked rather than
//! assumed, because a wrapped pixel looks like a game bug and is a console bug.

/// Coordinates and sizes are clamped to this before any primitive iterates.
///
/// Everything clips to the 128×128 screen, so a coordinate past this window is
/// already entirely off-screen and drawing it changes nothing visible. What it
/// DID change was the cost: `circ` with a two-billion radius looped two billion
/// rows, and `line` between far-apart points stepped Bresenham a pixel at a time
/// across the whole gap — each a single Lua call, so the per-frame instruction
/// budget never saw them and the frame simply hung. Clamping the geometry bounds
/// every loop to a few thousand iterations while leaving all real drawing exact:
/// nothing on a 128-pixel screen needs a coordinate beyond ±4096.
const DRAW_LIMIT: i32 = 4096;

#[inline]
fn clamp_coord(v: i32) -> i32 {
    v.clamp(-DRAW_LIMIT, DRAW_LIMIT)
}

pub const W: i32 = 128;
pub const H: i32 = 128;

/// A character cell: 3 pixels of glyph and one of air, five rows and one of
/// air. A game laying out a screen needs these, so they are named rather than
/// left as the 4 and 6 sprinkled through the drawing code.
pub const CHAR_WIDTH: i32 = 4;
pub const LINE_HEIGHT: i32 = 6;

/// Eight colours, and no more. Enough for a readable game, few enough that an
/// author picks by name instead of deliberating.
///
///   0 black · 1 navy · 2 red · 3 orange · 4 yellow · 5 green · 6 blue · 7 white
pub const DEFAULT_PALETTE: [(u8, u8, u8); 8] = [
    (0x00, 0x00, 0x00),
    (0x1d, 0x2b, 0x53),
    (0xff, 0x00, 0x4d),
    (0xff, 0xa3, 0x00),
    (0xff, 0xec, 0x27),
    (0x00, 0xe4, 0x36),
    (0x29, 0xad, 0xff),
    (0xff, 0xf1, 0xe8),
];

pub struct Screen {
    pub px: Vec<u8>,
}

impl Default for Screen {
    fn default() -> Self {
        Self::new()
    }
}

impl Screen {
    pub fn new() -> Self {
        Self { px: vec![0; (W * H) as usize] }
    }

    #[inline]
    fn col(c: i32) -> u8 {
        // Wrap rather than clamp, so `c % 8` arithmetic in a game does what the
        // author meant and a stray 9 is still a colour rather than a crash.
        (c.rem_euclid(8)) as u8
    }

    pub fn cls(&mut self, c: i32) {
        self.px.fill(Self::col(c));
    }

    #[inline]
    pub fn pset(&mut self, x: i32, y: i32, c: i32) {
        if x >= 0 && y >= 0 && x < W && y < H {
            self.px[(y * W + x) as usize] = Self::col(c);
        }
    }

    #[inline]
    pub fn pget(&self, x: i32, y: i32) -> u8 {
        if x >= 0 && y >= 0 && x < W && y < H {
            self.px[(y * W + x) as usize]
        } else {
            0
        }
    }

    pub fn rect(&mut self, x: i32, y: i32, w: i32, h: i32, c: i32) {
        if w <= 0 || h <= 0 {
            return;
        }
        let c = Self::col(c);
        let x0 = x.max(0);
        let y0 = y.max(0);
        let x1 = x.saturating_add(w).min(W);
        let y1 = y.saturating_add(h).min(H);
        for yy in y0..y1 {
            let row = (yy * W) as usize;
            for xx in x0..x1 {
                self.px[row + xx as usize] = c;
            }
        }
    }

    pub fn rectb(&mut self, x: i32, y: i32, w: i32, h: i32, c: i32) {
        if w <= 0 || h <= 0 {
            return;
        }
        self.rect(x, y, w, 1, c);
        self.rect(x, y + h - 1, w, 1, c);
        self.rect(x, y, 1, h, c);
        self.rect(x + w - 1, y, 1, h, c);
    }

    pub fn line(&mut self, x0: i32, y0: i32, x1: i32, y1: i32, c: i32) {
        // Bresenham, in the form that needs no special cases for steepness or
        // direction — the one place in here worth not improvising.
        let (x0, y0) = (clamp_coord(x0), clamp_coord(y0));
        let (x1, y1) = (clamp_coord(x1), clamp_coord(y1));
        let (mut x, mut y) = (x0, y0);
        let dx = (x1 - x0).abs();
        let dy = -(y1 - y0).abs();
        let sx = if x0 < x1 { 1 } else { -1 };
        let sy = if y0 < y1 { 1 } else { -1 };
        let mut err = dx + dy;
        loop {
            self.pset(x, y, c);
            if x == x1 && y == y1 {
                break;
            }
            let e2 = 2 * err;
            if e2 >= dy {
                err += dy;
                x += sx;
            }
            if e2 <= dx {
                err += dx;
                y += sy;
            }
        }
    }

    pub fn circ(&mut self, cx: i32, cy: i32, r: i32, c: i32) {
        if r < 0 {
            return;
        }
        let r = r.min(DRAW_LIMIT);
        let rr = r * r;
        for dy in -r..=r {
            let span = ((rr - dy * dy) as f64).sqrt() as i32;
            self.rect(cx - span, cy + dy, span * 2 + 1, 1, c);
        }
    }

    pub fn circb(&mut self, cx: i32, cy: i32, r: i32, c: i32) {
        if r < 0 {
            return;
        }
        let r = r.min(DRAW_LIMIT);
        let (mut x, mut y, mut d) = (r, 0, 1 - r);
        while x >= y {
            for (px, py) in [
                (cx + x, cy + y), (cx + y, cy + x), (cx - y, cy + x), (cx - x, cy + y),
                (cx - x, cy - y), (cx - y, cy - x), (cx + y, cy - x), (cx + x, cy - y),
            ] {
                self.pset(px, py, c);
            }
            y += 1;
            if d < 0 {
                d += 2 * y + 1;
            } else {
                x -= 1;
                d += 2 * (y - x) + 1;
            }
        }
    }

    /// Text, 3×5 with a pixel of air — four pixels per character, so a full
    /// line is 32 characters. Lower case is folded to upper: one case is a
    /// smaller font table and, at this size, the only legible option.
    /// Text, with every pixel drawn as a `scale`-sized block. One font at any
    /// size — which is what a title screen and a cover both need, and the
    /// alternative was seven carts each reinventing it.
    pub fn print(&mut self, text: &str, x: i32, y: i32, c: i32, scale: i32) {
        let s = scale.max(1);
        let (mut cx, mut cy) = (x, y);
        for ch in text.chars() {
            if ch == '\n' {
                cx = x;
                cy += LINE_HEIGHT * s;
                continue;
            }
            if let Some(rows) = glyph(ch.to_ascii_uppercase()) {
                for (ry, bits) in rows.iter().enumerate() {
                    for rx in 0..3 {
                        if bits & (0b100 >> rx) != 0 {
                            if s == 1 {
                                self.pset(cx + rx, cy + ry as i32, c);
                            } else {
                                self.rect(cx + rx * s, cy + ry as i32 * s, s, s, c);
                            }
                        }
                    }
                }
            }
            cx += CHAR_WIDTH * s;
        }
    }


    /// The palette arrives here and nowhere else. A cart names slots; only
    /// this call turns a slot into a colour, which is why swapping a theme
    /// costs nothing and no cart can tell which one it is running under.
    pub fn to_png(&self, palette: &[(u8, u8, u8); 8]) -> Vec<u8> {
        crate::png::encode(W as u32, H as u32, palette, &self.px)
    }
}

/// Every character the font can draw. The web player exports its font from
/// this, so the two renderers cannot drift apart. Test-only: the export runs
/// from a test, and the console itself asks `glyph` directly.
#[cfg(test)]
pub const PRINTABLE: &str =
    " ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.,:;!?-_+=*/\\'\"()[]<>%#@&^";

/// The font as data: each drawable character with its five rows of three bits.
#[cfg(test)]
pub fn font_table() -> Vec<(char, [u8; 5])> {
    PRINTABLE.chars().filter_map(|c| glyph(c).map(|rows| (c, rows))).collect()
}

/// Whether `print` would draw this character rather than skip it. The cart
/// rules check titles against this, so a name the menu cannot draw is refused
/// at load rather than showing up as a gap on screen.
pub fn can_render(c: char) -> bool {
    glyph(c.to_ascii_uppercase()).is_some()
}

/// The font. Five rows of three bits, most significant bit leftmost.
#[rustfmt::skip]
fn glyph(c: char) -> Option<[u8; 5]> {
    Some(match c {
        ' ' => [0b000, 0b000, 0b000, 0b000, 0b000],
        'A' => [0b010, 0b101, 0b111, 0b101, 0b101],
        'B' => [0b110, 0b101, 0b110, 0b101, 0b110],
        'C' => [0b011, 0b100, 0b100, 0b100, 0b011],
        'D' => [0b110, 0b101, 0b101, 0b101, 0b110],
        'E' => [0b111, 0b100, 0b110, 0b100, 0b111],
        'F' => [0b111, 0b100, 0b110, 0b100, 0b100],
        'G' => [0b011, 0b100, 0b101, 0b101, 0b011],
        'H' => [0b101, 0b101, 0b111, 0b101, 0b101],
        'I' => [0b111, 0b010, 0b010, 0b010, 0b111],
        'J' => [0b001, 0b001, 0b001, 0b101, 0b010],
        'K' => [0b101, 0b101, 0b110, 0b101, 0b101],
        'L' => [0b100, 0b100, 0b100, 0b100, 0b111],
        'M' => [0b101, 0b111, 0b111, 0b101, 0b101],
        'N' => [0b110, 0b101, 0b101, 0b101, 0b101],
        'O' => [0b010, 0b101, 0b101, 0b101, 0b010],
        'P' => [0b110, 0b101, 0b110, 0b100, 0b100],
        'Q' => [0b010, 0b101, 0b101, 0b111, 0b011],
        'R' => [0b110, 0b101, 0b110, 0b101, 0b101],
        'S' => [0b011, 0b100, 0b010, 0b001, 0b110],
        'T' => [0b111, 0b010, 0b010, 0b010, 0b010],
        'U' => [0b101, 0b101, 0b101, 0b101, 0b011],
        'V' => [0b101, 0b101, 0b101, 0b010, 0b010],
        'W' => [0b101, 0b101, 0b111, 0b111, 0b101],
        'X' => [0b101, 0b101, 0b010, 0b101, 0b101],
        'Y' => [0b101, 0b101, 0b010, 0b010, 0b010],
        'Z' => [0b111, 0b001, 0b010, 0b100, 0b111],
        '0' => [0b111, 0b101, 0b101, 0b101, 0b111],
        '1' => [0b010, 0b110, 0b010, 0b010, 0b111],
        '2' => [0b110, 0b001, 0b010, 0b100, 0b111],
        '3' => [0b111, 0b001, 0b011, 0b001, 0b111],
        '4' => [0b101, 0b101, 0b111, 0b001, 0b001],
        '5' => [0b111, 0b100, 0b110, 0b001, 0b110],
        '6' => [0b011, 0b100, 0b110, 0b101, 0b010],
        '7' => [0b111, 0b001, 0b010, 0b010, 0b010],
        '8' => [0b010, 0b101, 0b010, 0b101, 0b010],
        '9' => [0b010, 0b101, 0b011, 0b001, 0b110],
        '.' => [0b000, 0b000, 0b000, 0b000, 0b010],
        ',' => [0b000, 0b000, 0b000, 0b010, 0b100],
        ':' => [0b000, 0b010, 0b000, 0b010, 0b000],
        ';' => [0b000, 0b010, 0b000, 0b010, 0b100],
        '!' => [0b010, 0b010, 0b010, 0b000, 0b010],
        '?' => [0b110, 0b001, 0b010, 0b000, 0b010],
        '-' => [0b000, 0b000, 0b111, 0b000, 0b000],
        '_' => [0b000, 0b000, 0b000, 0b000, 0b111],
        '+' => [0b000, 0b010, 0b111, 0b010, 0b000],
        '=' => [0b000, 0b111, 0b000, 0b111, 0b000],
        '*' => [0b101, 0b010, 0b111, 0b010, 0b101],
        '/' => [0b001, 0b001, 0b010, 0b100, 0b100],
        '\\' => [0b100, 0b100, 0b010, 0b001, 0b001],
        '\'' => [0b010, 0b010, 0b000, 0b000, 0b000],
        '"' => [0b101, 0b101, 0b000, 0b000, 0b000],
        '(' => [0b001, 0b010, 0b010, 0b010, 0b001],
        ')' => [0b100, 0b010, 0b010, 0b010, 0b100],
        '[' => [0b011, 0b010, 0b010, 0b010, 0b011],
        ']' => [0b110, 0b010, 0b010, 0b010, 0b110],
        '<' => [0b001, 0b010, 0b100, 0b010, 0b001],
        '>' => [0b100, 0b010, 0b001, 0b010, 0b100],
        '%' => [0b101, 0b001, 0b010, 0b100, 0b101],
        '#' => [0b101, 0b111, 0b101, 0b111, 0b101],
        '@' => [0b010, 0b101, 0b111, 0b100, 0b011],
        '&' => [0b010, 0b101, 0b010, 0b101, 0b011],
        '^' => [0b010, 0b101, 0b000, 0b000, 0b000],
        _ => return None,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn extreme_geometry_terminates_and_does_not_overflow() {
        // Each of these is a single Lua call, so the per-frame instruction
        // budget never sees it. Before the clamp, circ looped ~2 billion rows
        // and line stepped Bresenham across ~4 billion pixels; the frame hung.
        // The test passing at all is the assertion — it returns.
        let mut s = Screen::new();
        s.circ(0, 0, i32::MAX, 3);
        s.circb(0, 0, i32::MAX, 3);
        s.line(i32::MIN, i32::MIN, i32::MAX, i32::MAX, 4);
        s.rect(i32::MAX, i32::MAX, i32::MAX, i32::MAX, 5);
        s.circ(-i32::MAX, -i32::MAX, i32::MAX, 6);

        // and an ordinary circle is unchanged: centre filled, well outside empty
        let mut s = Screen::new();
        s.circ(64, 64, 10, 5);
        assert_eq!(s.pget(64, 64), 5, "centre of a normal circle not drawn");
        assert_eq!(s.pget(64, 90), 0, "a normal circle leaked past its radius");
    }

    #[test]
    fn a_new_screen_is_black() {
        assert!(Screen::new().px.iter().all(|&p| p == 0));
    }

    #[test]
    fn drawing_off_screen_neither_panics_nor_wraps() {
        // The bug this exists for: a pixel at x = -1 landing on the right-hand
        // edge of the row above. It reads as the game being broken.
        let mut s = Screen::new();
        s.pset(-1, 5, 7);
        s.pset(W, 5, 7);
        s.pset(5, -1, 7);
        s.pset(5, H, 7);
        s.rect(-40, -40, 20, 20, 7);
        s.rect(W + 5, H + 5, 20, 20, 7);
        s.line(-500, -500, -400, -400, 7);
        s.circ(-60, 64, 10, 7);
        s.print("OFF THE EDGE ENTIRELY", -400, -400, 7, 1);
        assert!(s.px.iter().all(|&p| p == 0), "something drew off-screen onto the screen");
    }

    #[test]
    fn clipping_keeps_the_part_that_is_on_screen() {
        let mut s = Screen::new();
        s.rect(-5, -5, 10, 10, 3);
        assert_eq!(s.pget(0, 0), 3);
        assert_eq!(s.pget(4, 4), 3);
        assert_eq!(s.pget(5, 5), 0);
    }

    #[test]
    fn colours_wrap_rather_than_crash() {
        // Games do `c = c + 1` in loops. Nine must be a colour, not a panic.
        let mut s = Screen::new();
        s.pset(1, 1, 9);
        s.pset(2, 2, -1);
        assert_eq!(s.pget(1, 1), 1);
        assert_eq!(s.pget(2, 2), 7);
    }

    #[test]
    fn lines_reach_both_ends() {
        let mut s = Screen::new();
        s.line(2, 2, 40, 60, 5);
        assert_eq!(s.pget(2, 2), 5);
        assert_eq!(s.pget(40, 60), 5);
    }

    #[test]
    fn a_filled_circle_is_filled_and_bounded() {
        let mut s = Screen::new();
        s.circ(64, 64, 10, 2);
        assert_eq!(s.pget(64, 64), 2, "centre");
        assert_eq!(s.pget(64, 74), 2, "bottom edge");
        assert_eq!(s.pget(64, 76), 0, "outside");
    }

    #[test]
    fn every_printable_character_has_a_glyph() {
        // A missing glyph is a silent hole in a game's text.
        for c in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 .,:;!?-_+=*/\\'\"()[]<>%#@&^".chars() {
            assert!(glyph(c).is_some(), "no glyph for {c:?}");
        }
    }

    #[test]
    fn text_is_readable_and_fits() {
        let mut s = Screen::new();
        s.print("SCORE 100", 0, 0, 7, 1);
        assert!(s.px.iter().any(|&p| p == 7), "text drew nothing");
        // 32 characters is a full line at four pixels each.
        let mut wide = Screen::new();
        wide.print(&"M".repeat(32), 0, 0, 7, 1);
        assert_eq!(wide.pget(127, 2), 0, "the 32nd character must end at the edge");
    }

    #[test]
    fn scaled_text_is_the_same_shape_only_bigger() {
        let mut one = Screen::new();
        one.print("AB", 0, 0, 7, 1);
        let mut three = Screen::new();
        three.print("AB", 0, 0, 7, 3);
        // Every lit pixel at 1x must be a lit 3x3 block at 3x, and nothing else
        // may be lit — that is what "the same shape, bigger" has to mean.
        for y in 0..5 {
            for x in 0..8 {
                let lit = one.pget(x, y) == 7;
                for dy in 0..3 {
                    for dx in 0..3 {
                        let got = three.pget(x * 3 + dx, y * 3 + dy) == 7;
                        assert_eq!(got, lit, "pixel {x},{y} block {dx},{dy}");
                    }
                }
            }
        }
    }


    #[test]
    fn a_scale_of_zero_or_less_still_draws() {
        // A cart doing `print(t, x, y, c, n - 1)` must not silently vanish.
        let mut s = Screen::new();
        s.print("A", 4, 4, 7, 0);
        assert!(s.px.iter().any(|&p| p == 7));
    }

    #[test]
    fn a_newline_starts_a_new_line() {
        // It used to reset the column without moving down, so a second line
        // landed on top of the first and read as corrupted text.
        let mut s = Screen::new();
        s.print("AB\nCD", 0, 0, 7, 1);
        let mut apart = Screen::new();
        apart.print("AB", 0, 0, 7, 1);
        apart.print("CD", 0, LINE_HEIGHT, 7, 1);
        assert_eq!(s.px, apart.px);
    }

    #[test]
    fn lower_case_prints_as_upper() {
        let (mut a, mut b) = (Screen::new(), Screen::new());
        a.print("hello", 4, 4, 7, 1);
        b.print("HELLO", 4, 4, 7, 1);
        assert_eq!(a.px, b.px);
    }
}
