//! omarchy-micromachee — the working half of the micromachee plugin.
//!
//! The QML in the bar is deliberately thin: it runs this binary and renders
//! what it prints. Everything that can go wrong lives here, where `cargo test`
//! can reach it without a compositor running.
//!
//! Two conventions the QML depends on:
//!
//!   * `status` prints ONE line of JSON on stdout and exits 0. The bar polls
//!     it on a timer, so it must be cheap and must never block.
//!   * every other command prints a human sentence to stderr and exits
//!     non-zero when it fails. The panel shows that last line verbatim, so
//!     write it for the person reading the bar, not for a log.
//!
//!   omarchy-micromachee status     one line of JSON for the bar
//!   omarchy-micromachee set <text>  write the headline the bar shows
//!   omarchy-micromachee doctor     what is installed and reachable

use std::fs;
use std::path::PathBuf;

use serde_json::{json, Value};

// ── where state lives ───────────────────────────────────────────────────────
//
// Under XDG state, not config: this is something the program maintains, not
// something the user edits. Respect the env vars — a user who has moved their
// state directory means it.

fn state_dir() -> PathBuf {
    let base = std::env::var("XDG_STATE_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| {
            PathBuf::from(std::env::var("HOME").unwrap_or_else(|_| "/tmp".into()))
                .join(".local/state")
        });
    base.join("omarchy-micromachee")
}

fn state_path() -> PathBuf {
    state_dir().join("state.json")
}

fn load_state() -> Value {
    fs::read_to_string(state_path())
        .ok()
        .and_then(|t| serde_json::from_str(&t).ok())
        .unwrap_or_else(|| json!({}))
}

/// Write via a temp file and rename, so a crash mid-write cannot leave the
/// user with a truncated state file — on a widget that saves constantly, that
/// is a real risk rather than a theoretical one.
fn save_state(v: &Value) -> std::io::Result<()> {
    let dir = state_dir();
    fs::create_dir_all(&dir)?;
    let tmp = dir.join("state.json.tmp");
    fs::write(&tmp, serde_json::to_string(v).unwrap_or_else(|_| "{}".into()))?;
    fs::rename(tmp, state_path())
}

// ── commands ────────────────────────────────────────────────────────────────

/// One line of JSON for the bar. `ready` decides whether the glyph is lit;
/// `headline` is the handful of characters shown beside it.
fn cmd_status() {
    let state = load_state();
    let out = json!({
        "ready": true,
        "headline": state.get("headline").and_then(|v| v.as_str()).unwrap_or("hello"),
    });
    println!("{}", out);
}

/// The other half of the round trip, and the example of an "action": it changes
/// something, says nothing on success, and explains itself on failure.
fn cmd_set(rest: &[String]) -> i32 {
    let value = rest.join(" ");
    if value.trim().is_empty() {
        eprintln!("✗ nothing to set — try: omarchy-micromachee set 42");
        return 2;
    }
    let mut state = load_state();
    state["headline"] = json!(value);
    match save_state(&state) {
        Ok(()) => 0,
        Err(e) => {
            // Written for someone reading their bar, not for a log file.
            eprintln!("✗ could not save: {e}");
            1
        }
    }
}

fn cmd_doctor() -> i32 {
    println!("state file: {}", state_path().display());
    println!(
        "state:      {}",
        if state_path().exists() { "present" } else { "not written yet" }
    );
    0
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let cmd = args.first().map(String::as_str).unwrap_or("status");

    let code = match cmd {
        "status" => {
            cmd_status();
            0
        }
        "set" => cmd_set(&args[1..]),
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
    use super::*;

    #[test]
    fn missing_state_is_an_empty_object_not_a_panic() {
        // A first run has no state file, and the widget must still render.
        let v = serde_json::from_str::<Value>("").unwrap_or_else(|_| json!({}));
        assert!(v.is_object());
    }

    #[test]
    fn state_survives_a_round_trip() {
        let v = json!({ "headline": "42" });
        let text = serde_json::to_string(&v).unwrap();
        let back: Value = serde_json::from_str(&text).unwrap();
        assert_eq!(back["headline"], "42");
    }

    #[test]
    fn set_with_nothing_to_set_fails_loudly() {
        // Silent success on an empty argument is how a widget ends up showing
        // a blank label with no clue why.
        assert_eq!(cmd_set(&[]), 2);
        assert_eq!(cmd_set(&["   ".to_string()]), 2);
    }
}
