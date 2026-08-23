//! Where carts live, and how new ones arrive.
//!
//! A cart is a file. The shelf is a directory of them. Adding a game to your
//! own console is `cp mygame.lua ~/.local/share/omarchy-micromachee/carts/` and
//! nothing else — no install step, no index to regenerate, no registry to
//! notify. `sync` exists only to fetch other people's carts from a catalog on
//! the internet; it is not how carts work, just one way they can travel.

use std::path::PathBuf;
use std::process::{Command, Stdio};

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

/// The host the shelf is published on, taken from the default catalog rather
/// than written out again, so the two cannot drift apart.
pub fn catalog_host(url: &str) -> Option<String> {
    let rest = url.strip_prefix("https://")?;
    let host = rest.split(['/', '?', '#']).next()?;
    let host = host.rsplit('@').next()?; // ignore any userinfo
    let host = host.split(':').next()?; // and any port
    if host.is_empty() {
        None
    } else {
        Some(host.to_ascii_lowercase())
    }
}

/// Addresses a catalog must never be able to send this program at.
///
/// Not a general SSRF defence and not presented as one — a name that resolves
/// to an internal address is still a name, and stopping that needs resolving it
/// here and connecting by address, which is a DNS client this program does not
/// have. What it does stop is the direct forms: the cloud metadata endpoint,
/// loopback, and the private ranges written as literals. The real protection is
/// the host allowlist below, which leaves nothing for this to catch on the
/// shipped shelf.
fn is_local_address(host: &str) -> bool {
    if host == "localhost" || host.ends_with(".localhost") || host == "[::1]" {
        return true;
    }
    let octets: Vec<&str> = host.split('.').collect();
    if octets.len() == 4 {
        if let Ok(a) = octets[0].parse::<u8>() {
            let b = octets[1].parse::<u8>().unwrap_or(0);
            if octets.iter().all(|o| o.parse::<u8>().is_ok()) {
                return a == 127                       // loopback
                    || a == 10                        // private
                    || a == 0                         // this network
                    || (a == 172 && (16..=31).contains(&b))
                    || (a == 192 && b == 168)
                    || (a == 169 && b == 254)         // link-local, and 169.254.169.254
                    || (a == 100 && (64..=127).contains(&b)); // carrier NAT
            }
        }
    }
    host.starts_with('[') // any other IPv6 literal
}

/// Whether a url in a catalog is one this program is willing to follow.
///
/// `sync` used to hand each entry's url straight to curl, which speaks a great
/// many protocols this program has no business speaking — `file:`, `dict:`,
/// `gopher:`, `scp:` — and would follow any host at all. A catalog is somebody
/// else's file, so it does not get to choose either.
pub fn allowed_url(url: &str, expect_host: Option<&str>) -> Result<(), String> {
    if !url.starts_with("https://") {
        return Err("only https urls are followed".into());
    }
    let Some(host) = catalog_host(url) else {
        return Err("that url has no host".into());
    };
    if is_local_address(&host) {
        return Err(format!("{host} is a local or internal address"));
    }
    if let Some(want) = expect_host {
        if host != want.to_ascii_lowercase() {
            return Err(format!("{host} is not {want}, where the shelf is published"));
        }
    }
    Ok(())
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
        "mega": false,
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
            "mega": c.in_mega,
        }))
        .collect::<Vec<_>>())
}

/// Whether this cart is still a draft — made here and not yet put on the shelf.
pub fn is_draft(id: &str) -> bool {
    valid_id(id) && crate::make::drafts_dir().join(format!("{id}.lua")).exists()
}

pub fn find(id: &str) -> Option<PathBuf> {
    // Ids reach here from the command line and from the panel too, and the same
    // join that let a catalog escape the cart directory would let
    // `micromachee play ../../something` read outside it.
    if !valid_id(id) {
        return None;
    }
    for dir in search_paths() {
        let p = dir.join(format!("{id}.lua"));
        if p.exists() {
            return Some(p);
        }
    }
    None
}

// ── what the console remembers ──────────────────────────────────────────────

/// The most the state file may be. It holds settings and one small object of
/// saved values per cart; anything approaching this is not our state any more.
const MAX_STATE_BYTES: usize = 1024 * 1024;

/// A draft is a cart that has not been published yet, and is bounded like one.
pub const MAX_DRAFT_BYTES: usize = MAX_CART_BYTES;

pub fn load_state() -> Value {
    // Bounded, and refused if it is a symlink or stopped being a regular file
    // while it was opened. This is read on nearly every command, so an
    // enormous or redirected state file was the cheapest thing to leave lying
    // around for this program to walk into.
    match crate::safeio::read_regular_at_most(&state_path(), MAX_STATE_BYTES) {
        Ok(Some(body)) => serde_json::from_slice(&body).unwrap_or_else(|_| json!({})),
        _ => json!({}),
    }
}

fn save_state(v: &Value) {
    // Staged under a name that is created exclusively and never reused, then
    // renamed. The previous version wrote through a fixed `state.json.tmp`,
    // which is a name anyone could sit a symlink on and wait for.
    let body = serde_json::to_string(v).unwrap_or_else(|_| "{}".into());
    let _ = crate::safeio::write_new_then_rename(&state_path(), body.as_bytes());
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
/// Where the generated sound bank lives. Beside the state, not beside the
/// carts: it is the console's, not the shelf's.
pub fn sounds_dir() -> PathBuf {
    state_path().parent().map(|p| p.join("sounds")).unwrap_or_else(|| PathBuf::from("sounds"))
}

/// Sound is off by default in nothing — but a widget in a bar that makes noise
/// without being asked is a widget people uninstall, so this is honoured
/// everywhere and the panel can turn it off in one press.
pub fn saved_muted() -> bool {
    load_state().get("muted").and_then(|v| v.as_bool()).unwrap_or(false)
}

pub fn set_muted(on: bool) {
    let mut state = load_state();
    if !state.is_object() {
        state = json!({});
    }
    state["muted"] = json!(on);
    save_state(&state);
}

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

/// A single cart's saved data may not exceed this once serialized. The per-key
/// bounds in the VM already keep an honest cart far under it; this is the
/// backstop that makes "one cart cannot bloat the shared state file" true
/// regardless of how the data got into the map.
const MAX_CART_SAVE_BYTES: usize = 128 * 1024;

pub fn store_save(id: &str, data: &serde_json::Map<String, Value>) {
    let blob = Value::Object(data.clone());
    if blob.to_string().len() > MAX_CART_SAVE_BYTES {
        // Dropped rather than written: persisting this would risk the next
        // load_state refusing the whole file and taking every cart's saves
        // with it. Losing one oversized cart's write is the smaller harm.
        return;
    }
    let mut state = load_state();
    if !state.is_object() {
        state = json!({});
    }
    state["saves"][id] = blob;
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

/// The most a catalog may be. It carries every cart's source inline, so it is
/// legitimately the largest thing fetched — fourteen carts of 24K each plus
/// JSON is under half a megabyte, and this is four times that.
const MAX_CATALOG_BYTES: usize = 2 * 1024 * 1024;

/// A cart id, and therefore a filename stem, and nothing else.
///
/// This is the check that was missing. `PathBuf::join` **replaces** the base
/// when given an absolute path and happily walks upward on `..`, so an id taken
/// from a remote catalog and pasted into a path meant any endpoint serving that
/// catalog could choose where on the disk a file landed: `../../x` climbed out
/// of the cart directory and `/tmp/x` ignored it altogether. Every `.lua` file
/// the user could write was reachable.
///
/// Ids are generated from filename stems and from `slug()`, both of which
/// already produce exactly this alphabet, so nothing legitimate is excluded.
pub fn valid_id(id: &str) -> bool {
    !id.is_empty()
        && id.len() <= 40
        && !id.starts_with('-')
        && id
            .chars()
            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-' || c == '_')
}

/// Fetch at most `limit` bytes.
///
/// The limit is enforced HERE rather than on the result, because a check that
/// runs after the download has already let the whole thing into memory. curl's
/// own `--max-filesize` is passed as well and is not enough on its own: it
/// works from Content-Length, which a chunked response simply does not send.
/// So the pipe is read with a hard ceiling and the child is killed the moment
/// it goes over.
fn fetch_at_most(url: &str, limit: usize) -> Result<Vec<u8>, String> {
    // curl rather than a TLS stack: this binary sits in a bar all day, and a
    // whole HTTP client to download a text file now and then is not a trade
    // worth making. `doctor` says so if curl is missing.
    let child = Command::new("curl")
        // Redirects are not followed at all.
        //
        // The allowlist runs before this, once, on the url we were given. `-L`
        // then handed curl permission to go somewhere else entirely: a 302 from
        // an allowed host could point at an internal https endpoint and nothing
        // would check it, because the check had already happened. Restricting
        // the redirect PROTOCOL does not help — the destination host is the
        // problem, and curl cannot ask us about it.
        //
        // So the check and the request are made to be about the same URL. The
        // shelf serves 200 directly and has never redirected; if it ever needs
        // to, the right answer is to read the Location, put it through
        // `allowed_url` and fetch again — deliberately, not as a side effect of
        // a flag.
        .args([
            "-fsS",
            // The status, on stderr, so it cannot be confused with the body.
            // `-f` covers 4xx and 5xx; without this a 3xx we refuse to follow
            // would arrive as a short body and be reported as malformed JSON,
            // which says nothing about what actually happened.
            "-w",
            "%{stderr}%{http_code}",
            "--max-redirs",
            "0",
            "--proto",
            "=https",
            "--proto-redir",
            "=https",
            "--max-time",
            "20",
            "--max-filesize",
            &limit.to_string(),
            url,
        ])
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| format!("could not run curl: {e}"))?;

    // Bounded at the pipe; see safeio::read_child_bounded for the stdout-first
    // ordering and why draining stderr first would deadlock.
    let (body, note, status) = crate::safeio::read_child_bounded(child, limit)
        .map_err(|_| format!("{url} is larger than {limit} bytes — refused"))?;

    // A redirect we declined to follow.
    //
    // `-w` writes at the very end, so the status is the TRAILING digits. Taking
    // every digit in the buffer instead would fold in any curl message that
    // happens to contain one — `curl: (35) SSL connect error` followed by `000`
    // reads as 35000, which starts with a three and would be reported as a
    // redirect that never happened.
    let note = String::from_utf8_lossy(&note);
    let code: String = note
        .chars()
        .rev()
        .take_while(|c| c.is_ascii_digit())
        .collect::<Vec<_>>()
        .into_iter()
        .rev()
        .collect();
    if code.len() == 3 && code.starts_with('3') {
        return Err(format!("{url} answered {code} — redirects are not followed"));
    }

    if !status.success() {
        // 63 is curl's own "exceeded the maximum allowed file size". On a
        // chunked response there is no Content-Length to check up front, so
        // curl counts as it goes and aborts — which reads as a plain network
        // failure unless it is named.
        if status.code() == Some(63) {
            return Err(format!("{url} is larger than {limit} bytes — refused"));
        }
        return Err(format!("{url} could not be fetched"));
    }
    Ok(body)
}

/// Pull the catalog and any carts named in it that are not already here.
/// What is already on disk, relative to what the catalog is offering.
#[derive(Debug, PartialEq, Eq)]
pub enum Local {
    /// Nothing here yet.
    Absent,
    /// Here and byte-identical to the shelf.
    Current,
    /// Here and different. Might be an old copy; might be one you changed.
    Stale,
}

/// The whole of the decision, kept out of `sync` so it can be tested without a
/// network. A catalog entry with no checksum is taken as "leave it alone" — an
/// absent hash must never be read as a mismatch, or every cart on an old
/// catalog would report itself stale.
pub fn compare(local: Option<&[u8]>, want_sha: Option<&str>) -> Local {
    match local {
        None => Local::Absent,
        Some(bytes) => match want_sha {
            None => Local::Current,
            Some(want) if crate::sha256::hex(bytes).eq_ignore_ascii_case(want) => Local::Current,
            Some(_) => Local::Stale,
        },
    }
}

/// Fetch the published shelf.
///
/// A cart already on disk is never quietly replaced — yours might be a cart you
/// wrote, or one you edited, and losing that to a routine `sync` would be
/// unforgivable. But "already here" said nothing about whether the copy was
/// still current, so a machine that installed early sat on the old shelf
/// forever with nothing anywhere saying so: the titles had changed underneath
/// it and the only symptom was a shelf that looked subtly wrong.
///
/// So a cart whose bytes differ from the catalog is now counted separately and
/// reported, and `--update` replaces those — keeping a `.lua.bak` beside each
/// one, because the whole reason for not overwriting was that the file might
/// have been yours.
pub fn sync(update: bool) -> i32 {
    // A local catalog, for developing against a shelf that is not published
    // yet. Deliberately a SEPARATE variable holding a path rather than a
    // `file:` url through the fetcher: the point of the scheme check is that a
    // catalog cannot send this program at a local resource, and that stays true
    // if the only way to read one is an explicit choice made here, by whoever
    // is running the command, with no url involved anywhere.
    let (body, host, url) = if let Ok(path) = std::env::var("MICROMACHEE_CATALOG_FILE") {
        let path = std::path::PathBuf::from(path);
        println!("→ {} (local)", path.display());
        match crate::safeio::read_regular_at_most(&path, MAX_CATALOG_BYTES) {
            // A local catalog has no origin of its own, so its entries are
            // still held to the published one. Otherwise this path would be the
            // one place an arbitrary host could be reached, which is exactly
            // what the check exists to prevent.
            Ok(Some(b)) => (b, catalog_host(DEFAULT_CATALOG), path.display().to_string()),
            Ok(None) => {
                eprintln!("✗ {} is not there", path.display());
                return 1;
            }
            Err(e) => {
                eprintln!("✗ {e}");
                return 1;
            }
        }
    } else {
        let url = catalog_url();
        println!("→ {url}");
        // An override may point somewhere else, but not at a different KIND of
        // thing: still https, still not an internal address.
        if let Err(e) = allowed_url(&url, None) {
            eprintln!("✗ {url}: {e}");
            return 2;
        }
        let host = catalog_host(&url);
        match fetch_at_most(&url, MAX_CATALOG_BYTES) {
            Ok(b) => (b, host, url),
            Err(e) => {
                eprintln!("✗ {e}");
                return 1;
            }
        }
    };
    let _ = &url;
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

    let (mut got, mut skipped, mut failed, mut replaced) = (0, 0, 0, 0);
    let mut stale: Vec<String> = Vec::new();

    for entry in carts {
        let Some(id) = entry.get("id").and_then(|v| v.as_str()) else { continue };
        // The catalog is somebody else's file. It does not get to choose where
        // on this disk anything lands.
        if !valid_id(id) {
            println!("  ✗ {id} is not a cart name — refused");
            failed += 1;
            continue;
        }
        let dest = dir.join(format!("{id}.lua"));

        // What is already here, and is it the same thing the catalog is
        // offering? Without the second half of that question, "already here" is
        // indistinguishable from "already up to date".
        //
        // Bounded and symlink-refusing: this is a file something else on the
        // machine can replace, so it is read the same careful way as anything
        // off the network. A link here would otherwise be followed and its
        // target copied into the backup below.
        let local = match crate::safeio::read_regular_at_most(&dest, MAX_CART_BYTES) {
            Ok(v) => v,
            Err(e) => {
                println!("  ✗ {id}: {e}");
                failed += 1;
                continue;
            }
        };
        match compare(local.as_deref(), entry.get("sha256").and_then(|v| v.as_str())) {
            Local::Absent => {}
            Local::Current => {
                skipped += 1;
                continue;
            }
            Local::Stale if !update => {
                stale.push(id.to_string());
                continue;
            }
            Local::Stale => {}
        }
        // A catalog may carry the source inline; if it does there is nothing to
        // fetch. Older catalogs only have a url, so both still work.
        let fetched = match entry.get("code").and_then(|v| v.as_str()) {
            Some(code) => Ok(code.as_bytes().to_vec()),
            None => match entry.get("url").and_then(|v| v.as_str()) {
                Some(u) => match allowed_url(u, host.as_deref()) {
                    // Pinned to the host the catalog itself came from. On the
                    // shipped shelf that is one origin and nothing else is
                    // reachable, which is what makes the address checks above
                    // a backstop rather than the defence.
                    Ok(()) => fetch_at_most(u, MAX_CART_BYTES),
                    Err(e) => Err(format!("{u}: {e}")),
                },
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
                        // Keep whatever was there. It may have been edited, and
                        // this is the one command that would have eaten it.
                        let was = local.as_ref().map(|b| {
                            let old = String::from_utf8_lossy(b).to_string();
                            let title = Cart::parse(id, &old)
                                .map(|o| o.title)
                                .unwrap_or_else(|_| id.to_string());
                            // The backup gets the same treatment as the cart.
                            // It was the one write still going out through
                            // plain `fs::write`, and a link at `<id>.lua.bak`
                            // would have been followed.
                            let _ = crate::safeio::write_new_then_rename(
                                &dir.join(format!("{id}.lua.bak")),
                                b,
                            );
                            title
                        });
                        // Never opens `dest`. Staged and renamed, so there is
                        // no window between deciding it is safe to write and
                        // writing — the destination is only ever replaced.
                        if crate::safeio::write_new_then_rename(&dest, text.as_bytes()).is_ok() {
                            match was {
                                Some(old) if old != c.title => {
                                    println!("  ↻ {id} — {} by {} (was {old}, old copy kept as {id}.lua.bak)", c.title, c.author);
                                    replaced += 1;
                                }
                                Some(_) => {
                                    println!("  ↻ {id} — {} by {} (old copy kept as {id}.lua.bak)", c.title, c.author);
                                    replaced += 1;
                                }
                                None => {
                                    println!("  ✓ {id} — {} by {}", c.title, c.author);
                                    got += 1;
                                }
                            }
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
    print!("{got} new");
    if replaced > 0 {
        print!(", {replaced} updated");
    }
    println!(", {skipped} already here, {failed} failed → {}", dir.display());

    // The sentence that was missing. A shelf can be silently a version behind
    // and look like nothing more than a shelf.
    if !stale.is_empty() {
        println!(
            "\n{} cart(s) here differ from the shelf: {}",
            stale.len(),
            stale.join(", ")
        );
        println!("`micromachee sync --update` replaces them and keeps your copies as .lua.bak");
    }
    i32::from(failed > 0 && got == 0)
}

#[cfg(test)]
mod url_tests {
    use super::*;

    const HOST: &str = "pixygontech.b-cdn.net";

    #[test]
    fn the_published_shelf_is_reachable() {
        assert!(allowed_url(DEFAULT_CATALOG, None).is_ok(), "{DEFAULT_CATALOG}");
        assert_eq!(catalog_host(DEFAULT_CATALOG).as_deref(), Some(HOST));
        let cart = format!("https://{HOST}/releases/micromachee/9.9.9/snake.lua");
        assert!(allowed_url(&cart, Some(HOST)).is_ok());
    }

    #[test]
    fn nothing_but_https_is_followed() {
        // curl speaks a great many protocols this program has no business
        // speaking, and each entry's url used to go straight to it.
        for bad in [
            "file:///etc/passwd",
            "file://localhost/etc/shadow",
            "dict://127.0.0.1:11211/stat",
            "gopher://127.0.0.1:6379/_INFO",
            "scp://host/x",
            "http://pixygontech.b-cdn.net/x.lua",
            "ftp://pixygontech.b-cdn.net/x.lua",
            "/etc/passwd",
            "",
        ] {
            assert!(allowed_url(bad, None).is_err(), "{bad} was allowed");
        }
    }

    #[test]
    fn a_catalog_cannot_point_at_the_machine_it_is_running_on() {
        for bad in [
            "https://169.254.169.254/latest/meta-data/",   // cloud metadata
            "https://127.0.0.1/x",
            "https://localhost/x",
            "https://10.0.0.5/x",
            "https://192.168.1.1/x",
            "https://172.16.0.1/x",
            "https://172.31.255.255/x",
            "https://[::1]/x",
            "https://0.0.0.0/x",
        ] {
            assert!(allowed_url(bad, None).is_err(), "{bad} was allowed");
        }
        // and the ones that only look private
        assert!(allowed_url("https://172.32.0.1/x", None).is_ok());
        assert!(allowed_url("https://11.0.0.1/x", None).is_ok());
    }

    #[test]
    fn an_entry_may_not_leave_the_origin_its_catalog_came_from() {
        for bad in [
            "https://evil.example/snake.lua",
            "https://pixygontech.b-cdn.net.evil.example/snake.lua",
            "https://user@evil.example/snake.lua",
        ] {
            assert!(allowed_url(bad, Some(HOST)).is_err(), "{bad} was allowed");
        }
    }

    #[test]
    fn userinfo_and_ports_cannot_disguise_the_host() {
        // `https://real-host@evil/` is a url whose HOST is evil.
        assert_eq!(catalog_host("https://a@evil.example/x").as_deref(), Some("evil.example"));
        assert_eq!(catalog_host("https://host.example:8443/x").as_deref(), Some("host.example"));
        assert_eq!(catalog_host("https://HOST.example/x").as_deref(), Some("host.example"));
    }
}

#[cfg(test)]
mod id_tests {
    use super::*;

    #[test]
    fn a_cart_id_is_a_filename_stem_and_nothing_else() {
        for good in ["snake", "the-veil", "rogue2", "my_game", "a"] {
            assert!(valid_id(good), "{good} should be a usable id");
        }
    }

    #[test]
    fn nothing_that_could_name_a_path_is_an_id() {
        // Every one of these was accepted before, and each one chose where on
        // the disk `sync` wrote a file.
        for bad in [
            "../../pwned",
            "..",
            "/tmp/absolute",
            "/etc/passwd",
            "a/b",
            "a\\b",
            "snake/../../x",
            "",
            "-rf",
            "Snake",          // ids are the lowercase stem, never the title
            "sn ake",
            "sn.ake",
            "sn\0ake",
        ] {
            assert!(!valid_id(bad), "{bad:?} was accepted as an id");
        }
        assert!(!valid_id(&"x".repeat(41)), "an id may not be unbounded");
    }

    #[test]
    fn a_refused_id_cannot_be_turned_into_a_path() {
        // The property that actually matters, stated directly: for anything
        // `valid_id` accepts, joining it onto a directory stays under that
        // directory. `join` replaces the base for an absolute path and walks
        // up for `..`, so this is the whole defence.
        let base = std::path::Path::new("/base/carts");
        for id in ["snake", "the-veil", "my_game"] {
            let p = base.join(format!("{id}.lua"));
            assert!(p.starts_with(base), "{id} escaped to {}", p.display());
            assert_eq!(p.components().filter(|c| matches!(c, std::path::Component::ParentDir)).count(), 0);
        }
    }

    #[test]
    fn the_shelf_will_not_look_up_a_traversing_id() {
        assert!(find("../../../../etc/passwd").is_none());
        assert!(find("/etc/passwd").is_none());
        assert!(!is_draft("../../x"));
    }
}

#[cfg(test)]
mod sync_tests {
    use super::*;

    const BODY: &[u8] = b"-- title: Signcarver\nfunction _draw() end\n";

    fn sha_of(b: &[u8]) -> String {
        crate::sha256::hex(b)
    }

    #[test]
    fn a_cart_that_is_not_here_is_fetched() {
        assert_eq!(compare(None, Some(&sha_of(BODY))), Local::Absent);
    }

    #[test]
    fn a_cart_that_matches_the_shelf_is_left_alone() {
        assert_eq!(compare(Some(BODY), Some(&sha_of(BODY))), Local::Current);
        // and the comparison must not care how the hash was cased
        assert_eq!(compare(Some(BODY), Some(&sha_of(BODY).to_uppercase())), Local::Current);
    }

    #[test]
    fn an_old_copy_is_stale_rather_than_current() {
        // Exactly the case that left a shelf reading "Picross" months after the
        // cart became "Signcarver", with `sync` cheerfully saying "already here".
        let old = b"-- title: Picross\nfunction _draw() end\n";
        assert_eq!(compare(Some(old), Some(&sha_of(BODY))), Local::Stale);
    }

    #[test]
    fn a_catalog_without_hashes_never_calls_anything_stale() {
        // Older catalogs carry only urls. Reading a missing hash as a mismatch
        // would offer to replace every cart on the shelf, every time.
        assert_eq!(compare(Some(BODY), None), Local::Current);
        let anything = b"-- title: Something Else\n";
        assert_eq!(compare(Some(anything), None), Local::Current);
    }
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
