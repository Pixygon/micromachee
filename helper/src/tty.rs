//! Playing a cart in the terminal.
//!
//! The bar widget is one front end and this is another, but they are not the
//! same shape. `play` speaks a protocol down a pipe because QML is on the far
//! end of it; here there is no far end. The cart runs in this process and its
//! framebuffer goes straight to the terminal — no PNG, no base64, no second
//! process, and so no pipe to break.
//!
//! Pixels become half-blocks: one character cell is two pixels stacked, `▀`
//! with the foreground the top pixel and the background the bottom, so a
//! 240×160 screen is 240×80 cells.
//!
//! No crate is pulled in for any of this. Raw mode, echo and the window size
//! all come from `stty`, which is already on any machine that has a terminal
//! to ask about — the same reasoning that made the PNG encoder hand-written.
//!
//! ## The one thing a terminal cannot do
//!
//! It cannot tell you a key was **released**. So a press is held briefly and
//! then let go on a timer. `btnp` games are exact. `btn` games feel right while
//! you hold the key, because the terminal's own key-repeat keeps renewing it.

use std::io::{IsTerminal, Read, Write};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

use crate::cart::Cart;
use crate::console;
use crate::shelf;
use crate::theme::{self, Palette};
use crate::vm::{Machine, FPS};

/// How long a keypress counts as held. Long enough that `btn` games move while
/// you lean on a key, short enough that letting go stops you promptly.
const HOLD: Duration = Duration::from_millis(110);

fn stty(args: &[&str]) -> Option<String> {
    let out = Command::new("stty")
        .args(args)
        .stdin(Stdio::inherit())
        .output()
        .ok()?;
    if !out.status.success() {
        return None;
    }
    Some(String::from_utf8_lossy(&out.stdout).trim().to_string())
}

fn term_size() -> (usize, usize) {
    if let Some(s) = stty(&["size"]) {
        let mut it = s.split_whitespace();
        if let (Some(r), Some(c)) = (it.next(), it.next()) {
            if let (Ok(r), Ok(c)) = (r.parse::<usize>(), c.parse::<usize>()) {
                // A pty with no size set answers "0 0". That is "do not know",
                // not "a terminal with no room in it".
                if r > 0 && c > 0 {
                    return (r, c);
                }
            }
        }
    }
    (84, 240)
}

/// Puts the terminal back however we leave — a normal quit, an error, or a
/// panic. Getting this wrong hands somebody a shell with no echo and no
/// newlines, which they have to fix blind, so it is a `Drop` rather than a
/// line at the end of the loop.
struct RawMode(Option<String>);

impl RawMode {
    fn enter() -> RawMode {
        let saved = stty(&["-g"]);
        // min 0 / time 0: a read returns immediately with nothing rather than
        // blocking, which is what lets one thread do input and frames both.
        stty(&["raw", "-echo", "min", "0", "time", "0"]);
        print!("\x1b[?25l\x1b[2J");
        let _ = std::io::stdout().flush();
        RawMode(saved)
    }
}

impl Drop for RawMode {
    fn drop(&mut self) {
        print!("\x1b[0m\x1b[?25h\r\n");
        let _ = std::io::stdout().flush();
        match &self.0 {
            Some(saved) => stty(&[saved.as_str()]),
            None => stty(&["sane"]),
        };
    }
}

/// 0 left · 1 right · 2 up · 3 down · 4 O · 5 X
fn button(b: u8) -> Option<usize> {
    Some(match b {
        b'a' | b'A' => 0,
        b'd' | b'D' => 1,
        b'w' | b'W' => 2,
        b's' | b'S' => 3,
        b'z' | b'Z' | b' ' | b'\r' | b'\n' => 4,
        b'x' | b'X' => 5,
        _ => return None,
    })
}

fn rows(px: &[u8], palette: &Palette, step: usize) -> Vec<String> {
    let (w, h) = (console::W as usize, console::H as usize);
    let mut out = Vec::with_capacity(h / (2 * step));
    let mut y = 0;
    while y < h {
        let mut line = String::with_capacity(w / step * 6);
        let (mut fg, mut bg) = (None, None);
        let mut x = 0;
        while x < w {
            let top = palette[px[y * w + x] as usize];
            let bot = if y + step < h {
                palette[px[(y + step) * w + x] as usize]
            } else {
                (0, 0, 0)
            };
            // A colour is only named when it changes. Half the bytes of a frame
            // are escape codes otherwise.
            if Some(top) != fg {
                line.push_str(&format!("\x1b[38;2;{};{};{}m", top.0, top.1, top.2));
                fg = Some(top);
            }
            if Some(bot) != bg {
                line.push_str(&format!("\x1b[48;2;{};{};{}m", bot.0, bot.1, bot.2));
                bg = Some(bot);
            }
            line.push('▀');
            x += step;
        }
        line.push_str("\x1b[0m");
        out.push(line);
        y += 2 * step;
    }
    out
}

pub fn play(id: &str) -> i32 {
    if !std::io::stdout().is_terminal() {
        eprintln!("✗ this draws to a terminal — down a pipe you want `micromachee play {id}`");
        return 2;
    }
    let Some(path) = shelf::find(id) else {
        eprintln!("✗ no cart called {id}");
        return 2;
    };
    let cart = match Cart::load(&path) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("✗ {e}");
            return 1;
        }
    };
    let machine = match Machine::load(&cart) {
        Ok(m) => m,
        Err(e) => {
            eprintln!("✗ {e}");
            return 1;
        }
    };

    let (h, w) = term_size();
    let step = if w >= 240 && h >= 84 { 1 } else { 2 };
    if step == 2 && (w < 64 || h < 36) {
        eprintln!("✗ this terminal is {w}x{h}; a cart needs 120x44, or 240x84 for one cell per pixel");
        return 2;
    }
    let palette = theme::active(shelf::saved_theme().as_deref()).palette;

    // The guard is scoped so the terminal is back to normal before anything is
    // printed about what went wrong.
    let failure = {
        let _raw = RawMode::enter();
        run(&machine, &cart, &palette, step)
    };
    match failure {
        Some(e) => {
            eprintln!("✗ {e}");
            1
        }
        None => 0,
    }
}

fn run(machine: &Machine, cart: &Cart, palette: &Palette, step: usize) -> Option<String> {
    let mut stdin = std::io::stdin();
    let mut out = std::io::stdout();
    let mut buf = [0u8; 64];
    let mut until: [Option<Instant>; 6] = [None; 6];
    let mut prev: Vec<String> = Vec::new();
    let mut last_score = i64::MIN;
    let frame = Duration::from_micros(1_000_000 / FPS as u64);
    let mut next = Instant::now();

    if let Err(e) = machine.init() {
        return Some(e);
    }

    loop {
        // ── input ───────────────────────────────────────────────────────────
        // Bounded rather than "until empty": a wedged terminal handing back
        // bytes forever must not stop the frames.
        for _ in 0..8 {
            let n = match stdin.read(&mut buf) {
                Ok(0) | Err(_) => break,
                Ok(n) => n,
            };
            let mut i = 0;
            while i < n {
                let b = buf[i];
                // An arrow is three bytes. Walking the buffer rather than
                // matching it whole keeps a fast tapper from losing presses,
                // and means a lone ESC — the start of an arrow — is ignored
                // rather than read as a quit. Hence `q` and not Escape.
                if b == 0x1b && i + 2 < n && buf[i + 1] == b'[' {
                    let bit = match buf[i + 2] {
                        b'D' => Some(0),
                        b'C' => Some(1),
                        b'A' => Some(2),
                        b'B' => Some(3),
                        _ => None,
                    };
                    if let Some(bit) = bit {
                        until[bit] = Some(Instant::now() + HOLD);
                    }
                    i += 3;
                } else {
                    if b == b'q' || b == b'Q' || b == 0x03 {
                        return None;
                    }
                    if let Some(bit) = button(b) {
                        until[bit] = Some(Instant::now() + HOLD);
                    }
                    i += 1;
                }
            }
            if n < buf.len() {
                break;
            }
        }

        let now = Instant::now();
        let mut held = 0u8;
        for (bit, u) in until.iter_mut().enumerate() {
            match *u {
                Some(t) if t > now => held |= 1 << bit,
                Some(_) => *u = None,
                None => {}
            }
        }

        // ── a turn of the machine ───────────────────────────────────────────
        machine.set_held(held);
        if let Err(e) = machine.update() {
            return Some(e);
        }
        if let Err(e) = machine.draw() {
            return Some(e);
        }

        // ── draw only what moved ────────────────────────────────────────────
        // A whole frame is tens of kilobytes of escape codes; thirty of those a
        // second is a megabyte, which a terminal notices and a terminal over
        // ssh notices a great deal. Most games hold most of the screen still.
        let cells = rows(&machine.screen.borrow().px, palette, step);
        let mut paint = String::new();
        for (n, row) in cells.iter().enumerate() {
            if prev.get(n) != Some(row) {
                paint.push_str(&format!("\x1b[{};1H", n + 1));
                paint.push_str(row);
            }
        }
        let score = machine.score.get();
        paint.push_str(&format!(
            "\x1b[{};1H  {}   score {}   arrows/wasd · z x · q quits\x1b[K",
            cells.len() + 1,
            cart.title,
            score
        ));
        prev = cells;
        if out.write_all(paint.as_bytes()).is_err() || out.flush().is_err() {
            return None;
        }

        if score != last_score {
            last_score = score;
            shelf::record_score(&cart.id, score);
        }

        next += frame;
        let now = Instant::now();
        if next > now {
            std::thread::sleep(next - now);
        } else {
            next = now; // fell behind; do not try to catch up
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn grey() -> Palette {
        let mut p = [(0, 0, 0); 8];
        for i in 0..8 {
            p[i] = ((i * 36) as u8, (i * 36) as u8, (i * 36) as u8);
        }
        p
    }

    #[test]
    fn a_frame_is_half_as_many_rows_as_pixels() {
        let px = vec![0u8; (console::W * console::H) as usize];
        assert_eq!(rows(&px, &grey(), 1).len(), console::H as usize / 2);
        assert_eq!(rows(&px, &grey(), 2).len(), console::H as usize / 4);
    }

    #[test]
    fn every_row_holds_one_cell_per_pixel_column() {
        let px = vec![3u8; (console::W * console::H) as usize];
        let r = rows(&px, &grey(), 1);
        assert_eq!(r[0].matches('▀').count(), console::W as usize);
        assert_eq!(rows(&px, &grey(), 2)[0].matches('▀').count(), console::W as usize / 2);
    }

    #[test]
    fn a_flat_row_names_its_colours_once() {
        // The whole reason a still screen costs nothing to redraw.
        let px = vec![5u8; (console::W * console::H) as usize];
        let r = rows(&px, &grey(), 1);
        assert_eq!(r[0].matches("\x1b[38;2;").count(), 1, "one foreground for the row");
        assert_eq!(r[0].matches("\x1b[48;2;").count(), 1, "one background for the row");
    }

    #[test]
    fn identical_frames_produce_identical_rows() {
        // Which is what the diff in `run` relies on to skip them.
        let a = vec![2u8; (console::W * console::H) as usize];
        let b = a.clone();
        assert_eq!(rows(&a, &grey(), 1), rows(&b, &grey(), 1));
    }

    #[test]
    fn a_changed_pixel_changes_exactly_one_row() {
        let mut px = vec![0u8; (console::W * console::H) as usize];
        let before = rows(&px, &grey(), 1);
        px[(40 * console::W + 7) as usize] = 6;   // row 40 lands in cell-row 20
        let after = rows(&px, &grey(), 1);
        let differing: Vec<usize> = (0..before.len()).filter(|&i| before[i] != after[i]).collect();
        assert_eq!(differing, vec![20]);
    }

    #[test]
    fn the_buttons_are_the_ones_the_carts_use() {
        assert_eq!(button(b'a'), Some(0));
        assert_eq!(button(b'd'), Some(1));
        assert_eq!(button(b'w'), Some(2));
        assert_eq!(button(b's'), Some(3));
        assert_eq!(button(b'z'), Some(4));
        assert_eq!(button(b' '), Some(4));
        assert_eq!(button(b'x'), Some(5));
        assert_eq!(button(b'k'), None);
    }
}
