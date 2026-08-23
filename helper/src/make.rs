//! Making a cart from a sentence.
//!
//! The console's rules are strict, and that is exactly what makes this work: a
//! generated cart is not trusted, it is *checked* — it has to parse, load, and
//! survive a run before it is written anywhere. When it fails, the error goes
//! back to the model and it tries again. So the rules are not a constraint on
//! generation, they are the thing that makes generation reliable.
//!
//! Drafts live beside the shelf but in their own directory, and the shelf looks
//! there too — so a draft is playable the moment it exists, with no publishing
//! step and nothing special in the player. Publishing is a file move.

use std::io::Write;
use std::path::PathBuf;
use std::process::{Command, Stdio};

use serde_json::{json, Value};

use crate::cart::{Cart, MAX_CART_BYTES};
use crate::shelf;
use crate::vm::Machine;

/// The console's rules, as the model sees them. A separate file from CLAUDE.md
/// because it has a different reader and a much tighter budget.
const RULES: &str = include_str!("cart-rules.md");

const MODEL: &str = "claude-opus-5";
const MAX_TOKENS: u32 = 16000;

/// How many times to hand an error back and ask again. Two repairs is plenty —
/// past that it is usually the request that is wrong, not the code.
const ATTEMPTS: usize = 3;

/// Frames to run before believing a generated cart works.
const PROVE_FRAMES: u32 = 600;

pub fn drafts_dir() -> PathBuf {
    if let Ok(dir) = std::env::var("MICROMACHEE_DRAFTS") {
        return PathBuf::from(dir);
    }
    shelf::carts_dir()
        .parent()
        .map(|p| p.join("drafts"))
        .unwrap_or_else(|| PathBuf::from("drafts"))
}

// ── talking to the model ────────────────────────────────────────────────────

/// How to authenticate, without ever putting the secret in a log line.
enum Auth {
    Key(String),
    /// A short-lived OAuth token from `ant auth login`.
    Bearer(String),
}

fn auth() -> Result<Auth, String> {
    if let Ok(k) = std::env::var("ANTHROPIC_API_KEY") {
        if !k.trim().is_empty() {
            return Ok(Auth::Key(k));
        }
    }
    // An unset key does not mean there are no credentials: `ant auth login`
    // leaves a profile the CLI can mint a token from.
    if let Ok(out) = Command::new("ant")
        .args(["auth", "print-credentials", "--access-token"])
        .output()
    {
        if out.status.success() {
            let tok = String::from_utf8_lossy(&out.stdout).trim().to_string();
            if !tok.is_empty() {
                return Ok(Auth::Bearer(tok));
            }
        }
    }
    Err("no Anthropic credentials — set ANTHROPIC_API_KEY, or run `ant auth login`".into())
}

/// One turn. Non-streaming: a cart is a few thousand tokens, well inside what a
/// single response returns comfortably.
/// The request, as a value, so its shape can be asserted without a network.
fn request_body(messages: &[Value]) -> Value {
    json!({
        "model": MODEL,
        "max_tokens": MAX_TOKENS,
        "system": [{
            "type": "text",
            "text": RULES,
            // The rules are the same every call and dwarf the request, so they
            // are worth caching across a conversation of revisions.
            "cache_control": {"type": "ephemeral"}
        }],
        "thinking": {"type": "adaptive"},
        "output_config": {"effort": "high"},
        // If a safety classifier declines, let the server retry the same request
        // on another model rather than handing the user a dead end.
        "fallbacks": "default",
        "messages": messages,
    })
}

/// Escape a value for a curl config file.
///
/// Config values are quoted and understand backslash escapes, so the two
/// characters that can end or extend a value have to be neutralised. Nothing
/// here is expected to contain either — an API key does not — but a request
/// body is JSON full of quotes, and "it will not contain that" is how escaping
/// bugs are written.
fn config_value(raw: &str) -> String {
    let mut out = String::with_capacity(raw.len() + 8);
    for c in raw.chars() {
        match c {
            '\\' => out.push_str("\\\\"),
            '"' => out.push_str("\\\""),
            // A literal newline would end the config line and turn the rest of
            // the value into commands. serde_json does not emit one, and this
            // is here so that staying true is not load-bearing.
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            c => out.push(c),
        }
    }
    out
}

/// The most an API response may be. A response carries one cart — at most 24K
/// of Lua — inside a JSON envelope, plus whatever the model said around it.
/// Two orders of magnitude of headroom over that is still nothing against a
/// compromised or misbehaving endpoint streaming without end.
const MAX_RESPONSE_BYTES: usize = 4 * 1024 * 1024;

fn ask(messages: &[Value]) -> Result<String, String> {
    let auth = auth()?;
    let body = request_body(messages);

    // Everything sensitive goes to curl on STDIN, as a config file, and none of
    // it appears in the command line.
    //
    // The key used to be passed as `-H "x-api-key: ..."`. On Linux
    // /proc/<pid>/cmdline is mode 444, so for as long as that request was in
    // flight the credential was readable by every process on the machine,
    // whoever it belonged to. The request body went the same way, which is a
    // smaller thing but the same mistake.
    //
    // stdin rather than a file with tight permissions: a 0600 temp file would
    // also keep it out of the command line, but it puts a credential on disk,
    // and something has to remember to delete it even if this process is killed
    // in between. A pipe has neither problem.
    let mut config = String::new();
    config.push_str("header = \"content-type: application/json\"\n");
    config.push_str("header = \"anthropic-version: 2023-06-01\"\n");
    match &auth {
        Auth::Key(k) => {
            config.push_str(&format!("header = \"x-api-key: {}\"\n", config_value(k)));
            config.push_str(
                "header = \"anthropic-beta: server-side-fallback-2026-07-01\"\n",
            );
        }
        Auth::Bearer(t) => {
            config.push_str(&format!("header = \"authorization: Bearer {}\"\n", config_value(t)));
            config.push_str(
                "header = \"anthropic-beta: server-side-fallback-2026-07-01,oauth-2025-04-20\"\n",
            );
        }
    }
    config.push_str(&format!("data-binary = \"{}\"\n", config_value(&body.to_string())));

    let mut child = Command::new("curl")
        .args([
            "-sS",
            "--max-time",
            "300",
            "--proto",
            "=https",
            "--proto-redir",
            "=https",
            "--max-redirs",
            "0",
            "-K",
            "-",
            "https://api.anthropic.com/v1/messages",
        ])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| format!("could not run curl: {e}"))?;
    if let Some(mut sink) = child.stdin.take() {
        use std::io::Write;
        sink.write_all(config.as_bytes())
            .map_err(|e| format!("could not send the request: {e}"))?;
    }

    // Bounded at the pipe, the same primitive shelf.rs uses for the catalog: a
    // compromised or runaway endpoint does not get to decide how much memory
    // this process allocates before anything is parsed.
    let (body, err_note, status) = crate::safeio::read_child_bounded(child, MAX_RESPONSE_BYTES)
        .map_err(|_| {
            format!("the response never ended (over {MAX_RESPONSE_BYTES} bytes) — refused")
        })?;
    if !status.success() {
        return Err(format!(
            "the request failed: {}",
            String::from_utf8_lossy(&err_note).trim()
        ));
    }
    let v: Value = serde_json::from_slice(&body)
        .map_err(|_| "the API sent something that is not JSON".to_string())?;

    if let Some(err) = v.get("error") {
        let msg = err.get("message").and_then(|m| m.as_str()).unwrap_or("unknown");
        return Err(format!("the API said: {msg}"));
    }
    // A decline arrives as a 200 with a stop reason, not as an error.
    if v.get("stop_reason").and_then(|s| s.as_str()) == Some("refusal") {
        return Err("the model declined to write that one — try describing it differently".into());
    }

    // Adaptive thinking means the content array holds thinking blocks as well;
    // only the text blocks are the answer.
    let text: String = v
        .get("content")
        .and_then(|c| c.as_array())
        .map(|blocks| {
            blocks
                .iter()
                .filter(|b| b.get("type").and_then(|t| t.as_str()) == Some("text"))
                .filter_map(|b| b.get("text").and_then(|t| t.as_str()))
                .collect::<Vec<_>>()
                .join("")
        })
        .unwrap_or_default();

    if text.trim().is_empty() {
        return Err("the model sent nothing back".into());
    }
    Ok(text)
}

/// The rules say "no markdown fences". Models mostly obey; strip them anyway,
/// because a fence is a one-character-deep failure that would otherwise cost a
/// whole repair round.
pub fn strip_fences(text: &str) -> String {
    let t = text.trim();
    if !t.starts_with("```") {
        return t.to_string();
    }
    let mut lines: Vec<&str> = t.lines().collect();
    lines.remove(0); // ```lua
    while let Some(last) = lines.last() {
        if last.trim().is_empty() {
            lines.pop();
        } else {
            break;
        }
    }
    if lines.last().map(|l| l.trim_start().starts_with("```")).unwrap_or(false) {
        lines.pop();
    }
    lines.join("\n")
}

// ── proving it works ────────────────────────────────────────────────────────

/// Everything `check` does, as a function: parses, loads, and survives play.
/// Whatever this returns is handed straight back to the model, so it has to
/// read as an instruction rather than a status code.
pub fn prove(id: &str, code: &str) -> Result<Cart, String> {
    if code.len() > MAX_CART_BYTES {
        return Err(format!(
            "the file is {} bytes and the limit is {MAX_CART_BYTES}. Make it shorter.",
            code.len()
        ));
    }
    let cart = Cart::parse(id, code)?;
    let machine = Machine::load(&cart).map_err(|e| format!("it does not load: {e}"))?;
    machine.init().map_err(|e| format!("_init failed: {e}"))?;

    let mut seed = 0x2545_f491u32;
    for frame in 0..PROVE_FRAMES {
        seed = seed.wrapping_mul(1_664_525).wrapping_add(1_013_904_223);
        machine.set_held((seed >> 24) as u8 & 0b11_1111);
        machine
            .update()
            .map_err(|e| format!("_update failed on frame {frame}: {e}"))?;
        machine
            .draw()
            .map_err(|e| format!("_draw failed on frame {frame}: {e}"))?;
    }
    if machine.has_cover() {
        machine.cover().map_err(|e| format!("_cover failed: {e}"))?;
    }
    Ok(cart)
}

// ── drafts on disk ──────────────────────────────────────────────────────────

fn slug(name: &str) -> String {
    let mut s = String::new();
    for ch in name.chars() {
        if ch.is_ascii_alphanumeric() {
            s.push(ch.to_ascii_lowercase());
        } else if !s.ends_with('-') && !s.is_empty() {
            s.push('-');
        }
    }
    let s = s.trim_matches('-').to_string();
    let s: String = s.chars().take(28).collect();
    let s = s.trim_matches('-').to_string();
    if s.is_empty() { "game".into() } else { s }
}

/// A free id, so making two games called the same thing does not overwrite one.
fn free_id(base: &str) -> String {
    let dir = drafts_dir();
    if !dir.join(format!("{base}.lua")).exists() && shelf::find(base).is_none() {
        return base.to_string();
    }
    for n in 2..999 {
        let candidate = format!("{base}-{n}");
        if !dir.join(format!("{candidate}.lua")).exists() && shelf::find(&candidate).is_none() {
            return candidate;
        }
    }
    format!("{base}-new")
}

fn history_path(id: &str) -> PathBuf {
    drafts_dir().join(format!("{id}.json"))
}

fn cart_path(id: &str) -> PathBuf {
    drafts_dir().join(format!("{id}.lua"))
}

fn save(id: &str, code: &str, history: &[Value]) -> Result<(), String> {
    let dir = drafts_dir();
    std::fs::create_dir_all(&dir).map_err(|e| format!("could not make {}: {e}", dir.display()))?;
    // Drafts live in the same user-writable directory as everything else, so
    // they are staged and renamed rather than written through whatever name
    // happens to be sitting there.
    crate::safeio::write_new_then_rename(&cart_path(id), code.as_bytes())
        .map_err(|e| format!("could not write the cart: {e}"))?;
    crate::safeio::write_new_then_rename(
        &history_path(id),
        Value::Array(history.to_vec()).to_string().as_bytes(),
    )
    .map_err(|e| format!("could not write the history: {e}"))?;
    Ok(())
}

/// A conversation with the model about one draft. Large, but not unbounded.
const MAX_HISTORY_BYTES: usize = 512 * 1024;

fn load_history(id: &str) -> Vec<Value> {
    crate::safeio::read_regular_at_most(&history_path(id), MAX_HISTORY_BYTES)
        .ok()
        .flatten()
        .and_then(|b| serde_json::from_slice::<Value>(&b).ok())
        .and_then(|v| v.as_array().cloned())
        .unwrap_or_default()
}

/// Progress, as one line each, so the panel can show what is happening during a
/// wait that is measured in tens of seconds.
fn say(kind: char, text: &str) {
    let out = std::io::stdout();
    let mut out = out.lock();
    let _ = writeln!(out, "{kind} {text}");
    let _ = out.flush();
}

// ── the loop ────────────────────────────────────────────────────────────────

/// Ask, check, and if it does not work hand the error back and ask again.
///
/// The asker is a parameter so the loop can be tested without a network or a
/// key: the interesting behaviour here is the repair, not the HTTP.
fn generate(
    id: &str,
    mut history: Vec<Value>,
    ask_fn: &dyn Fn(&[Value]) -> Result<String, String>,
) -> Result<(Cart, Vec<Value>), String> {
    let mut last = String::new();
    for attempt in 1..=ATTEMPTS {
        if attempt == 1 {
            say('P', "writing it");
        } else {
            say('P', &format!("attempt {attempt} — fixing what went wrong"));
        }
        let reply = ask_fn(&history)?;
        let code = strip_fences(&reply);
        history.push(json!({"role": "assistant", "content": reply}));

        say('P', "checking it plays");
        match prove(id, &code) {
            Ok(cart) => return Ok((cart, history)),
            Err(e) => {
                last = e.clone();
                say('P', &format!("not yet: {e}"));
                history.push(json!({
                    "role": "user",
                    "content": format!(
                        "That did not work: {e}\n\nFix it and reply with the whole corrected Lua \
                         file, nothing else."
                    ),
                }));
            }
        }
    }
    Err(format!("could not get a working game after {ATTEMPTS} tries. Last problem: {last}"))
}

pub fn make(name: &str, prompt: &str) -> i32 {
    if name.trim().is_empty() || prompt.trim().is_empty() {
        eprintln!("✗ it needs a name and a description");
        return 2;
    }
    let id = free_id(&slug(name));
    let history = vec![json!({
        "role": "user",
        "content": format!(
            "Write a micromachee cart.\n\nTitle: {name}\n\nThe game: {prompt}\n\n\
             Set `-- title: {name}` in the header. Reply with the Lua file and nothing else."
        ),
    })];

    match generate(&id, history, &ask) {
        Ok((cart, history)) => {
            if let Err(e) = save(&id, &cart.code, &history) {
                say('E', &e);
                return 1;
            }
            say('P', &format!("{} is ready to play", cart.title));
            say('D', &id);
            0
        }
        Err(e) => {
            say('E', &e);
            1
        }
    }
}

pub fn revise(id: &str, prompt: &str) -> i32 {
    if prompt.trim().is_empty() {
        eprintln!("✗ say what to change");
        return 2;
    }
    // Same reason `sync` checks: an id becomes a filename, and `join` will
    // happily take `../..` or an absolute path and put the file somewhere it
    // was never meant to go. These ids arrive from the command line.
    if !shelf::valid_id(id) {
        eprintln!("✗ there is no draft called {id}");
        return 2;
    }

    let path = cart_path(id);
    if !path.exists() {
        eprintln!("✗ there is no draft called {id}");
        return 2;
    }
    let mut history = load_history(id);
    if history.is_empty() {
        // A draft whose history was lost can still be revised: hand the model
        // the code back and carry on.
        let code = crate::safeio::read_regular_at_most(&path, shelf::MAX_DRAFT_BYTES)
            .ok()
            .flatten()
            .and_then(|b| String::from_utf8(b).ok())
            .unwrap_or_default();
        history.push(json!({
            "role": "user",
            "content": format!("Here is a micromachee cart:\n\n{code}"),
        }));
    }
    history.push(json!({
        "role": "user",
        "content": format!(
            "Change the game: {prompt}\n\nReply with the whole updated Lua file, nothing else."
        ),
    }));

    match generate(id, history, &ask) {
        Ok((cart, history)) => {
            if let Err(e) = save(id, &cart.code, &history) {
                say('E', &e);
                return 1;
            }
            say('P', "changed");
            say('D', id);
            0
        }
        Err(e) => {
            say('E', &e);
            1
        }
    }
}

/// Move a draft onto the shelf. Local only — sharing a cart with anyone else is
/// `scripts/publish.sh`, which is a deliberate act with different credentials.
pub fn publish(id: &str) -> i32 {
    // Same reason `sync` checks: an id becomes a filename, and `join` will
    // happily take `../..` or an absolute path and put the file somewhere it
    // was never meant to go. These ids arrive from the command line.
    if !shelf::valid_id(id) {
        eprintln!("✗ there is no draft called {id}");
        return 2;
    }
    let from = cart_path(id);
    if !from.exists() {
        eprintln!("✗ there is no draft called {id}");
        return 2;
    }
    let code = match crate::safeio::read_regular_at_most(&from, shelf::MAX_DRAFT_BYTES) {
        Ok(Some(b)) => match String::from_utf8(b) {
            Ok(c) => c,
            Err(_) => {
                eprintln!("✗ that draft is not text");
                return 1;
            }
        },
        Ok(None) => {
            eprintln!("✗ there is no draft called {id}");
            return 2;
        }
        Err(e) => {
            eprintln!("✗ could not read the draft: {e}");
            return 1;
        }
    };
    // It was checked when it was made, but it may have been edited by hand
    // since — and the shelf is not the place to find that out.
    let cart = match prove(id, &code) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("✗ {id} does not work: {e}");
            return 1;
        }
    };
    let dir = shelf::carts_dir();
    if let Err(e) = std::fs::create_dir_all(&dir) {
        eprintln!("✗ could not make {}: {e}", dir.display());
        return 1;
    }
    let to = dir.join(format!("{id}.lua"));
    if let Err(e) = crate::safeio::write_new_then_rename(&to, code.as_bytes()) {
        eprintln!("✗ could not write {}: {e}", to.display());
        return 1;
    }
    let _ = std::fs::remove_file(&from);
    let _ = std::fs::remove_file(history_path(id));
    println!("{} is on the shelf", cart.title);
    0
}

pub fn discard(id: &str) -> i32 {
    // Same reason `sync` checks: an id becomes a filename, and `join` will
    // happily take `../..` or an absolute path and put the file somewhere it
    // was never meant to go. These ids arrive from the command line.
    if !shelf::valid_id(id) {
        eprintln!("✗ there is no draft called {id}");
        return 2;
    }
    let path = cart_path(id);
    if !path.exists() {
        eprintln!("✗ there is no draft called {id}");
        return 2;
    }
    if let Err(e) = std::fs::remove_file(&path) {
        eprintln!("✗ could not remove it: {e}");
        return 1;
    }
    let _ = std::fs::remove_file(history_path(id));
    println!("{id} is gone");
    0
}

#[cfg(test)]
mod credential_tests {
    use super::*;

    #[test]
    fn a_body_full_of_json_survives_being_a_config_value() {
        // The escaping exists so the request arrives intact; if it did not,
        // the symptom would be an API error nobody could trace to quoting.
        let body = serde_json::json!({
            "messages": [{"role": "user", "content": "a \"quoted\" prompt with \\ backslash"}]
        })
        .to_string();
        let escaped = config_value(&body);
        assert!(!escaped.contains("\\\"") || escaped.contains("\\\\\""), "quotes left unescaped");
        // Undo what curl will undo, and the original has to come back.
        let mut out = String::new();
        let mut chars = escaped.chars();
        while let Some(c) = chars.next() {
            if c == '\\' {
                match chars.next() {
                    Some('n') => out.push('\n'),
                    Some('r') => out.push('\r'),
                    Some(other) => out.push(other),
                    None => {}
                }
            } else {
                out.push(c);
            }
        }
        assert_eq!(out, body, "the body did not survive the round trip");
    }

    #[test]
    fn nothing_in_a_value_can_end_the_config_line() {
        // A newline here would turn the rest of a credential or a prompt into
        // curl directives.
        for nasty in [
            "abc\ninsecure\n",
            "abc\r\nproxy = \"http://evil\"",
            "with \"quotes\"",
            "with \\ backslash",
        ] {
            let v = config_value(nasty);
            assert!(!v.contains('\n'), "{nasty:?} kept a newline");
            assert!(!v.contains('\r'), "{nasty:?} kept a carriage return");
            // every quote is preceded by a backslash
            let bytes: Vec<char> = v.chars().collect();
            for (i, c) in bytes.iter().enumerate() {
                if *c == '"' {
                    assert!(i > 0 && bytes[i - 1] == '\\', "{nasty:?} left a bare quote");
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_rules_still_say_the_things_that_matter() {
        // The rules are the contract generation depends on. If someone trims
        // them, the failures show up as bad games rather than as a broken
        // build, so they get an assertion.
        for needed in [
            "24576", "_draw", "_init", "_update", "_cover", "btnp", "score(n)",
            "128x128", "eight colours", "indexes",
        ] {
            assert!(RULES.contains(needed), "the rules no longer mention {needed:?}");
        }
        for api in ["cls(", "pset(", "pget(", "rectb(", "circb(", "mid(", "flr("] {
            assert!(RULES.contains(api), "the rules no longer document {api}");
        }
        assert!(!RULES.contains("io."), "the rules must not suggest io, which is absent");
    }

    #[test]
    fn the_request_is_shaped_the_way_the_api_expects() {
        let body = request_body(&[json!({"role": "user", "content": "hi"})]);
        assert_eq!(body["model"], "claude-opus-5");
        assert_eq!(body["max_tokens"], MAX_TOKENS);
        // Adaptive thinking, not a token budget — budget_tokens is rejected
        // outright on this model.
        assert_eq!(body["thinking"]["type"], "adaptive");
        assert!(body["thinking"].get("budget_tokens").is_none());
        // Effort belongs inside output_config, not at the top level.
        assert_eq!(body["output_config"]["effort"], "high");
        assert!(body.get("effort").is_none());
        // A decline should be rescued rather than handed to the user.
        assert_eq!(body["fallbacks"], "default");
        // The rules are the cached prefix; they are what makes revisions cheap.
        assert_eq!(body["system"][0]["cache_control"]["type"], "ephemeral");
        assert!(body["system"][0]["text"].as_str().unwrap().contains("128x128"));
        assert_eq!(body["messages"][0]["role"], "user");
        // It has to survive serialisation — the rules contain quotes and
        // backslashes, and a hand-built body would not.
        let text = body.to_string();
        assert!(serde_json::from_str::<Value>(&text).is_ok(), "the body is not valid JSON");
    }

    #[test]
    fn a_name_becomes_a_usable_id() {
        assert_eq!(slug("Snake"), "snake");
        assert_eq!(slug("My Great Game"), "my-great-game");
        assert_eq!(slug("  Space  Rocks!! "), "space-rocks");
        assert_eq!(slug("!!!"), "game");
        assert_eq!(slug(""), "game");
        // Whatever comes out has to satisfy the cart rules, or the draft
        // cannot be parsed at all.
        for name in ["Snake", "My Great Game", "!!!", "Über Game", &"x".repeat(90)] {
            let id = slug(name);
            assert!(Cart::parse(&id, "-- title: T\nfunction _draw() end\n").is_ok(),
                    "{name:?} gave the unusable id {id:?}");
        }
    }

    #[test]
    fn fences_come_off_but_plain_lua_is_untouched() {
        assert_eq!(strip_fences("```lua\nfunction _draw() end\n```"), "function _draw() end");
        assert_eq!(strip_fences("```\nfunction _draw() end\n```"), "function _draw() end");
        let plain = "-- title: X\nfunction _draw() end";
        assert_eq!(strip_fences(plain), plain);
        // A fence that opens and never closes must not eat the last line.
        assert_eq!(strip_fences("```lua\nfunction _draw() end"), "function _draw() end");
    }

    #[test]
    fn prove_accepts_a_working_cart() {
        let code = "-- title: Fine\nx = 0\nfunction _update() x = x + 1 end\n\
                    function _draw() cls(0) rect(x % 128, 4, 3, 3, 7) end\n";
        assert!(prove("fine", code).is_ok());
    }

    #[test]
    fn prove_rejects_and_explains() {
        // Each of these is a thing a model actually does, and the message is
        // what gets handed back to it — so it has to name the problem.
        let broken = prove("bad", "-- title: Bad\nfunction _draw( end\n").unwrap_err();
        assert!(broken.to_lowercase().contains("load") || broken.contains("syntax"), "{broken}");

        let no_draw = prove("nodraw", "-- title: None\nfunction _update() end\n");
        assert!(no_draw.is_err(), "a cart with no _draw must not pass");

        let boom = prove("boom", "-- title: Boom\nfunction _draw() error('nope') end\n").unwrap_err();
        assert!(boom.contains("_draw failed"), "{boom}");

        let hang = prove("hang", "-- title: Hang\nfunction _draw() while true do end end\n").unwrap_err();
        assert!(hang.contains("_draw failed"), "{hang}");

        let big = format!("-- title: Big\nfunction _draw() end\n-- {}", "x".repeat(MAX_CART_BYTES));
        assert!(prove("big", &big).unwrap_err().contains("shorter"));
    }

    const GOOD: &str = "-- title: Good\nfunction _draw() cls(0) print('HI', 4, 4, 7) end\n";

    #[test]
    fn the_loop_returns_the_first_cart_that_works() {
        let calls = std::cell::Cell::new(0);
        let out = generate("g", vec![json!({"role": "user", "content": "x"})], &|_| {
            calls.set(calls.get() + 1);
            Ok(GOOD.to_string())
        });
        let (cart, history) = out.unwrap();
        assert_eq!(cart.title, "Good");
        assert_eq!(calls.get(), 1, "a working first answer must not be asked twice");
        assert_eq!(history.len(), 2, "the reply is kept, so a revision has context");
    }

    #[test]
    fn a_broken_answer_is_handed_back_with_the_error_and_repaired() {
        // The whole point of the strict rules: the console can tell the model
        // exactly what is wrong, so the second try is informed rather than
        // another guess.
        let calls = std::cell::Cell::new(0);
        let seen = std::cell::RefCell::new(String::new());
        let out = generate("g", vec![json!({"role": "user", "content": "x"})], &|history| {
            calls.set(calls.get() + 1);
            if calls.get() == 1 {
                Ok("-- title: Bad\nfunction _draw() error('boom') end\n".to_string())
            } else {
                // Whatever the console complained about must have reached it.
                *seen.borrow_mut() = history.last().unwrap()["content"].as_str().unwrap().to_string();
                Ok(GOOD.to_string())
            }
        });
        assert!(out.is_ok(), "{:?}", out.err());
        assert_eq!(calls.get(), 2);
        let complaint = seen.borrow().clone();
        assert!(complaint.contains("_draw failed"), "the model was not told what broke: {complaint}");
        assert!(complaint.contains("boom"), "the actual Lua error was not passed on: {complaint}");
    }

    #[test]
    fn it_gives_up_after_a_few_tries_and_says_why() {
        let calls = std::cell::Cell::new(0);
        let out = generate("g", vec![json!({"role": "user", "content": "x"})], &|_| {
            calls.set(calls.get() + 1);
            Ok("-- title: Bad\nfunction _draw( end\n".to_string())
        });
        let e = out.unwrap_err();
        assert_eq!(calls.get(), ATTEMPTS, "it must stop, not keep paying for retries");
        assert!(e.contains("Last problem"), "{e}");
    }

    #[test]
    fn a_fenced_answer_still_works() {
        let out = generate("g", vec![json!({"role": "user", "content": "x"})], &|_| {
            Ok(format!("```lua\n{GOOD}```"))
        });
        assert!(out.is_ok(), "markdown fences must not cost a repair round");
    }

    #[test]
    fn an_api_failure_stops_immediately_rather_than_retrying() {
        let calls = std::cell::Cell::new(0);
        let out = generate("g", vec![json!({"role": "user", "content": "x"})], &|_| {
            calls.set(calls.get() + 1);
            Err("the API said: overloaded".to_string())
        });
        assert!(out.unwrap_err().contains("overloaded"));
        assert_eq!(calls.get(), 1, "a transport failure is not a cart to repair");
    }

    #[test]
    fn prove_runs_a_cart_that_only_breaks_later() {
        // The whole reason it runs six hundred frames rather than one.
        let code = "-- title: Late\nn = 0\nfunction _update() n = n + 1 \
                    if n > 300 then error('fell over') end end\nfunction _draw() cls(0) end\n";
        let e = prove("late", code).unwrap_err();
        assert!(e.contains("_update failed"), "{e}");
    }
}
