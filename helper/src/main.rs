//! micromachee — a 128×128, eight-colour console that lives in a bar.
//!
//! The bar runs `play`, which is a long-lived process printing one base64 PNG
//! per line and reading button state on stdin. Everything else is for making
//! games:
//!
//!   micromachee new <name>       write a starting cart that already plays
//!   micromachee check <file>     does it load, and survive two minutes?
//!   micromachee shot <file>      render a frame to PNG and look at it
//!
//! Those last two exist so that writing a game does not require a bar, a
//! compositor, or a person watching. An agent can write a cart, run `check`,
//! read the error, fix it, run `shot`, and look at what it made.

mod cart;
mod console;
mod palettes;
mod png;
mod sha256;
mod shelf;
mod theme;
mod tty;
mod vm;

use std::io::{BufRead, IsTerminal, Write};
use std::sync::atomic::{AtomicBool, AtomicU8, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

use cart::{Cart, MAX_CART_BYTES};
use vm::{Machine, FPS};

fn base64(data: &[u8]) -> String {
    const T: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::with_capacity(data.len().div_ceil(3) * 4);
    for c in data.chunks(3) {
        let b = [c[0], *c.get(1).unwrap_or(&0), *c.get(2).unwrap_or(&0)];
        let n = ((b[0] as u32) << 16) | ((b[1] as u32) << 8) | b[2] as u32;
        out.push(T[(n >> 18 & 63) as usize] as char);
        out.push(T[(n >> 12 & 63) as usize] as char);
        out.push(if c.len() > 1 { T[(n >> 6 & 63) as usize] as char } else { '=' });
        out.push(if c.len() > 2 { T[(n & 63) as usize] as char } else { '=' });
    }
    out
}

// ── play ────────────────────────────────────────────────────────────────────

/// Long-lived. One line per frame: `F <base64 png>`; `E <message>` and exit if
/// the cart dies. Reads `B <bitmask>` on stdin for buttons, `Q` to stop.
fn cmd_play(id: &str) -> i32 {
    // `play` prints eleven kilobytes of base64 thirty times a second. Nobody
    // typing it at a prompt wants that, and the fix is one word away.
    if std::io::stdout().is_terminal() {
        eprintln!("note: `play` prints a frame protocol for the bar. To play it here: micromachee tty {id}");
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

    // stdin blocks, so it gets its own thread and hands the loop a byte.
    let held = Arc::new(AtomicU8::new(0));
    let quit = Arc::new(AtomicBool::new(false));
    {
        let (held, quit) = (held.clone(), quit.clone());
        std::thread::spawn(move || {
            let stdin = std::io::stdin();
            for line in stdin.lock().lines() {
                let Ok(line) = line else { break };
                let line = line.trim();
                if let Some(bits) = line.strip_prefix("B ") {
                    if let Ok(v) = bits.trim().parse::<u8>() {
                        held.store(v, Ordering::Relaxed);
                    }
                } else if line == "Q" {
                    break;
                }
            }
            quit.store(true, Ordering::Relaxed);
        });
    }

    let palette = theme::active(shelf::saved_theme().as_deref()).palette;
    let out = std::io::stdout();
    let mut out = out.lock();
    let fail = |out: &mut dyn Write, e: String| {
        let _ = writeln!(out, "E {e}");
        let _ = out.flush();
    };

    if let Err(e) = machine.init() {
        fail(&mut out, e);
        return 1;
    }

    let step = Duration::from_micros(1_000_000 / FPS as u64);
    let mut next = Instant::now();
    let mut last_score = i64::MIN;
    while !quit.load(Ordering::Relaxed) {
        machine.set_held(held.load(Ordering::Relaxed));
        if let Err(e) = machine.update() {
            fail(&mut out, e);
            return 1;
        }
        if let Err(e) = machine.draw() {
            fail(&mut out, e);
            return 1;
        }
        let frame = machine.screen.borrow().to_png(&palette);
        if writeln!(out, "F {}", base64(&frame)).is_err() || out.flush().is_err() {
            break; // the panel closed; that is a normal ending
        }
        let score = machine.score.get();
        if score != last_score {
            last_score = score;
            let _ = writeln!(out, "S {score}");
            let _ = out.flush();
            shelf::record_score(&cart.id, score);
        }

        next += step;
        let now = Instant::now();
        if next > now {
            std::thread::sleep(next - now);
        } else {
            next = now; // fell behind; do not try to catch up
        }
    }
    0
}

// ── authoring ───────────────────────────────────────────────────────────────

/// Load a cart and play it blind for a while, pressing buttons at random.
///
/// The point is that a cart which crashes on frame 300, or only when you press
/// two buttons at once, fails here rather than in somebody's bar.
fn cmd_check(file: &str) -> i32 {
    let path = std::path::Path::new(file);
    let cart = match Cart::load(path) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("✗ {e}");
            return 1;
        }
    };
    println!(
        "  {} by {} — {} bytes of {} ({}% of a cart)",
        cart.title,
        cart.author,
        cart.bytes,
        MAX_CART_BYTES,
        cart.bytes * 100 / MAX_CART_BYTES
    );

    for w in cart.warnings() {
        println!("  ⚠ {w}");
    }

    let machine = match Machine::load(&cart) {
        Ok(m) => m,
        Err(e) => {
            eprintln!("✗ it does not load: {e}");
            return 1;
        }
    };
    if let Err(e) = machine.init() {
        eprintln!("✗ _init() failed: {e}");
        return 1;
    }

    let frames = FPS * 60; // a minute of play
    let mut seed = 0x9e37_79b9u32;
    let mut drew_something = false;
    for f in 0..frames {
        // A cheap deterministic input pattern: buttons change every ~half
        // second, sometimes several at once, so the run is reproducible.
        seed = seed.wrapping_mul(1_664_525).wrapping_add(1_013_904_223);
        if f % 15 == 0 {
            machine.set_held((seed >> 13) as u8 & 0b0011_1111);
        }
        if let Err(e) = machine.update() {
            eprintln!("✗ _update() failed on frame {f}: {e}");
            return 1;
        }
        if let Err(e) = machine.draw() {
            eprintln!("✗ _draw() failed on frame {f}: {e}");
            return 1;
        }
        if !drew_something {
            let s = machine.screen.borrow();
            let first = s.px[0];
            drew_something = s.px.iter().any(|&p| p != first);
        }
    }

    if !drew_something {
        // Not fatal — a game may legitimately hold one colour — but it is
        // nearly always a cart that forgot to draw.
        println!("  ⚠ every frame was a single flat colour. Did _draw() draw?");
    }
    println!("  ran {frames} frames with random input, no errors");
    println!("✓ {} is a good cart", cart.id);
    0
}

fn cmd_shot(args: &[String]) -> i32 {
    let mut file = None;
    let mut out = "shot.png".to_string();
    let mut frames = 1u32;
    let mut hold = 0u8;
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "-o" => {
                i += 1;
                out = args.get(i).cloned().unwrap_or(out);
            }
            "--frames" => {
                i += 1;
                frames = args.get(i).and_then(|v| v.parse().ok()).unwrap_or(1);
            }
            // Without this you can only ever photograph a game that nobody is
            // playing — which for most games is the title card or the death
            // screen, and never the thing you actually wanted to look at.
            "--hold" => {
                i += 1;
                for part in args.get(i).map(String::as_str).unwrap_or("").split(',') {
                    if let Ok(b) = part.trim().parse::<u8>() {
                        if b <= 5 {
                            hold |= 1 << b;
                        }
                    }
                }
            }
            other => file = Some(other.to_string()),
        }
        i += 1;
    }
    let Some(file) = file else {
        eprintln!("✗ shot what? try: micromachee shot mygame.lua --frames 60 --hold 2 -o look.png");
        return 2;
    };
    let cart = match Cart::load(std::path::Path::new(&file)) {
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
    if let Err(e) = machine.init() {
        eprintln!("✗ _init() failed: {e}");
        return 1;
    }
    machine.set_held(hold);
    for f in 0..frames.max(1) {
        if let Err(e) = machine.update() {
            eprintln!("✗ _update() failed on frame {f}: {e}");
            return 1;
        }
        if let Err(e) = machine.draw() {
            eprintln!("✗ _draw() failed on frame {f}: {e}");
            return 1;
        }
    }
    let palette = theme::active(shelf::saved_theme().as_deref()).palette;
    let frame = machine.screen.borrow().to_png(&palette);
    match std::fs::write(&out, frame) {
        Ok(()) => {
            println!("wrote {out} — frame {frames} of {}", cart.title);
            0
        }
        Err(e) => {
            eprintln!("✗ could not write {out}: {e}");
            1
        }
    }
}

fn cmd_new(args: &[String]) -> i32 {
    let Some(name) = args.first() else {
        eprintln!("✗ name it: micromachee new \"my game\"");
        return 2;
    };
    let id = name
        .to_lowercase()
        .chars()
        .map(|c| if c.is_ascii_alphanumeric() { c } else { '-' })
        .collect::<String>()
        .trim_matches('-')
        .to_string();
    let out = args.get(1).cloned().unwrap_or_else(|| format!("{id}.lua"));
    if std::path::Path::new(&out).exists() {
        eprintln!("✗ {out} already exists — not overwriting it");
        return 1;
    }
    match std::fs::write(&out, cart::scaffold(name)) {
        Ok(()) => {
            println!("wrote {out}");
            println!("  micromachee check {out}     does it hold up?");
            println!("  micromachee shot  {out}     look at it");
            0
        }
        Err(e) => {
            eprintln!("✗ could not write {out}: {e}");
            1
        }
    }
}

// ── the bar ─────────────────────────────────────────────────────────────────

fn cmd_status() {
    let carts = shelf::list();
    let state = shelf::load_state();
    let th = theme::active(shelf::saved_theme().as_deref());
    let last = state
        .get("last")
        .and_then(|v| v.as_str())
        .and_then(|id| carts.iter().find(|c| c.id == id))
        .or_else(|| carts.first());
    let headline = match last {
        Some(c) => c.title.clone(),
        None => "no carts".into(),
    };
    println!(
        "{}",
        serde_json::json!({
            "ready": !carts.is_empty(),
            "headline": headline,
            "count": carts.len(),
            // The shell travels with the palette so the QML never picks a
            // colour of its own — a bar widget that themes half of itself is
            // worse than one that does not theme at all.
            "theme": th.id,
            "themes": theme::ids(),
            "shell": {
                "body": th.shell.body, "bezel": th.shell.bezel,
                "text": th.shell.text, "dim": th.shell.dim, "accent": th.shell.accent,
            },
            "carts": carts.iter().map(|c| serde_json::json!({
                "id": c.id,
                "title": c.title,
                "author": c.author,
                "about": c.about,
                "bytes": c.bytes,
                "best": shelf::best(&c.id),
            })).collect::<Vec<_>>(),
        })
    );
}

fn cmd_doctor() -> i32 {
    println!("carts dir  : {}", shelf::carts_dir().display());
    println!("state file : {}", shelf::state_path().display());
    println!("catalog    : {}", shelf::catalog_url());
    let carts = shelf::list();
    println!("installed  : {} cart(s)", carts.len());
    for c in &carts {
        println!("  {:<14} {:<22} {:>6} bytes  best {}", c.id, c.title, c.bytes, shelf::best(&c.id));
    }
    if which("curl").is_none() {
        println!("⚠ curl is not installed — `sync` cannot fetch new carts");
    }
    0
}

fn which(bin: &str) -> Option<String> {
    std::env::var("PATH").ok().and_then(|p| {
        p.split(':')
            .map(|d| std::path::Path::new(d).join(bin))
            .find(|c| c.exists())
            .map(|c| c.to_string_lossy().to_string())
    })
}


/// The catalog `sync` reads. Generated from `carts/` rather than kept by hand,
/// because the hand-kept one went stale the moment a cart was added — it listed
/// four of seven, with byte counts for versions that no longer existed.
fn cmd_catalog(args: &[String]) -> i32 {
    let mut base = shelf::DEFAULT_CART_BASE.to_string();
    let mut out = "catalog.json".to_string();
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--base" => {
                i += 1;
                match args.get(i) {
                    Some(v) => base = v.trim_end_matches('/').to_string(),
                    None => {
                        eprintln!("✗ --base needs a url");
                        return 2;
                    }
                }
            }
            "-o" => {
                i += 1;
                match args.get(i) {
                    Some(v) => out = v.clone(),
                    None => {
                        eprintln!("✗ -o needs a path");
                        return 2;
                    }
                }
            }
            other => {
                eprintln!("✗ don't know the option {other}");
                return 2;
            }
        }
        i += 1;
    }

    let dir = std::path::Path::new("carts");
    let Ok(entries) = std::fs::read_dir(dir) else {
        eprintln!("✗ no carts/ directory here — run this from the repo");
        return 2;
    };
    let mut files: Vec<std::path::PathBuf> = entries
        .filter_map(|e| e.ok().map(|e| e.path()))
        .filter(|p| p.extension().and_then(|e| e.to_str()) == Some("lua"))
        .collect();
    files.sort();

    let mut carts = Vec::new();
    for path in &files {
        let Some(id) = path.file_stem().and_then(|s| s.to_str()) else { continue };
        let Ok(text) = std::fs::read_to_string(path) else {
            eprintln!("✗ could not read {}", path.display());
            return 1;
        };
        let cart = match Cart::parse(id, &text) {
            Ok(c) => c,
            Err(e) => {
                eprintln!("✗ {id}: {e}");
                return 1;
            }
        };
        carts.push(serde_json::json!({
            "id": cart.id,
            "title": cart.title,
            "author": cart.author,
            "about": cart.about,
            "bytes": cart.bytes,
            "sha256": sha256::hex(text.as_bytes()),
            "url": format!("{base}/{id}.lua"),
        }));
    }

    let doc = serde_json::json!({ "micromachee": 1, "carts": carts });
    let body = serde_json::to_string_pretty(&doc).unwrap_or_default() + "\n";
    if let Err(e) = std::fs::write(&out, &body) {
        eprintln!("✗ could not write {out}: {e}");
        return 1;
    }
    println!("wrote {out} — {} cart(s), urls under {base}", files.len());
    println!("upload the carts and this file, then `micromachee sync` finds them.");
    0
}


/// Frames of real play to use when a cart draws no cover of its own. Enough for
/// a title screen to settle or a game to have something on it.
const COVER_FALLBACK_FRAMES: u32 = 45;

/// The picture the shelf shows for a cart.
///
/// Drawn by the cart, through `_cover()`, on the same 128x128 screen with the
/// same eight colours — so a cover is one more thing a Lua file does, not an
/// asset beside it, and it follows the colour mode like everything else does.
/// A cart with no `_cover()` gets a frame of itself being played, which is at
/// least honest about what it looks like.
fn render_cover(cart: &Cart, palette: &theme::Palette) -> Result<Vec<u8>, String> {
    let machine = Machine::load(cart)?;
    machine.init()?;
    if machine.has_cover() {
        machine.cover()?;
    } else {
        for _ in 0..COVER_FALLBACK_FRAMES {
            machine.update()?;
            machine.draw()?;
        }
    }
    let png = machine.screen.borrow().to_png(palette);
    Ok(png)
}

/// Every cover at once, as one line of JSON. Deliberately NOT part of `status`:
/// the bar polls that on a timer and this is ~10K a cart, so it is asked for
/// once when the shelf is opened instead.
fn cmd_covers() -> i32 {
    let palette = theme::active(shelf::saved_theme().as_deref()).palette;
    let mut out = serde_json::Map::new();
    for entry in shelf::list() {
        let Some(path) = shelf::find(&entry.id) else { continue };
        let Ok(cart) = Cart::load(&path) else { continue };
        // One broken cart must not cost the shelf every other cover.
        if let Ok(png) = render_cover(&cart, &palette) {
            out.insert(entry.id.clone(), serde_json::Value::String(base64(&png)));
        }
    }
    println!("{}", serde_json::Value::Object(out));
    0
}

/// One cover, as a PNG, so you can look at it.
fn cmd_cover(args: &[String]) -> i32 {
    let mut id = None;
    let mut out = None;
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "-o" => {
                i += 1;
                out = args.get(i).cloned();
            }
            other => id = Some(other.to_string()),
        }
        i += 1;
    }
    let Some(id) = id else {
        eprintln!("✗ cover of what? try: micromachee cover snake -o cover.png");
        return 2;
    };
    // A path works as well as a shelf id, so you can look at a cart you are
    // still writing.
    let path = shelf::find(&id).unwrap_or_else(|| std::path::PathBuf::from(&id));
    let cart = match Cart::load(&path) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("✗ {e}");
            return 1;
        }
    };
    let palette = theme::active(shelf::saved_theme().as_deref()).palette;
    let png = match render_cover(&cart, &palette) {
        Ok(p) => p,
        Err(e) => {
            eprintln!("✗ {e}");
            return 1;
        }
    };
    let out = out.unwrap_or_else(|| format!("{}-cover.png", cart.id));
    if let Err(e) = std::fs::write(&out, &png) {
        eprintln!("✗ could not write {out}: {e}");
        return 1;
    }
    println!(
        "wrote {out} — {} ({})",
        cart.title,
        if Machine::load(&cart).map(|m| m.has_cover()).unwrap_or(false) {
            "its own cover"
        } else {
            "a frame of play, no _cover()"
        }
    );
    0
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let cmd = args.first().map(String::as_str).unwrap_or("status");
    let rest: Vec<String> = args.iter().skip(1).cloned().collect();

    let code = match cmd {
        "status" => {
            cmd_status();
            0
        }
        "list" => {
            println!("{}", serde_json::to_string(&shelf::list_json()).unwrap_or_else(|_| "[]".into()));
            0
        }
        "play" => match rest.first() {
            Some(id) => cmd_play(id),
            None => {
                eprintln!("✗ play what? try: micromachee list");
                2
            }
        },
        "check" => match rest.first() {
            Some(f) => cmd_check(f),
            None => {
                eprintln!("✗ check what? try: micromachee check mygame.lua");
                2
            }
        },
        "tty" => match rest.first() {
            Some(id) => tty::play(id),
            None => {
                eprintln!("✗ play what? try: micromachee list");
                2
            }
        },
        "shot" => cmd_shot(&rest),
        "new" => cmd_new(&rest),
        "theme" => match rest.first() {
            Some(id) if theme::get(id).is_some() => {
                shelf::set_theme(id);
                println!("theme is now {id}");
                0
            }
            Some(id) => {
                eprintln!("✗ there is no theme called {id} — try: {}", theme::ids().join(", "));
                2
            }
            None => {
                let now = theme::active(shelf::saved_theme().as_deref()).id;
                for id in theme::ids() {
                    println!("{} {id}", if id == now { "*" } else { " " });
                }
                // The one thing somebody writing a new palette has to know.
                println!(
                    "\nslots dark to light: {} — every theme keeps that order",
                    theme::rank().iter().map(|n| n.to_string()).collect::<Vec<_>>().join(" ")
                );
                0
            }
        },
        "covers" => cmd_covers(),
        "cover" => cmd_cover(&rest),
        "catalog" => cmd_catalog(&rest),
        "sync" => shelf::sync(),
        "doctor" => cmd_doctor(),
        "-h" | "--help" | "help" => {
            print!("{}", include_str!("usage.txt"));
            0
        }
        other => {
            eprintln!("✗ don't know how to {other}");
            2
        }
    };
    std::process::exit(code);
}

#[cfg(test)]
mod tests {
    /// manifest.json is what Omarchy reads; Cargo.toml is what the binary
    /// reports. They are copies of a version that lives in the Changelog API,
    /// and copies drift — this one sat at 0.1.0 through six releases. Kept
    /// honest by `scripts/version.sh`, and by this failing when it is not run.
    #[test]
    fn the_manifest_version_matches_the_binary() {
        const MANIFEST: &str = include_str!("../../manifest.json");
        let want = env!("CARGO_PKG_VERSION");
        let line = MANIFEST
            .lines()
            .find(|l| l.trim_start().starts_with("\"version\""))
            .expect("manifest.json has no version field");
        let got = line.split('"').nth(3).unwrap_or("");
        assert_eq!(
            got, want,
            "manifest.json says {got} and the crate says {want} — run scripts/version.sh"
        );
    }

    use super::*;

    #[test]
    fn base64_matches_the_standard() {
        assert_eq!(base64(b""), "");
        assert_eq!(base64(b"f"), "Zg==");
        assert_eq!(base64(b"fo"), "Zm8=");
        assert_eq!(base64(b"foo"), "Zm9v");
        assert_eq!(base64(b"foobar"), "Zm9vYmFy");
        // A frame is binary, so the high bytes matter more than the ASCII ones.
        assert_eq!(base64(&[0xff, 0xfe, 0xfd]), "//79");
    }

    #[test]
    fn a_whole_frame_encodes_to_one_line() {
        let png = crate::png::encode(128, 128, &crate::console::DEFAULT_PALETTE, &[0u8; 128 * 128]);
        let line = base64(&png);
        assert!(!line.contains('\n'), "the protocol is one frame per line");
        assert!(line.len() < 16_000, "line was {} chars", line.len());
    }
}
