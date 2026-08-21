//! The shelf, drawn by the console rather than around it.
//!
//! It used to be a grid of QML tiles sitting outside the screen, which meant
//! the thing you picked a game with was not made of the same pixels as the
//! game. Everything here goes through the same 128×128 `Screen` and the same
//! six buttons a cart gets, so the shelf is simply the first program the
//! console runs.
//!
//! Covers are the carts' own `_cover()` output, sampled down into a tile. Only
//! the top 96 rows are sampled: nearly every cover paints its title across the
//! bottom third, and a title reduced to a ninth of its size is a smear. The
//! name of the selected cart is spelled out in the header instead, at a size
//! the font was drawn for.

use crate::cart::Cart;
use crate::console::{Screen, CHAR_WIDTH, W};
use crate::mega;
use crate::shelf;
use crate::vm::Machine;

const COLS: usize = 3;
const TILE: i32 = 38;
const GAP: i32 = 3;
const X0: i32 = 4; // 3 × 38 + 2 × 3 = 120, so four pixels of margin each side
const GY: i32 = 16;
const VIS_ROWS: usize = 2;

/// The part of a cover that is picture rather than title card. Carts paint
/// their name across the bottom third; Mega's own cover starts its band a
/// little higher, and sampling into a title makes a smear rather than a
/// thumbnail.
const COVER_ART: i32 = 96;
const MEGA_ART: i32 = 82;

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
    /// How many rows of `art` are picture.
    art_rows: i32,
}

pub struct Browse {
    entries: Vec<Entry>,
    sel: usize,
    scroll: usize,
    info: bool,
    last: u8,
    picked: Option<String>,
    out: Screen,
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

/// A cart that will not run still needs a tile, so it gets its initial.
fn placeholder(title: &str) -> Screen {
    let mut s = Screen::new();
    s.cls(0);
    let initial: String = title.chars().take(1).collect::<String>().to_uppercase();
    s.print(&initial, centre(&initial, 6), 24, 1, 6);
    s
}

impl Browse {
    pub fn new() -> Self {
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
            art: mega::Mega::cover(),
            art_rows: MEGA_ART,
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
                art,
                art_rows: COVER_ART,
            });
        }

        Self { entries, sel: 0, scroll: 0, info: false, last: 0, picked: None, out: Screen::new() }
    }

    /// The cart the player chose, once they have chosen one.
    pub fn picked(&self) -> Option<&str> {
        self.picked.as_deref()
    }

    fn rows(&self) -> usize {
        self.entries.len().div_ceil(COLS)
    }

    fn move_to(&mut self, next: usize) {
        self.sel = next.min(self.entries.len().saturating_sub(1));
        // Keep the selection inside the two rows on screen, and no further —
        // scrolling by a whole page loses the player their place.
        let row = self.sel / COLS;
        if row < self.scroll {
            self.scroll = row;
        } else if row >= self.scroll + VIS_ROWS {
            self.scroll = row + 1 - VIS_ROWS;
        }
    }

    /// One frame. `held` is the same bitmask a cart sees.
    pub fn frame(&mut self, held: u8) -> &Screen {
        let pressed = held & !self.last;
        self.last = held;
        let hit = |b: u8| pressed & (1 << b) != 0;

        if self.entries.is_empty() {
            self.draw_empty();
            return &self.out;
        }

        if self.info {
            if hit(4) {
                self.picked = Some(self.entries[self.sel].id.clone());
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
            self.picked = Some(self.entries[self.sel].id.clone());
        }
        if hit(5) {
            self.info = true;
        }

        self.draw_grid();
        &self.out
    }

    // ── drawing ─────────────────────────────────────────────────────────────

    fn draw_empty(&mut self) {
        self.out.cls(0);
        let a = say("nothing on the shelf");
        let b = say("run micromachee sync");
        self.out.print(&a, centre(&a, 1), 56, 2, 1);
        self.out.print(&b, centre(&b, 1), 68, 1, 1);
    }

    /// One cover, sampled down into a tile. Nearest neighbour: a cover is pixel
    /// art, and averaging pixel art produces mud.
    fn draw_tile(&mut self, at: usize, x: i32, y: i32) {
        for ty in 0..TILE {
            let sy = ty * self.entries[at].art_rows / TILE;
            for tx in 0..TILE {
                let sx = tx * W / TILE;
                let c = self.entries[at].art.pget(sx, sy) as i32;
                self.out.pset(x + tx, y + ty, c);
            }
        }
        if self.entries[at].draft {
            self.out.rect(x + TILE - 4, y + 1, 3, 3, 2);
        }
        if at == self.sel {
            self.out.rectb(x - 1, y - 1, TILE + 2, TILE + 2, 7);
        } else {
            self.out.rectb(x - 1, y - 1, TILE + 2, TILE + 2, 1);
        }
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
        self.out.print(&title, 3, 4, colour, 1);

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
            let x = X0 + (slot % COLS) as i32 * (TILE + GAP);
            let y = GY + (slot / COLS) as i32 * (TILE + GAP);
            self.draw_tile(at, x, y);
        }

        // How much shelf is off-screen, in the margin the tiles do not use.
        if self.scroll > 0 {
            self.arrow(W / 2, GY - 2, true, 1);
        }
        if self.scroll + VIS_ROWS < self.rows() {
            self.arrow(W / 2, GY + VIS_ROWS as i32 * (TILE + GAP), false, 1);
        }

        self.out.line(0, 104, W - 1, 104, 1);
        let hint = say("o play   x info");
        self.out.print(&hint, centre(&hint, 1), 110, 6, 1);
        let count = say(&format!("{} of {}", self.sel + 1, self.entries.len()));
        self.out.print(&count, centre(&count, 1), 119, 1, 1);
    }

    fn draw_info(&mut self) {
        self.out.cls(0);
        let e = &self.entries[self.sel];

        let title = say(&e.title);
        // Two sizes and a rule for choosing: whichever still fits on the line.
        let scale = if title.chars().count() as i32 * CHAR_WIDTH * 2 <= W - 8 { 2 } else { 1 };
        self.out.print(&title, centre(&title, scale), 10, 7, scale);

        let by = say(&format!("by {}", e.author));
        self.out.print(&by, centre(&by, 1), 28, 1, 1);

        let about = say(&e.about);
        let mut y = 46;
        for line in wrap(&about, 30) {
            self.out.print(&line, centre(&line, 1), y, 6, 1);
            y += 9;
        }

        let mut y = 70;
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

        self.out.line(0, 104, W - 1, 104, 1);
        let hint = say("o play   x back");
        self.out.print(&hint, centre(&hint, 1), 112, 6, 1);
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
                art: placeholder("C"),
                art_rows: COVER_ART,
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
        assert_eq!(s.pget(64, 104), 1);
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
