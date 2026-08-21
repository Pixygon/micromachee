//! Where carts live, and how new ones arrive.
//!
//! A cart is a file. The shelf is a directory of them. Adding a game to your
//! own console is `cp mygame.lua ~/.local/share/omarchy-micromachee/carts/` and
//! nothing else — no install step, no index to regenerate, no registry to
//! notify. `sync` exists only to fetch other people's carts from a catalog on
//! the internet; it is not how carts work, just one way they can travel.

use std::path::PathBuf;
use std::process::Command;

use serde_json::{json, Value};

use crate::cart::{Cart, MAX_CART_BYTES};

/// The published shelf, at a path that carries this build's version.
///
/// The CDN caches for thirty days and there is no purge in the factory, so a
/// stable url is a url that keeps serving whatever was first uploaded to it —
/// a republished catalog simply never arrives. Versioned paths are immutable
/// instead: every release publishes to its own, nothing is ever overwritten,
/// and an older binary keeps seeing the shelf it shipped with, which is honest
/// rather than broken.
const DEFAULT_CATALOG: &str = concat!(
    "https://pixygontech.b-cdn.net/releases/micromachee/",
    env!("CARGO_PKG_VERSION"),
    "/catalog.json"
);

/// Where the cart files themselves live. Only used when generating a catalog —
/// `sync` follows whatever url each entry carries.
pub const DEFAULT_CART_BASE: &str = concat!(
    "https://pixygontech.b-cdn.net/releases/micromachee/",
    env!("CARGO_PKG_VERSION")
);

fn xdg(var: &str, fallback: &str) -> PathBuf {
    std::env::var(var).map(PathBuf::from).unwrap_or_else(|_| {
        PathBuf::from(std::env::var("HOME").unwrap_or_else(|_| "/tmp".into())).join(fallback)
    })
}

pub fn carts_dir() -> PathBuf {
    if let Ok(dir) = std::env::var("MICROMACHEE_CARTS") {
        return PathBuf::from(dir);
    }
    xdg("XDG_DATA_HOME", ".local/share").join("omarchy-micromachee/carts")
}

pub fn state_path() -> PathBuf {
    xdg("XDG_STATE_HOME", ".local/state").join("omarchy-micromachee/state.json")
}

pub fn catalog_url() -> String {
    std::env::var("MICROMACHEE_CATALOG").unwrap_or_else(|_| DEFAULT_CATALOG.into())
}

/// Every directory carts may come from, in the order they win ties.
///
/// A `carts/` beside the working directory comes first so that working on a
/// game means running it, with no install step in the loop.
fn search_paths() -> Vec<PathBuf> {
    let mut v = vec![PathBuf::from("carts")];
    v.push(carts_dir());
    // Drafts are ordinary carts in a different folder. Looking here means a
    // just-made game is playable with no publishing step and nothing special
    // anywhere in the player.
    v.push(crate::make::drafts_dir());
    v
}

pub fn list() -> Vec<Cart> {
    let mut out: Vec<Cart> = Vec::new();
    for dir in search_paths() {
        let Ok(entries) = std::fs::read_dir(&dir) else { continue };
        for e in entries.flatten() {
            let path = e.path();
            if path.extension().and_then(|x| x.to_str()) != Some("lua") {
                continue;
            }
            // A cart that does not parse is skipped rather than fatal: one bad
            // file in the directory must not take the whole shelf down.
            if let Ok(c) = Cart::load(&path) {
                if !out.iter().any(|existing| existing.id == c.id) {
                    out.push(c);
                }
            }
        }
    }
    out.sort_by(|a, b| a.title.to_lowercase().cmp(&b.title.to_lowercase()));

    out
}

/// What a front end shows: the carts on disk, led by the meta-game.
///
/// The meta-game is not a file and never will be — there is nothing for a
/// `mega.lua` to contain — so it is added here rather than given a special case
/// in every shelf that gets drawn. `list()` itself stays exactly what it says:
/// the carts that exist.
pub fn shelf_json() -> Value {
    let mut carts = vec![json!({
        "id": crate::mega::MEGA_ID,
        "title": crate::mega::MEGA_TITLE,
        "author": "pixygon",
        "about": crate::mega::MEGA_ABOUT,
        "bytes": 0,
        "best": best(crate::mega::MEGA_ID),
        "draft": false,
    })];
    if let Value::Array(rest) = list_json() {
        carts.extend(rest);
    }
    Value::Array(carts)
}

pub fn list_json() -> Value {
    json!(list()
        .iter()
        .map(|c| json!({
            "id": c.id, "title": c.title, "author": c.author,
            "about": c.about, "bytes": c.bytes, "best": best(&c.id),
            // A draft is playable like anything else; the shelf just says so,
            // and offers to publish or throw it away.
            "draft": is_draft(&c.id),
        }))
        .collect::<Vec<_>>())
}

/// Whether this cart is still a draft — made here and not yet put on the shelf.
pub fn is_draft(id: &str) -> bool {
    crate::make::drafts_dir().join(format!("{id}.lua")).exists()
}

pub fn find(id: &str) -> Option<PathBuf> {
    for dir in search_paths() {
        let p = dir.join(format!("{id}.lua"));
        if p.exists() {
            return Some(p);
        }
    }
    None
}

// ── what the console remembers ──────────────────────────────────────────────

pub fn load_state() -> Value {
    std::fs::read_to_string(state_path())
        .ok()
        .and_then(|t| serde_json::from_str(&t).ok())
        .unwrap_or_else(|| json!({}))
}

fn save_state(v: &Value) {
    let path = state_path();
    if let Some(dir) = path.parent() {
        let _ = std::fs::create_dir_all(dir);
        let tmp = dir.join("state.json.tmp");
        if std::fs::write(&tmp, serde_json::to_string(v).unwrap_or_else(|_| "{}".into())).is_ok() {
            let _ = std::fs::rename(tmp, &path);
        }
    }
}

/// The theme the player chose, if they chose one.
/// How many screen pixels one console pixel gets. Kept here rather than in the
/// plugin settings so the buttons on the console can change it: a widget you
/// have to open a settings page to resize is one you resize once and never
/// again.
pub fn saved_scale() -> i64 {
    load_state().get("scale").and_then(|v| v.as_i64()).unwrap_or(3).clamp(2, 6)
}

pub fn set_scale(n: i64) -> i64 {
    let n = n.clamp(2, 6);
    let mut state = load_state();
    if !state.is_object() {
        state = json!({});
    }
    state["scale"] = json!(n);
    save_state(&state);
    n
}

/// Whether the console is speaking the Ydrast. Off unless somebody found it.
pub fn saved_tongue() -> bool {
    load_state().get("tongue").and_then(|v| v.as_str()) == Some("ydrast")
}

pub fn set_tongue(on: bool) {
    let mut state = load_state();
    if !state.is_object() {
        state = json!({});
    }
    state["tongue"] = json!(if on { "ydrast" } else { "plain" });
    save_state(&state);
}

pub fn saved_theme() -> Option<String> {
    load_state().get("theme").and_then(|v| v.as_str()).map(String::from)
}

pub fn set_theme(id: &str) {
    let mut state = load_state();
    state["theme"] = json!(id);
    save_state(&state);
}

pub fn best(id: &str) -> i64 {
    load_state().get("best").and_then(|b| b.get(id)).and_then(|v| v.as_i64()).unwrap_or(0)
}

/// The console keeps the records, not the game. A cart calls `score(n)` and
/// forgets about it; nothing in a cart can read or write another cart's best,
/// and a game cannot lower your record by mistake.
/// What a cart has saved. Kept beside the high scores, because it is the same
/// kind of thing: something the console remembers about a game between runs.
pub fn load_save(id: &str) -> serde_json::Map<String, Value> {
    load_state()
        .get("saves")
        .and_then(|s| s.get(id))
        .and_then(|v| v.as_object())
        .cloned()
        .unwrap_or_default()
}

pub fn store_save(id: &str, data: &serde_json::Map<String, Value>) {
    let mut state = load_state();
    if !state.is_object() {
        state = json!({});
    }
    state["saves"][id] = Value::Object(data.clone());
    save_state(&state);
}

pub fn record_score(id: &str, score: i64) {
    let mut state = load_state();
    let prev = state.get("best").and_then(|b| b.get(id)).and_then(|v| v.as_i64()).unwrap_or(0);
    state["last"] = json!(id);
    if score > prev {
        if !state.get("best").map(|b| b.is_object()).unwrap_or(false) {
            state["best"] = json!({});
        }
        state["best"][id] = json!(score);
    }
    save_state(&state);
}

// ── carts from elsewhere ────────────────────────────────────────────────────

fn fetch(url: &str) -> Result<Vec<u8>, String> {
    // curl rather than a TLS stack: this binary sits in a bar all day, and a
    // whole HTTP client to download a text file now and then is not a trade
    // worth making. `doctor` says so if curl is missing.
    let out = Command::new("curl")
        .args(["-fsSL", "--max-time", "20", url])
        .output()
        .map_err(|e| format!("could not run curl: {e}"))?;
    if !out.status.success() {
        return Err(format!("{url} could not be fetched"));
    }
    Ok(out.stdout)
}

/// Pull the catalog and any carts named in it that are not already here.
pub fn sync() -> i32 {
    let url = catalog_url();
    println!("→ {url}");
    let body = match fetch(&url) {
        Ok(b) => b,
        Err(e) => {
            eprintln!("✗ {e}");
            return 1;
        }
    };
    let catalog: Value = match serde_json::from_slice(&body) {
        Ok(v) => v,
        Err(e) => {
            eprintln!("✗ the catalog is not JSON: {e}");
            return 1;
        }
    };
    let Some(carts) = catalog.get("carts").and_then(|c| c.as_array()) else {
        eprintln!("✗ the catalog has no `carts` array");
        return 1;
    };

    let dir = carts_dir();
    if let Err(e) = std::fs::create_dir_all(&dir) {
        eprintln!("✗ could not make {}: {e}", dir.display());
        return 1;
    }

    let (mut got, mut skipped, mut failed) = (0, 0, 0);
    for entry in carts {
        let Some(id) = entry.get("id").and_then(|v| v.as_str()) else { continue };
        let dest = dir.join(format!("{id}.lua"));
        if dest.exists() {
            skipped += 1;
            continue;
        }
        // A catalog may carry the source inline; if it does there is nothing to
        // fetch. Older catalogs only have a url, so both still work.
        let fetched = match entry.get("code").and_then(|v| v.as_str()) {
            Some(code) => Ok(code.as_bytes().to_vec()),
            None => match entry.get("url").and_then(|v| v.as_str()) {
                Some(u) => fetch(u),
                None => continue,
            },
        };
        match fetched {
            Ok(bytes) => {
                // The size limit is enforced here too. A catalog is somebody
                // else's file; it does not get to raise our ceiling.
                if bytes.len() > MAX_CART_BYTES {
                    println!("  ✗ {id} is {} bytes — over the {MAX_CART_BYTES} limit", bytes.len());
                    failed += 1;
                    continue;
                }
                // A catalog that publishes a hash is taken at its word about
                // it. Without this the field is decoration, and decoration in a
                // manifest is worse than no field at all.
                if let Some(want) = entry.get("sha256").and_then(|v| v.as_str()) {
                    let got = crate::sha256::hex(&bytes);
                    if !got.eq_ignore_ascii_case(want) {
                        println!("  ✗ {id} did not match its checksum — not saved");
                        failed += 1;
                        continue;
                    }
                }
                let text = String::from_utf8_lossy(&bytes).to_string();
                match Cart::parse(id, &text) {
                    Ok(c) => {
                        if std::fs::write(&dest, &text).is_ok() {
                            println!("  ✓ {id} — {} by {}", c.title, c.author);
                            got += 1;
                        } else {
                            failed += 1;
                        }
                    }
                    Err(e) => {
                        println!("  ✗ {id}: {e}");
                        failed += 1;
                    }
                }
            }
            Err(e) => {
                println!("  ✗ {id}: {e}");
                failed += 1;
            }
        }
    }
    println!("{got} new, {skipped} already here, {failed} failed → {}", dir.display());
    i32::from(failed > 0 && got == 0)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Point the shelf at a scratch directory for the duration of a test.
    ///
    /// Environment variables are process-global and cargo runs tests in
    /// parallel, so these hold a lock for their whole life. Without it the
    /// three tests below pass or fail depending on who set `XDG_STATE_HOME`
    /// last — which is exactly the kind of flake that gets a suite ignored.
    static SHELF_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

    struct Sandbox(PathBuf, std::sync::MutexGuard<'static, ()>);
    impl Sandbox {
        fn new(name: &str) -> Sandbox {
            let guard = SHELF_LOCK.lock().unwrap_or_else(|e| e.into_inner());
            let dir = std::env::temp_dir().join(format!("mm-test-{name}-{}", std::process::id()));
            let _ = std::fs::remove_dir_all(&dir);
            std::fs::create_dir_all(dir.join("carts")).unwrap();
            std::env::set_var("MICROMACHEE_CARTS", dir.join("carts"));
            std::env::set_var("XDG_STATE_HOME", &dir);
            Sandbox(dir, guard)
        }
    }
    impl Drop for Sandbox {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
            std::env::remove_var("MICROMACHEE_CARTS");
            std::env::remove_var("XDG_STATE_HOME");
        }
    }

    #[test]
    fn a_record_only_goes_up() {
        let _s = Sandbox::new("best");
        record_score("snake", 10);
        assert_eq!(best("snake"), 10);
        record_score("snake", 3);
        assert_eq!(best("snake"), 10, "a worse run must not overwrite a record");
        record_score("snake", 42);
        assert_eq!(best("snake"), 42);
    }

    #[test]
    fn records_are_kept_per_cart() {
        let _s = Sandbox::new("percart");
        record_score("snake", 10);
        record_score("breakout", 5);
        assert_eq!(best("snake"), 10);
        assert_eq!(best("breakout"), 5);
        assert_eq!(best("never-played"), 0);
    }

    #[test]
    fn playing_remembers_what_was_last_played() {
        let _s = Sandbox::new("last");
        record_score("breakout", 1);
        assert_eq!(load_state()["last"], json!("breakout"));
    }

    #[test]
    fn a_broken_cart_does_not_take_the_shelf_down() {
        let s = Sandbox::new("broken");
        let dir = s.0.join("carts");
        std::fs::write(dir.join("good.lua"), "-- title: Good\nfunction _draw() end").unwrap();
        std::fs::write(dir.join("bad.lua"), "this file has no draw").unwrap();
        std::fs::write(dir.join("notes.txt"), "not a cart at all").unwrap();
        let carts = list();
        assert_eq!(carts.len(), 1, "only the good one should show");
        assert_eq!(carts[0].title, "Good");
    }

    #[test]
    fn find_locates_a_cart_by_id() {
        let s = Sandbox::new("find");
        std::fs::write(s.0.join("carts/pong.lua"), "-- title: Pong\nfunction _draw() end").unwrap();
        assert!(find("pong").is_some());
        assert!(find("nothing-here").is_none());
    }
}
