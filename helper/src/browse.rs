//! The shelf, drawn by the console rather than around it.
//!
//! It used to be a grid of QML tiles sitting outside the screen, which meant
//! the thing you picked a game with was not made of the same pixels as the
//! game. Everything here goes through the same 240×160 `Screen` and the same
//! six buttons a cart gets, so the shelf is simply the first program the
//! console runs.
//!
//! Covers are the carts' own `_cover()` output, sampled down into a tile. Only
//! the top 96 rows are sampled: nearly every cover paints its title across the
//! bottom third, and a title reduced to a ninth of its size is a smear. The
//! name of the selected cart is spelled out in the header instead, at a size
//! the font was drawn for.

use crate::cart::Cart;
use crate::console::{headline_glyph, Screen, CHAR_WIDTH, HEADLINE_WIDTH, H, W};
use crate::mega;
use crate::shelf;
use crate::vm::Machine;

const COLS: usize = 3;
// Tiles are 3:2, the same shape as the screen and therefore as every cover —
// a tile IS the cover, shrunk, so the shapes have to agree.
const TILE_W: i32 = 72;
const TILE_H: i32 = 48;
// A tile is a CARD: art on top, the title set properly underneath. The art
// crops to the top 3/4 of the cover — the band where covers bake their big
// painted titles is cut, because a scale-4 title squeezed through a 3.3:1
// downsample is mush, and the caption below says the same thing legibly.
const ART_H: i32 = 36;
const ART_SRC_H: i32 = 120; // 3/4 of 160, the same 10:3 ratio as the width
const CAP_H: i32 = TILE_H - ART_H;
const GAP: i32 = 4;
const X0: i32 = 8; // 3 × 72 + 2 × 4 = 224, so eight pixels of margin each side
const GY: i32 = 18;
const VIS_ROWS: usize = 2;


/// Frames the fallback cover is allowed to run for a cart with no `_cover()`.
const FALLBACK_FRAMES: u32 = 40;

pub struct Entry {
    pub id: String,
    pub title: String,
    pub author: String,
    pub about: String,
    pub best: i64,
    pub draft: bool,
    pub in_mega: bool,
    art: Screen,
}

/// The reserved last tile. It is not a cart and has no file; picking it asks
/// the panel to open the make-a-game flow, which is why it comes back as its
/// own line rather than as an id that something might try to load.
const MAKE_ID: &str = "\u{1}make";

/// Frames of the opening titles. Skippable, and only played when the panel
/// itself opened — not every time the shelf process restarts, or leaving a game
/// would replay it and it would stop being a welcome.
const INTRO: i32 = 78;

pub struct Browse {
    entries: Vec<Entry>,
    sel: usize,
    scroll: usize,
    info: bool,
    last: u8,
    picked: Option<String>,
    sfx: Vec<u8>,
    make: bool,
    intro: i32,
    tick: i32,
    out: Screen,
}

/// Clamp to 0..1 — the eased slide needs it and `mid` is integer-only.
fn mid_f(v: f32) -> f32 {
    if v < 0.0 {
        0.0
    } else if v > 1.0 {
        1.0
    } else {
        v
    }
}

fn centre(text: &str, scale: i32) -> i32 {
    (W - text.chars().count() as i32 * CHAR_WIDTH * scale) / 2
}

/// Titles and labels go through the tongue like everything else, so the secret
/// mode does not stop at the edge of the games.
fn say(text: &str) -> String {
    if shelf::saved_tongue() {
        crate::ydrast::render(text)
    } else {
        text.to_uppercase()
    }
}

/// The console's own display face: 5x7, for titles the 3x5 font turns to mush.
fn headline(out: &mut Screen, text: &str, x: i32, y: i32, c: i32, scale: i32) {
    let mut cx = x;
    for ch in text.chars() {
        if let Some(rows) = headline_glyph(ch) {
            for (ry, row) in rows.iter().enumerate() {
                for rx in 0..5 {
                    if row & (0b10000 >> rx) != 0 {
                        if scale == 1 {
                            out.pset(cx + rx, y + ry as i32, c);
                        } else {
                            out.rect(cx + rx * scale, y + ry as i32 * scale, scale, scale, c);
                        }
                    }
                }
            }
        }
        cx += HEADLINE_WIDTH * scale;
    }
}

fn headline_centre(text: &str, scale: i32) -> i32 {
    (W - text.chars().count() as i32 * HEADLINE_WIDTH * scale) / 2
}

fn wrap(text: &str, cols: usize) -> Vec<String> {
    let mut lines = Vec::new();
    let mut line = String::new();
    for word in text.split_whitespace() {
        if !line.is_empty() && line.chars().count() + 1 + word.chars().count() > cols {
            lines.push(std::mem::take(&mut line));
        }
        if !line.is_empty() {
            line.push(' ');
        }
        line.push_str(word);
    }
    if !line.is_empty() {
        lines.push(line);
    }
    lines
}

/// Run a cart far enough to have a picture, and keep the pixels.
fn art_for(cart: &Cart) -> Option<Screen> {
    let machine = Machine::load(cart).ok()?;
    machine.set_tongue(shelf::saved_tongue());
    machine.init().ok()?;
    if machine.has_cover() {
        machine.cover().ok()?;
    } else {
        for _ in 0..FALLBACK_FRAMES {
            machine.update().ok()?;
            machine.draw().ok()?;
        }
    }
    let src = machine.screen.borrow();
    let mut copy = Screen::new();
    for y in 0..crate::console::H {
        for x in 0..W {
            copy.pset(x, y, src.pget(x, y) as i32);
        }
    }
    Some(copy)
}

/// The make-a-game tile: nothing but a plus, because it is the one tile that is
/// not a picture of a game that exists.
fn make_tile() -> Screen {
    let mut s = Screen::new();
    s.cls(0);
    s.rectb(10, 8, 108, 80, 1);
    s.rectb(11, 9, 106, 78, 1);
    s.rect(56, 30, 16, 36, 5);
    s.rect(46, 40, 36, 16, 5);
    s
}

/// A cart that will not run still needs a tile, so it gets its initial.
fn placeholder(title: &str) -> Screen {
    let mut s = Screen::new();
    s.cls(0);
    let initial: String = title.chars().take(1).collect::<String>().to_uppercase();
    s.print(&initial, centre(&initial, 6), 24, 1, 6);
    s
}

impl Browse {
    pub fn new(intro: bool) -> Self {
        let mut entries = Vec::new();

        // Mega goes first, the way it does on every other listing: it is the
        // one thing here that is about the whole shelf.
        entries.push(Entry {
            id: mega::MEGA_ID.to_string(),
            title: mega::MEGA_TITLE.to_string(),
            author: "pixygon".to_string(),
            about: mega::MEGA_ABOUT.to_string(),
            best: shelf::best(mega::MEGA_ID),
            draft: false,
            in_mega: false,
            art: mega::Mega::cover()
        });

        for c in shelf::list() {
            let art = shelf::find(&c.id)
                .and_then(|p| Cart::load(&p).ok())
                .and_then(|cart| art_for(&cart))
                .unwrap_or_else(|| placeholder(&c.title));
            entries.push(Entry {
                best: shelf::best(&c.id),
                draft: shelf::is_draft(&c.id),
                in_mega: c.in_mega,
                id: c.id,
                title: c.title,
                author: c.author,
                about: c.about,
                art
            });
        }

        // Always last, so the shelf reads as "the games, and then make one"
        // rather than putting a tool in among the toys.
        entries.push(Entry {
            id: MAKE_ID.to_string(),
            title: "Make a game".to_string(),
            author: "you".to_string(),
            about: "say what it is. the console writes it".to_string(),
            best: 0,
            draft: false,
            in_mega: false,
            art: make_tile()
        });

        Self {
            entries,
            sel: 0,
            scroll: 0,
            info: false,
            last: 0,
            picked: None,
            sfx: Vec::new(),
            make: false,
            intro: if intro { INTRO } else { 0 },
            tick: 0,
            out: Screen::new(),
        }
    }

    /// Sounds asked for since this was last called.
    pub fn take_sfx(&mut self) -> Vec<u8> {
        std::mem::take(&mut self.sfx)
    }

    /// Whether the player asked for the make-a-game flow rather than a cart.
    pub fn wants_make(&self) -> bool {
        self.make
    }

    /// The cart the player chose, once they have chosen one.
    pub fn picked(&self) -> Option<&str> {
        self.picked.as_deref()
    }

    fn rows(&self) -> usize {
        self.entries.len().div_ceil(COLS)
    }

    fn move_to(&mut self, next: usize) {
        let was = self.sel;
        self.sel = next.min(self.entries.len().saturating_sub(1));
        // Only when it actually moved: a blip at the end of a row for a press
        // that changed nothing is the console lying about what it did.
        if self.sel != was {
            self.sfx.push(0);
        }
        // Keep the selection inside the two rows on screen, and no further —
        // scrolling by a whole page loses the player their place.
        let row = self.sel / COLS;
        if row < self.scroll {
            self.scroll = row;
        } else if row >= self.scroll + VIS_ROWS {
            self.scroll = row + 1 - VIS_ROWS;
        }
    }

    fn choose(&mut self) {
        self.sfx.push(3);                   // pickup: you took something
        let id = self.entries[self.sel].id.clone();
        if id == MAKE_ID {
            self.make = true;
        } else {
            self.picked = Some(id);
        }
    }

    /// One frame. `held` is the same bitmask a cart sees.
    pub fn frame(&mut self, held: u8) -> &Screen {
        self.tick += 1;
        let pressed = held & !self.last;
        self.last = held;
        let hit = |b: u8| pressed & (1 << b) != 0;

        if self.entries.is_empty() {
            self.draw_empty();
            return &self.out;
        }

        // Any button at all cuts the titles short. An intro you cannot skip is
        // a delay, however good it is.
        if self.intro > 0 {
            self.intro -= 1;
            if pressed != 0 {
                // The press that skips is spent on skipping. Letting it fall
                // through as well means the button you hit to get past the
                // titles also moves the selection or starts a game.
                self.intro = 0;
                self.draw_grid();
                return &self.out;
            }
            self.draw_intro();
            return &self.out;
        }

        if self.info {
            if hit(4) {
                self.choose();
            } else if hit(5) {
                self.info = false;
            }
            self.draw_info();
            return &self.out;
        }

        if hit(0) && self.sel > 0 {
            self.move_to(self.sel - 1);
        }
        if hit(1) {
            self.move_to(self.sel + 1);
        }
        if hit(2) && self.sel >= COLS {
            self.move_to(self.sel - COLS);
        }
        if hit(3) {
            // Down from the last row goes to the end rather than nowhere, so a
            // half-full bottom row is still reachable from every column.
            let next = (self.sel + COLS).min(self.entries.len() - 1);
            self.move_to(next);
        }
        if hit(4) {
            self.choose();
        }
        if hit(5) {
            self.info = true;
            self.sfx.push(0);
        }

        self.draw_grid();
        &self.out
    }

    // ── drawing ─────────────────────────────────────────────────────────────

    /// The opening titles. MICRO comes down, MACHEE comes up, they meet, and
    /// the line under them draws itself outward from the middle.
    ///
    /// All of it is one eased number: `slide` runs 0 to 1 over the first third,
    /// so the two halves are always exactly as far along as each other and meet
    /// on the same frame however the timing is retuned.
    fn draw_intro(&mut self) {
        self.out.cls(0);
        let t = INTRO - self.intro;               // frames elapsed
        let arrive = INTRO / 3;

        // Cubic ease out: fast in, settling rather than stopping.
        let p = mid_f(t as f32 / arrive as f32);
        let slide = 1.0 - (1.0 - p) * (1.0 - p) * (1.0 - p);

        let top_y = (-30.0 + slide * 74.0) as i32;      // MICRO, down to 44
        let bot_y = (140.0 - slide * 72.0) as i32;      // MACHEE, up to 68

        self.out.print("MICRO", centre("MICRO", 3), top_y, 7, 3);
        self.out.print("MACHEE", centre("MACHEE", 3), bot_y, 6, 3);

        // Once they have landed, a rule opens out between them and the byline
        // fades up under it.
        if p >= 1.0 {
            let after = t - arrive;
            let w = (after * 5).clamp(0, 60);
            self.out.rect(64 - w, 64, w * 2, 1, 5);
            if after > 14 {
                let by = say("by pixygon");
                self.out.print(&by, centre(&by, 1), 96, 1, 1);
            }
        }
    }

    fn draw_empty(&mut self) {
        self.out.cls(0);
        let a = say("nothing on the shelf");
        let b = say("run micromachee sync");
        self.out.print(&a, centre(&a, 1), H / 2 - 8, 2, 1);
        self.out.print(&b, centre(&b, 1), H / 2 + 4, 1, 1);
    }

    /// One cover, shrunk into a tile: an exact miniature of the WHOLE 240x160
    /// cover, so what the shelf shows is what the cover is. Nearest-neighbour
    /// on the centre pixel of each block — a cover is pixel art drawn to read
    /// small, so a faithful sample beats the old mode-of-the-block averaging
    /// (muddy) and the old top-rows-only crop (which squished it out of shape).
    fn draw_tile(&mut self, at: usize, x: i32, y: i32) {
        let e = &self.entries[at];
        // rank_of[slot] = place in the luminance order, so bright art outvotes
        // its dark ground when a block is squeezed to one pixel. Point
        // sampling dropped thin bright strokes; a plain majority drowned them.
        let mut rank_of = [0i32; 8];
        for (place, slot) in crate::palettes::rank().iter().enumerate() {
            rank_of[*slot] = place as i32;
        }
        for ty in 0..ART_H {
            let sy0 = ty * ART_SRC_H / ART_H;
            let sy1 = ((ty + 1) * ART_SRC_H / ART_H).max(sy0 + 1);
            for tx in 0..TILE_W {
                let sx0 = tx * W / TILE_W;
                let sx1 = ((tx + 1) * W / TILE_W).max(sx0 + 1);
                let mut votes = [0i32; 8];
                for sy in sy0..sy1 {
                    for sx in sx0..sx1 {
                        let c = e.art.pget(sx, sy) as usize & 7;
                        votes[c] += 1 + rank_of[c];
                    }
                }
                let mut best = 0;
                for c in 1..8 {
                    if votes[c] > votes[best] {
                        best = c;
                    }
                }
                self.out.pset(x + tx, y + ty, best as i32);
            }
        }
        // the caption: the title, set in the headline face, never sampled
        self.out.rect(x, y + ART_H, TILE_W, CAP_H, 0);
        self.out.line(x, y + ART_H, x + TILE_W - 1, y + ART_H, 1);
        let title = say(&e.title);
        let sel = at == self.sel;
        let colour = if sel { 7 } else { 6 };
        let n = title.chars().count() as i32;
        if n * HEADLINE_WIDTH <= TILE_W {
            // the headline face, whenever it fits
            headline(&mut self.out, &title, x + (TILE_W - n * HEADLINE_WIDTH) / 2, y + ART_H + 3, colour, 1);
        } else {
            // a long name drops to the small face rather than losing its tail
            let title: String = title.chars().take((TILE_W / CHAR_WIDTH) as usize).collect();
            let tw = title.chars().count() as i32 * CHAR_WIDTH;
            self.out.print(&title, x + (TILE_W - tw) / 2, y + ART_H + 4, colour, 1);
        }
        if e.draft {
            self.out.rect(x + TILE_W - 4, y + 1, 3, 3, 2);
        }
        self.out.rectb(x - 1, y - 1, TILE_W + 2, TILE_H + 2, if sel { 7 } else { 1 });
    }

    /// A small solid triangle, for "there is more this way".
    fn arrow(&mut self, cx: i32, y: i32, up: bool, c: i32) {
        for i in 0..3 {
            let w = 1 + i * 2;
            let row = if up { y + i } else { y + 2 - i };
            self.out.rect(cx - i, row, w, 1, c);
        }
    }

    fn draw_grid(&mut self) {
        self.out.cls(0);

        let sel = self.sel;
        let title = say(&self.entries[sel].title);
        let colour = if self.entries[sel].draft { 2 } else { 7 };
        headline(&mut self.out, &title, 4, 3, colour, 1);

        let best = self.entries[sel].best;
        if best > 0 {
            let label = say(&format!("best {best}"));
            let x = W - 3 - label.chars().count() as i32 * CHAR_WIDTH;
            self.out.print(&label, x, 4, 6, 1);
        }
        self.out.line(0, 13, W - 1, 13, 1);

        let first = self.scroll * COLS;
        for slot in 0..COLS * VIS_ROWS {
            let at = first + slot;
            if at >= self.entries.len() {
                break;
            }
            let x = X0 + (slot % COLS) as i32 * (TILE_W + GAP);
            let y = GY + (slot / COLS) as i32 * (TILE_H + GAP);
            self.draw_tile(at, x, y);
        }

        // How much shelf is off-screen, in the margin the tiles do not use.
        if self.scroll > 0 {
            self.arrow(W / 2, GY - 3, true, 1);
        }
        if self.scroll + VIS_ROWS < self.rows() {
            self.arrow(W / 2, GY + VIS_ROWS as i32 * (TILE_H + GAP), false, 1);
        }

        self.out.line(0, H - 24, W - 1, H - 24, 1);
        let hint = say("o play   x info");
        self.out.print(&hint, centre(&hint, 1), H - 18, 6, 1);
        let count = say(&format!("{} of {}", self.sel + 1, self.entries.len()));
        self.out.print(&count, centre(&count, 1), H - 9, 1, 1);
    }

    fn draw_info(&mut self) {
        self.out.cls(0);
        let e = &self.entries[self.sel];

        let title = say(&e.title);
        // Two sizes and a rule for choosing: whichever still fits on the line.
        let scale = if title.chars().count() as i32 * HEADLINE_WIDTH * 2 <= W - 8 { 2 } else { 1 };
        headline(&mut self.out, &title, headline_centre(&title, scale), 14, 7, scale);

        let by = say(&format!("by {}", e.author));
        self.out.print(&by, centre(&by, 1), 38, 1, 1);

        let about = say(&e.about);
        let mut y = 58;
        for line in wrap(&about, 48) {
            self.out.print(&line, centre(&line, 1), y, 6, 1);
            y += 9;
        }

        let mut y = 88;
        if e.best > 0 {
            let best = say(&format!("best {}", e.best));
            self.out.print(&best, centre(&best, 1), y, 4, 1);
            y += 11;
        }

        // The thing Mega Micromachee needed the shelf to say out loud: a
        // nonogram is a fine game and a terrible ten seconds, and the player
        // should be able to see which of the two a cart is before it turns up.
        if e.id != mega::MEGA_ID {
            let (text, c) = if e.in_mega {
                ("plays in mega", 5)
            } else {
                ("too slow for mega", 1)
            };
            let line = say(text);
            self.out.print(&line, centre(&line, 1), y, c, 1);
            y += 11;
        }

        if e.draft {
            let line = say("draft — not published");
            self.out.print(&line, centre(&line, 1), y, 2, 1);
        }

        self.out.line(0, H - 24, W - 1, H - 24, 1);
        let hint = say("o play   x back");
        self.out.print(&hint, centre(&hint, 1), H - 16, 6, 1);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dummy(n: usize) -> Browse {
        let mut b = Browse {
            entries: Vec::new(),
            sel: 0,
            scroll: 0,
            info: false,
            last: 0,
            picked: None,
            sfx: Vec::new(),
            make: false,
            intro: 0,
            tick: 0,
            out: Screen::new(),
        };
        for i in 0..n {
            b.entries.push(Entry {
                id: format!("c{i}"),
                title: format!("Cart {i}"),
                author: "pixygon".into(),
                about: "a small thing that does a small thing".into(),
                best: i as i64,
                draft: false,
                in_mega: i % 2 == 0,
                art: placeholder("C")
            });
        }
        b
    }

    fn press(b: &mut Browse, button: u8) {
        b.frame(1 << button);
        b.frame(0);
    }

    #[test]
    fn every_cart_can_be_reached_with_the_buttons_alone() {
        // The shelf is keyboard-only now, so "reachable" is the whole contract.
        let mut b = dummy(10);
        let mut seen = std::collections::HashSet::new();
        for _ in 0..10 {
            seen.insert(b.sel);
            press(&mut b, 1);
        }
        assert_eq!(seen.len(), 10, "walking right did not visit every cart");

        // and back again
        let mut b = dummy(10);
        for _ in 0..9 {
            press(&mut b, 1);
        }
        assert_eq!(b.sel, 9);
        for _ in 0..9 {
            press(&mut b, 0);
        }
        assert_eq!(b.sel, 0);
    }

    #[test]
    fn down_from_a_ragged_last_row_still_lands_somewhere() {
        // Ten carts is three full rows and one lonely tile. Pressing down in
        // the third column of row three used to be a no-op.
        let mut b = dummy(10);
        b.move_to(8);
        press(&mut b, 3);
        assert_eq!(b.sel, 9, "down from the last full row went nowhere");
    }

    #[test]
    fn the_selection_never_leaves_the_screen() {
        let mut b = dummy(10);
        for _ in 0..12 {
            press(&mut b, 3);
            let row = b.sel / COLS;
            assert!(
                row >= b.scroll && row < b.scroll + VIS_ROWS,
                "selection on row {row} with the window at {}",
                b.scroll
            );
        }
        for _ in 0..12 {
            press(&mut b, 2);
            let row = b.sel / COLS;
            assert!(row >= b.scroll && row < b.scroll + VIS_ROWS);
        }
    }

    #[test]
    fn the_make_tile_is_not_a_cart() {
        // Picking it must not come back as an id, or the panel would try to
        // load a cart called "make" and fail in a way nobody could read.
        let mut b = dummy(3);
        b.entries.push(Entry {
            id: MAKE_ID.into(),
            title: "Make a game".into(),
            author: "you".into(),
            about: "say what it is".into(),
            best: 0,
            draft: false,
            in_mega: false,
            art: make_tile()
        });
        b.move_to(3);
        press(&mut b, 4);
        assert!(b.wants_make(), "O on the make tile did not ask for the make flow");
        assert!(b.picked().is_none(), "it came back as a cart id as well");
    }

    #[test]
    fn the_titles_play_once_and_can_be_skipped() {
        let mut b = dummy(4);
        b.intro = INTRO;
        b.frame(0);
        assert!(b.intro > 0, "the titles ended before they began");
        b.frame(1 << 1);
        assert_eq!(b.intro, 0, "a button did not skip the titles");
        // and skipping must not also move the selection or start anything
        assert_eq!(b.sel, 0);
        assert!(b.picked().is_none());
    }

    #[test]
    fn info_is_the_alt_button_and_play_is_the_other_one() {
        let mut b = dummy(4);
        press(&mut b, 5);
        assert!(b.info, "X did not open the info card");
        assert!(b.picked().is_none(), "opening info must not start anything");
        press(&mut b, 5);
        assert!(!b.info, "X did not close it again");

        press(&mut b, 5);
        press(&mut b, 4);
        assert_eq!(b.picked(), Some("c0"), "O from the info card did not play it");
    }

    #[test]
    fn moving_does_not_start_a_game() {
        let mut b = dummy(6);
        for button in [0, 1, 2, 3] {
            press(&mut b, button);
        }
        assert!(b.picked().is_none());
    }

    #[test]
    fn a_held_button_moves_one_tile_not_every_frame() {
        // Buttons are edge-triggered here for the same reason they are in a
        // cart: a held key at thirty frames a second is not a choice.
        let mut b = dummy(9);
        for _ in 0..20 {
            b.frame(1 << 1);
        }
        assert_eq!(b.sel, 1);
    }

    #[test]
    fn every_frame_is_a_full_screen() {
        let mut b = dummy(7);
        let s = b.frame(0);
        assert_eq!(s.pget(0, 0), 0);
        // the header rule, drawn in slot 1, proves the frame was actually drawn
        assert_eq!(s.pget(64, 13), 1);
        press(&mut b, 5);
        let s = b.frame(0);
        assert_eq!(s.pget(64, H - 24), 1);
    }

    #[test]
    fn long_words_wrap_without_being_lost() {
        let lines = wrap("the numbers describe a sign. carve it", 30);
        assert!(lines.len() >= 2);
        let back = lines.join(" ");
        assert_eq!(back, "the numbers describe a sign. carve it");
        for l in &lines {
            assert!(l.chars().count() <= 30, "{l} is too wide for the screen");
        }
        assert!(wrap("", 30).is_empty());
    }
}
