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

mod browse;
mod cart;
mod console;
mod make;
mod mega;
mod palettes;
mod png;
mod safeio;
mod sha256;
mod shelf;
mod theme;
mod tty;
mod vm;
mod wav;
mod ydrast;

use std::io::{BufRead, IsTerminal, Write};
use std::sync::atomic::{AtomicBool, AtomicU8, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use cart::{Cart, MAX_CART_BYTES, MAX_LOCAL_CART_BYTES};
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
    if id == mega::MEGA_ID {
        return cmd_play_mega();
    }
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
    let machine = match Machine::load_with(&cart, shelf::load_save(&cart.id)) {
        Ok(m) => { m.set_tongue(shelf::saved_tongue()); m }
        Err(e) => {
            eprintln!("✗ {e}");
            return 1;
        }
    };

    // stdin blocks, so it gets its own thread and hands the loop a byte.
    //
    //   B <mask>   buttons held
    //   P / R      pause and resume — closing the panel should not lose a game
    //   T <id>     change the colour mode WITHOUT restarting: restarting meant
    //              tearing down this process and standing another one up, and
    //              the dying one's exit took the new one's state with it
    //   Q          quit, and write the high score out properly
    let held = Arc::new(AtomicU8::new(0));
    let quit = Arc::new(AtomicBool::new(false));
    let paused = Arc::new(AtomicBool::new(false));
    let want_theme: Arc<Mutex<Option<String>>> = Arc::new(Mutex::new(None));
    {
        let (held, quit, paused, want_theme) =
            (held.clone(), quit.clone(), paused.clone(), want_theme.clone());
        std::thread::spawn(move || {
            let stdin = std::io::stdin();
            for line in stdin.lock().lines() {
                let Ok(line) = line else { break };
                let line = line.trim();
                if let Some(bits) = line.strip_prefix("B ") {
                    if let Ok(v) = bits.trim().parse::<u8>() {
                        held.store(v, Ordering::Relaxed);
                    }
                } else if let Some(id) = line.strip_prefix("T ") {
                    *want_theme.lock().unwrap() = Some(id.trim().to_string());
                } else if line == "P" {
                    paused.store(true, Ordering::Relaxed);
                    held.store(0, Ordering::Relaxed); // no key is held while away
                } else if line == "R" {
                    paused.store(false, Ordering::Relaxed);
                } else if line == "Q" {
                    break;
                }
            }
            quit.store(true, Ordering::Relaxed);
        });
    }

    let mut palette = theme::active(shelf::saved_theme().as_deref()).palette;
    let muted = shelf::saved_muted();
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
    let mut last_flush = Instant::now();
    while !quit.load(Ordering::Relaxed) {
        // A new colour mode is eight different bytes in the next PLTE chunk.
        // Nothing else has to happen — the cart never learns about it.
        if let Some(id) = want_theme.lock().unwrap().take() {
            if let Some(t) = theme::get(&id) {
                palette = t.palette;
                shelf::set_theme(&id);
            }
        }

        // Paused: the game stops advancing and stops costing anything, and the
        // last frame stays on screen. Closing the panel is a pause, not a loss.
        if paused.load(Ordering::Relaxed) {
            flush_save(&cart.id, &machine);
            next = Instant::now();
            std::thread::sleep(Duration::from_millis(120));
            continue;
        }

        machine.set_held(held.load(Ordering::Relaxed));
        if let Err(e) = machine.update() {
            fail(&mut out, e);
            return 1;
        }
        if let Err(e) = machine.draw() {
            fail(&mut out, e);
            return 1;
        }
        // Sounds before the picture: they were asked for during the update that
        // produced this frame, and a sound that arrives a frame late is a sound
        // that does not belong to what you just saw.
        if !muted {
            for n in machine.take_sfx() {
                let _ = writeln!(out, "A {n}");
            }
        } else {
            machine.take_sfx();
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

        // Written at most once a second: a widget can be killed at any moment,
        // so waiting for a clean exit would lose the farm.
        if machine.dirty.get() && last_flush.elapsed() >= Duration::from_secs(1) {
            flush_save(&cart.id, &machine);
            last_flush = Instant::now();
        }

        next += step;
        let now = Instant::now();
        if next > now {
            std::thread::sleep(next - now);
        } else {
            next = now; // fell behind; do not try to catch up
        }
    }
    flush_save(&cart.id, &machine);
    0
}

/// The same protocol as `play`, driving the meta-game instead of one cart.
fn cmd_play_mega() -> i32 {
    let mut mega = match mega::Mega::new() {
        Ok(m) => m,
        Err(e) => {
            eprintln!("✗ {e}");
            return 1;
        }
    };

    let held = Arc::new(AtomicU8::new(0));
    let quit = Arc::new(AtomicBool::new(false));
    let paused = Arc::new(AtomicBool::new(false));
    let want_theme: Arc<Mutex<Option<String>>> = Arc::new(Mutex::new(None));
    {
        let (held, quit, paused, want_theme) =
            (held.clone(), quit.clone(), paused.clone(), want_theme.clone());
        std::thread::spawn(move || {
            let stdin = std::io::stdin();
            for line in stdin.lock().lines() {
                let Ok(line) = line else { break };
                let line = line.trim();
                if let Some(bits) = line.strip_prefix("B ") {
                    if let Ok(v) = bits.trim().parse::<u8>() {
                        held.store(v, Ordering::Relaxed);
                    }
                } else if let Some(id) = line.strip_prefix("T ") {
                    *want_theme.lock().unwrap() = Some(id.trim().to_string());
                } else if line == "P" {
                    paused.store(true, Ordering::Relaxed);
                    held.store(0, Ordering::Relaxed);
                } else if line == "R" {
                    paused.store(false, Ordering::Relaxed);
                } else if line == "Q" {
                    break;
                }
            }
            quit.store(true, Ordering::Relaxed);
        });
    }

    let mut palette = theme::active(shelf::saved_theme().as_deref()).palette;
    let muted_mega = shelf::saved_muted();
    let out = std::io::stdout();
    let mut out = out.lock();

    let step = Duration::from_micros(1_000_000 / FPS as u64);
    let mut next = Instant::now();
    let mut last_score = i64::MIN;
    while !quit.load(Ordering::Relaxed) {
        if let Some(id) = want_theme.lock().unwrap().take() {
            if let Some(t) = theme::get(&id) {
                palette = t.palette;
                shelf::set_theme(&id);
            }
        }
        if paused.load(Ordering::Relaxed) {
            next = Instant::now();
            std::thread::sleep(Duration::from_millis(120));
            continue;
        }

        if let Err(e) = mega.step(held.load(Ordering::Relaxed)) {
            let _ = writeln!(out, "E {e}");
            let _ = out.flush();
            return 1;
        }

        if !muted_mega {
            for n in mega.take_sfx() {
                let _ = writeln!(out, "A {n}");
            }
        } else {
            mega.take_sfx();
        }
        let frame = mega.out.to_png(&palette);
        if writeln!(out, "F {}", base64(&frame)).is_err() || out.flush().is_err() {
            break;
        }
        let score = mega.score();
        if score != last_score {
            last_score = score;
            let _ = writeln!(out, "S {score}");
            let _ = out.flush();
            shelf::record_score(mega::MEGA_ID, score);
        }

        next += step;
        let now = Instant::now();
        if next > now {
            std::thread::sleep(next - now);
        } else {
            next = now;
        }
    }
    0
}

/// The shelf, as a program the console runs.
///
/// Same protocol as `play`, with two lines added: `G <id>` when the player picks
/// a cart, and `M` when they pick the make-a-game tile. Either way this exits
/// and the panel takes over — picking is a handover rather than a mode inside
/// one process, so a game that falls over cannot take the shelf down with it.
///
/// `--intro` plays the opening titles. The panel passes it when it opens and
/// not when the shelf merely restarts, so leaving a game does not replay them.
fn cmd_browse(args: &[String]) -> i32 {
    if std::io::stdout().is_terminal() {
        eprintln!("note: `browse` prints a frame protocol for the bar, not a menu for a terminal.");
    }
    let mut shelf_screen = browse::Browse::new(args.iter().any(|a| a == "--intro"));

    let held = Arc::new(AtomicU8::new(0));
    let quit = Arc::new(AtomicBool::new(false));
    let paused = Arc::new(AtomicBool::new(false));
    let want_theme: Arc<Mutex<Option<String>>> = Arc::new(Mutex::new(None));
    {
        let (held, quit, paused, want_theme) =
            (held.clone(), quit.clone(), paused.clone(), want_theme.clone());
        std::thread::spawn(move || {
            let stdin = std::io::stdin();
            for line in stdin.lock().lines() {
                let Ok(line) = line else { break };
                let line = line.trim();
                if let Some(bits) = line.strip_prefix("B ") {
                    if let Ok(v) = bits.trim().parse::<u8>() {
                        held.store(v, Ordering::Relaxed);
                    }
                } else if let Some(id) = line.strip_prefix("T ") {
                    *want_theme.lock().unwrap() = Some(id.trim().to_string());
                } else if line == "P" {
                    paused.store(true, Ordering::Relaxed);
                    held.store(0, Ordering::Relaxed);
                } else if line == "R" {
                    paused.store(false, Ordering::Relaxed);
                } else if line == "Q" {
                    break;
                }
            }
            quit.store(true, Ordering::Relaxed);
        });
    }

    let mut palette = theme::active(shelf::saved_theme().as_deref()).palette;
    let muted_browse = shelf::saved_muted();
    let out = std::io::stdout();
    let mut out = out.lock();

    let step = Duration::from_micros(1_000_000 / FPS as u64);
    let mut next = Instant::now();
    while !quit.load(Ordering::Relaxed) {
        if let Some(id) = want_theme.lock().unwrap().take() {
            if let Some(t) = theme::get(&id) {
                palette = t.palette;
                shelf::set_theme(&id);
            }
        }
        // A shelf nobody is looking at costs nothing to stop drawing.
        if paused.load(Ordering::Relaxed) {
            next = Instant::now();
            std::thread::sleep(Duration::from_millis(120));
            continue;
        }

        let sounds = {
            let s = shelf_screen.frame(held.load(Ordering::Relaxed));
            let png = s.to_png(&palette);
            (shelf_screen.take_sfx(), png)
        };
        if !muted_browse {
            for n in sounds.0 {
                let _ = writeln!(out, "A {n}");
            }
        }
        if writeln!(out, "F {}", base64(&sounds.1)).is_err() || out.flush().is_err() {
            break;
        }
        if let Some(id) = shelf_screen.picked() {
            let _ = writeln!(out, "G {id}");
            let _ = out.flush();
            return 0;
        }
        if shelf_screen.wants_make() {
            let _ = writeln!(out, "M");
            let _ = out.flush();
            return 0;
        }

        next += step;
        let now = Instant::now();
        if next > now {
            std::thread::sleep(next - now);
        } else {
            next = now;
        }
    }
    0
}

fn flush_save(id: &str, machine: &Machine) {
    if !machine.dirty.get() {
        return;
    }
    shelf::store_save(id, &machine.saved.borrow());
    machine.dirty.set(false);
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
    // A cart within the shelf cap is measured against it; a bundled campaign
    // over it is measured against the local ceiling and told it is bundle-only,
    // because it can no longer travel over sync.
    if cart.bytes <= MAX_CART_BYTES {
        println!(
            "  {} by {} — {} bytes of {} ({}% of a cart)",
            cart.title, cart.author, cart.bytes, MAX_CART_BYTES,
            cart.bytes * 100 / MAX_CART_BYTES
        );
    } else {
        println!(
            "  {} by {} — {} bytes ({}% of the {} campaign ceiling) — over 24K, so bundle-only, not for sync",
            cart.title, cart.author, cart.bytes,
            cart.bytes * 100 / MAX_LOCAL_CART_BYTES, MAX_LOCAL_CART_BYTES
        );
    }

    for w in cart.warnings() {
        println!("  ⚠ {w}");
    }

    let machine = match Machine::load(&cart) {
        Ok(m) => { m.set_tongue(shelf::saved_tongue()); m }
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

/// `"5:2,6:0"` → the button mask in force from each frame until the next.
///
/// Sorted, so the track may be written in any order, and masked to six buttons
/// so a typo cannot set a bit no cart can read.
fn parse_key_track(spec: &str) -> Result<Vec<(u32, u8)>, String> {
    let mut out = Vec::new();
    for part in spec.split(',') {
        let part = part.trim();
        if part.is_empty() {
            continue;
        }
        let (f, m) = part
            .split_once(':')
            .ok_or_else(|| format!("--keys wants frame:mask pairs, e.g. 0:2,15:16,30:0 — got {part:?}"))?;
        let frame: u32 = f
            .trim()
            .parse()
            .map_err(|_| format!("--keys: {:?} is not a frame number", f.trim()))?;
        let mask: u8 = m
            .trim()
            .parse()
            .map_err(|_| format!("--keys: {:?} is not a button mask (0-63)", m.trim()))?;
        out.push((frame, mask & 0b0011_1111));
    }
    out.sort_by_key(|(f, _)| *f);
    Ok(out)
}

fn cmd_shot(args: &[String]) -> i32 {
    let mut file = None;
    let mut out = "shot.png".to_string();
    let mut frames = 1u32;
    let mut hold = 0u8;
    // (frame, button mask) — the mask in force from that frame until the next.
    let mut keys: Vec<(u32, u8)> = Vec::new();
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
            // `--hold` can only ever show you frame 1 of a btnp game: a held
            // button fires btnp once, so a menu never moves and a turn-based
            // game never takes a second turn. That is exactly the class where
            // the bugs are layout and state rather than motion, and exactly
            // the class an author most needs to look at. A track of
            // `frame:mask` changes lets a tap be expressed.
            "--keys" => {
                i += 1;
                match parse_key_track(args.get(i).map(String::as_str).unwrap_or("")) {
                    Ok(track) => keys = track,
                    Err(e) => {
                        eprintln!("✗ {e}");
                        return 2;
                    }
                }
            }
            other => file = Some(other.to_string()),
        }
        i += 1;
    }
    let Some(file) = file else {
        eprintln!("✗ shot what? try: micromachee shot mygame.lua --frames 60 --hold 2 -o look.png");
        eprintln!("  for a btnp game, tap instead:  --keys \"10:2,11:0,20:16,21:0\"");
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
        Ok(m) => { m.set_tongue(shelf::saved_tongue()); m }
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
    let mut next_key = 0usize;
    for f in 0..frames.max(1) {
        // Apply every change scheduled at or before this frame. Holding the
        // mask until the next entry is what makes a tap expressible: set it on
        // one frame, clear it on the next.
        while next_key < keys.len() && keys[next_key].0 <= f {
            machine.set_held(keys[next_key].1);
            next_key += 1;
        }
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
            // The console's own size control, so the buttons on it can change
            // it without anybody opening a settings page.
            "scale": shelf::saved_scale(),
            "sounds": shelf::sounds_dir().to_string_lossy(),
        "muted": shelf::saved_muted(),
        "tongue": if shelf::saved_tongue() { "ydrast" } else { "plain" },
            "shell": {
                "body": th.shell.body, "bezel": th.shell.bezel,
                "text": th.shell.text, "dim": th.shell.dim, "accent": th.shell.accent,
            },
            // One shelf for everybody. Building it here by hand is how the
            // panel ended up without the `draft` flag it reads.
            "carts": shelf::shelf_json(),
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
    // Campaign carts over the 24K shelf cap cannot be synced — `sync` refuses
    // anything past it by design, and that cap is the shareable-cart identity.
    // On the plugin they ship bundled beside it; the web has no plugin to bundle
    // into, so they travel in a SEPARATE `bundle` array here. `sync` only ever
    // reads `carts`, so it never sees these and never rejects them; the web
    // reads both, so the shelf is the same one the plugin shows.
    let mut bundle = Vec::new();
    for path in &files {
        let Some(id) = path.file_stem().and_then(|s| s.to_str()) else { continue };
        // Never publish a name a correct client would refuse to install. The
        // check that stops a hostile catalog also has to stop us shipping one
        // by accident.
        if !shelf::valid_id(id) {
            eprintln!("✗ {id} is not a usable cart name — rename the file");
            return 1;
        }
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
        let mut entry = serde_json::json!({
            "id": cart.id,
            "title": cart.title,
            "author": cart.author,
            "about": cart.about,
            "bytes": cart.bytes,
            // Whether a few seconds of it is a game, which Mega needs to know
            // before it deals the cart out.
            "mega": cart.in_mega,
            "price": cart.price,
            "sha256": sha256::hex(text.as_bytes()),
            // The source travels inside the catalog as well as beside it. The
            // CDN only sends CORS headers for .json, so a browser can read this
            // file and nothing else — and one request for the whole shelf beats
            // one per cart anyway.
            "code": text.clone(),
        });
        if cart.bytes > MAX_CART_BYTES {
            // Bundle-only: no `url`, because sync never fetches it and CORS
            // would not let a browser read a .lua anyway — the web plays it
            // from the inline `code`.
            println!("  · bundling {id} ({} bytes) — over the 24K sync cap, web-only", cart.bytes);
            bundle.push(entry);
        } else {
            entry["url"] = serde_json::json!(format!("{base}/{id}.lua"));
            carts.push(entry);
        }
    }

    let doc = serde_json::json!({ "micromachee": 1, "carts": carts, "bundle": bundle });
    let body = serde_json::to_string_pretty(&doc).unwrap_or_default() + "\n";
    if let Err(e) = std::fs::write(&out, &body) {
        eprintln!("✗ could not write {out}: {e}");
        return 1;
    }
    println!("wrote {out} — {} cart(s) + {} bundled, urls under {base}", carts.len(), bundle.len());
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
    machine.set_tongue(shelf::saved_tongue());
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
    out.insert(
        mega::MEGA_ID.to_string(),
        serde_json::Value::String(base64(&mega::Mega::cover().to_png(&palette))),
    );
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
    if id == mega::MEGA_ID {
        let palette = theme::active(shelf::saved_theme().as_deref()).palette;
        let out = out.unwrap_or_else(|| format!("{}-cover.png", mega::MEGA_ID));
        return match std::fs::write(&out, mega::Mega::cover().to_png(&palette)) {
            Ok(()) => {
                println!("wrote {out} — {}", mega::MEGA_TITLE);
                0
            }
            Err(e) => {
                eprintln!("✗ could not write {out}: {e}");
                1
            }
        };
    }
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
            println!("{}", serde_json::to_string(&shelf::shelf_json()).unwrap_or_else(|_| "[]".into()));
            0
        }
        "sounds" => {
            let dir = rest
                .iter()
                .position(|a| a == "-o")
                .and_then(|i| rest.get(i + 1))
                .map(std::path::PathBuf::from)
                .unwrap_or_else(shelf::sounds_dir);
            match wav::write_bank(&dir) {
                Ok(n) => {
                    println!("wrote {n} sound(s) → {}", dir.display());
                    0
                }
                Err(e) => {
                    eprintln!("✗ {e}");
                    1
                }
            }
        }
        "mute" => match rest.first().map(String::as_str) {
            Some("on") => {
                shelf::set_muted(true);
                println!("sound is off");
                0
            }
            Some("off") => {
                shelf::set_muted(false);
                println!("sound is on");
                0
            }
            None => {
                println!("{}", if shelf::saved_muted() { "off" } else { "on" });
                0
            }
            Some(other) => {
                eprintln!("✗ mute takes on or off, not {other}");
                2
            }
        },
        "browse" => cmd_browse(&rest),
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
        "make" => match (rest.first(), rest.get(1)) {
            (Some(name), Some(prompt)) => make::make(name, prompt),
            _ => {
                eprintln!("✗ try: micromachee make \"Space Rocks\" \"dodge falling rocks\"");
                2
            }
        },
        "revise" => match (rest.first(), rest.get(1)) {
            (Some(id), Some(prompt)) => make::revise(id, prompt),
            _ => {
                eprintln!("✗ try: micromachee revise space-rocks \"make it faster\"");
                2
            }
        },
        "publish" => match rest.first() {
            Some(id) => make::publish(id),
            None => {
                eprintln!("✗ publish what? try: micromachee drafts");
                2
            }
        },
        "discard" => match rest.first() {
            Some(id) => make::discard(id),
            None => {
                eprintln!("✗ discard what? try: micromachee drafts");
                2
            }
        },
        "covers" => cmd_covers(),
        "cover" => cmd_cover(&rest),
        "catalog" => cmd_catalog(&rest),
        "tongue" => {
            // Not advertised in `--help`. Somebody has to find it.
            let on = match rest.first().map(String::as_str) {
                Some("ydrast") => { shelf::set_tongue(true); true }
                Some("plain") => { shelf::set_tongue(false); false }
                Some(other) => {
                    eprintln!("✗ don't know the tongue {other}");
                    std::process::exit(2);
                }
                None => shelf::saved_tongue(),
            };
            println!("{}", if on { "ydrast" } else { "plain" });
            0
        }
        "scale" => {
            // With no argument it reports; with one it sets and reports.
            let n = match rest.first() {
                Some(v) => match v.parse::<i64>() {
                    Ok(n) => shelf::set_scale(n),
                    Err(_) => {
                        eprintln!("✗ scale takes a number from 2 to 6");
                        std::process::exit(2)
                    }
                },
                None => shelf::saved_scale(),
            };
            println!("{n}");
            0
        }
        "sync" => shelf::sync(rest.iter().any(|a| a == "--update")),
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
    fn a_key_track_parses_into_frame_ordered_masks() {
        assert_eq!(parse_key_track("5:2,6:0").unwrap(), vec![(5, 2), (6, 0)]);
        // Any order in, frame order out.
        assert_eq!(parse_key_track("30:0, 5:2 ,6:0").unwrap(), vec![(5, 2), (6, 0), (30, 0)]);
        assert_eq!(parse_key_track("").unwrap(), vec![]);
        // Six buttons; a stray high bit is not a seventh.
        assert_eq!(parse_key_track("0:255").unwrap(), vec![(0, 63)]);
    }

    #[test]
    fn a_malformed_key_track_says_what_is_wrong() {
        // Silently ignoring a typo would render a frame that looks like the
        // game ignoring input, which is the bug the author is hunting.
        for bad in ["5", "5:x", "x:5", "5:2,junk"] {
            let e = parse_key_track(bad).expect_err(&format!("{bad:?} should not parse"));
            assert!(!e.is_empty());
        }
    }

    #[test]
    fn a_whole_frame_encodes_to_one_line() {
        let png = crate::png::encode(128, 128, &crate::console::DEFAULT_PALETTE, &[0u8; 128 * 128]);
        let line = base64(&png);
        assert!(!line.contains('\n'), "the protocol is one frame per line");
        assert!(line.len() < 16_000, "line was {} chars", line.len());
    }
}
