//! Reading and writing files that something else can also write.
//!
//! The cart directory and the state file live under `$HOME`, and everything in
//! this program had been treating them as if this process were the only thing
//! that touches them. It is not: anything else running as the user can put a
//! symlink where a cart should be, swap a path between a check and the write
//! that follows it, or leave a very large file where a small one is expected.
//!
//! None of that is a privilege boundary — a process that can do those things
//! can also just drop a cart in the directory. It is still worth closing,
//! because each one turns "this program wrote a file" into "this program wrote
//! a file somewhere else, or read all of one into memory", and neither was ever
//! intended.
//!
//! Two primitives, used everywhere a cart, a backup or the state is touched:
//!
//! - [`read_regular_at_most`] — checks the path, opens it, and then verifies
//!   **the descriptor it actually got** is the thing it checked, before reading
//!   a bounded number of bytes from that same descriptor. Checking a path and
//!   then opening it is two operations on a name; this makes the second half a
//!   question about the open file.
//! - [`write_new_then_rename`] — never opens the destination at all. It creates
//!   a fresh, uniquely named file with `O_CREAT|O_EXCL`, which cannot follow a
//!   symlink because it fails outright if anything is already there, and then
//!   renames it into place. `rename` replaces the *name*, so a symlink that
//!   appears at the destination in the meantime is replaced rather than
//!   written through.
//!
//! This is Linux-only, like the rest of the plugin, so `MetadataExt` is used
//! directly rather than behind a cfg.

use std::fs::{File, OpenOptions};
use std::io::{Read, Write};
use std::os::unix::fs::MetadataExt;
use std::path::Path;
use std::sync::atomic::{AtomicU64, Ordering};

/// Bumped per call so two writes in the same process, in the same nanosecond,
/// cannot choose the same staging name.
static NONCE: AtomicU64 = AtomicU64::new(0);

/// Read at most `limit` bytes from a regular file, or `None` if it is not there.
///
/// Refuses a symlink, refuses anything that is not a regular file, refuses a
/// file that grew past the limit, and refuses a path that changed identity
/// between being checked and being opened.
pub fn read_regular_at_most(path: &Path, limit: usize) -> Result<Option<Vec<u8>>, String> {
    let before = match std::fs::symlink_metadata(path) {
        Ok(m) => m,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(e) => return Err(format!("{} could not be read: {e}", path.display())),
    };
    if before.file_type().is_symlink() {
        return Err(format!("{} is a symlink — refused", path.display()));
    }
    if !before.file_type().is_file() {
        return Err(format!("{} is not a regular file — refused", path.display()));
    }

    let file = File::open(path).map_err(|e| format!("{} could not be opened: {e}", path.display()))?;

    // The check above was about a NAME. This one is about the descriptor that
    // name actually resolved to, and the two only agree if nothing swapped the
    // path in between.
    let after = file
        .metadata()
        .map_err(|e| format!("{} could not be inspected: {e}", path.display()))?;
    if after.ino() != before.ino() || after.dev() != before.dev() {
        return Err(format!("{} changed while it was being opened — refused", path.display()));
    }
    if !after.file_type().is_file() {
        return Err(format!("{} is not a regular file — refused", path.display()));
    }

    // Bounded at the descriptor rather than by trusting the size from the
    // metadata: a file can grow between the two, and `read_to_end` would
    // happily follow it.
    let mut body = Vec::new();
    file.take(limit as u64 + 1)
        .read_to_end(&mut body)
        .map_err(|e| format!("{} could not be read: {e}", path.display()))?;
    if body.len() > limit {
        return Err(format!("{} is larger than {limit} bytes — refused", path.display()));
    }
    Ok(Some(body))
}

/// Write `data` to `dest` without ever opening `dest`.
///
/// Staged through a uniquely named sibling created with `create_new`, which is
/// `O_CREAT|O_EXCL` and therefore fails rather than follows if anything —
/// including a symlink somebody planted — is already at that name. The rename
/// is atomic, so a reader either sees the old file or the new one and never a
/// half-written one.
pub fn write_new_then_rename(dest: &Path, data: &[u8]) -> Result<(), String> {
    let dir = dest
        .parent()
        .filter(|p| !p.as_os_str().is_empty())
        .ok_or_else(|| format!("{} has no directory to write into", dest.display()))?;
    std::fs::create_dir_all(dir).map_err(|e| format!("could not make {}: {e}", dir.display()))?;

    let stem = dest.file_name().and_then(|s| s.to_str()).unwrap_or("out");

    let mut last = String::new();
    for _ in 0..8 {
        let nonce = NONCE.fetch_add(1, Ordering::Relaxed);
        let stamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.subsec_nanos() as u64)
            .unwrap_or(0);
        let tmp = dir.join(format!(".{stem}.{}.{}.{nonce}.part", std::process::id(), stamp));

        match OpenOptions::new().write(true).create_new(true).open(&tmp) {
            Ok(mut f) => {
                let wrote = f
                    .write_all(data)
                    .and_then(|_| f.sync_all())
                    .map_err(|e| format!("could not write {}: {e}", tmp.display()));
                drop(f);
                if let Err(e) = wrote {
                    let _ = std::fs::remove_file(&tmp);
                    return Err(e);
                }
                if let Err(e) = std::fs::rename(&tmp, dest) {
                    let _ = std::fs::remove_file(&tmp);
                    return Err(format!("could not put {} in place: {e}", dest.display()));
                }
                return Ok(());
            }
            // Taken already: try another name rather than touching that one.
            Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => {
                last = format!("{} was already there", tmp.display());
                continue;
            }
            Err(e) => return Err(format!("could not create {}: {e}", tmp.display())),
        }
    }
    Err(format!("could not find a free name to write {} ({last})", dest.display()))
}

/// Read a spawned child's output with a hard ceiling on the body.
///
/// `Command::output()` and `wait_with_output()` both buffer to completion,
/// which hands the child — or whatever is on the other end of it — the decision
/// of how much memory this process allocates. Every place that shells out to
/// curl for something off the network goes through here instead: the body is
/// read from the pipe up to `limit`, and the moment it goes over, the child is
/// killed rather than drained.
///
/// stdout FIRST, then stderr. curl's `-w` status and any complaint are written
/// only once the transfer ends, so draining stderr to EOF before the body
/// deadlocks the instant the body outgrows a pipe buffer: the child blocks
/// writing stdout while this blocks reading stderr. The body is the big one, so
/// it goes first; stderr is small and capped.
///
/// The child must be spawned with stdout and stderr piped. Returns the body,
/// the (bounded) stderr, and the exit status; `Err` if the body exceeded the
/// limit or the child could not be waited on.
pub fn read_child_bounded(
    mut child: std::process::Child,
    limit: usize,
) -> Result<(Vec<u8>, Vec<u8>, std::process::ExitStatus), String> {
    let mut body = Vec::new();
    if let Some(out) = child.stdout.take() {
        // limit + 1, so going over is detectable rather than a silent truncation.
        let _ = out.take(limit as u64 + 1).read_to_end(&mut body);
    }
    if body.len() > limit {
        let _ = child.kill();
        let _ = child.wait();
        return Err(format!("the response is larger than {limit} bytes — refused"));
    }
    let mut note = Vec::new();
    if let Some(err) = child.stderr.take() {
        // A status line and maybe one line of complaint, never a payload.
        let _ = err.take(4096).read_to_end(&mut note);
    }
    let status = child.wait().map_err(|e| format!("the command did not finish: {e}"))?;
    Ok((body, note, status))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::symlink;

    struct Dir(std::path::PathBuf);
    impl Dir {
        fn new(tag: &str) -> Dir {
            let p = std::env::temp_dir().join(format!(
                "mm-safeio-{tag}-{}-{}",
                std::process::id(),
                NONCE.fetch_add(1, Ordering::Relaxed)
            ));
            let _ = std::fs::remove_dir_all(&p);
            std::fs::create_dir_all(&p).unwrap();
            Dir(p)
        }
    }
    impl Drop for Dir {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }

    #[test]
    fn a_flooding_child_is_bounded_and_killed() {
        use std::process::{Command, Stdio};
        // yes writes an endless stream; the reader must stop at the limit and
        // kill it rather than buffer forever.
        let child = Command::new("yes")
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn();
        let Ok(child) = child else { return }; // no `yes` here; skip rather than fail
        let r = read_child_bounded(child, 64 * 1024);
        assert!(r.is_err(), "an endless child was not refused");
        assert!(r.unwrap_err().contains("larger than"));
    }

    #[test]
    fn a_small_child_returns_its_output_and_status() {
        use std::process::{Command, Stdio};
        let child = Command::new("printf")
            .arg("hello")
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn();
        let Ok(child) = child else { return };
        let (body, _note, status) = read_child_bounded(child, 1024).unwrap();
        assert_eq!(body, b"hello");
        assert!(status.success());
    }

    #[test]
    fn an_ordinary_file_reads_back() {
        let d = Dir::new("plain");
        let p = d.0.join("a.lua");
        std::fs::write(&p, b"hello").unwrap();
        assert_eq!(read_regular_at_most(&p, 100).unwrap().as_deref(), Some(&b"hello"[..]));
    }

    #[test]
    fn an_absent_file_is_absent_and_not_an_error() {
        let d = Dir::new("absent");
        assert_eq!(read_regular_at_most(&d.0.join("nope.lua"), 100).unwrap(), None);
    }

    #[test]
    fn a_symlink_is_never_read_through() {
        // Following one here would copy a file from elsewhere into a directory
        // whoever planted the link can read.
        let d = Dir::new("readlink");
        let secret = d.0.join("secret");
        std::fs::write(&secret, b"not yours").unwrap();
        let link = d.0.join("snake.lua");
        symlink(&secret, &link).unwrap();

        let err = read_regular_at_most(&link, 100).unwrap_err();
        assert!(err.contains("symlink"), "{err}");
    }

    #[test]
    fn a_file_over_the_limit_is_refused_rather_than_loaded() {
        let d = Dir::new("big");
        let p = d.0.join("big.lua");
        std::fs::write(&p, vec![b'x'; 5_000]).unwrap();
        assert!(read_regular_at_most(&p, 10_000).unwrap().is_some());
        let err = read_regular_at_most(&p, 1_000).unwrap_err();
        assert!(err.contains("larger than"), "{err}");
    }

    #[test]
    fn writing_replaces_a_symlink_instead_of_writing_through_it() {
        // The race the check-then-write version left open: even if a link
        // appears after any check, the destination is never opened, so the
        // target cannot be written. The link itself is replaced.
        let d = Dir::new("writelink");
        let target = d.0.join("elsewhere");
        std::fs::write(&target, b"original").unwrap();
        let dest = d.0.join("snake.lua");
        symlink(&target, &dest).unwrap();

        write_new_then_rename(&dest, b"new cart").unwrap();

        assert_eq!(std::fs::read(&target).unwrap(), b"original", "wrote through the link");
        assert_eq!(std::fs::read(&dest).unwrap(), b"new cart");
        assert!(!std::fs::symlink_metadata(&dest).unwrap().file_type().is_symlink());
    }

    #[test]
    fn writing_leaves_nothing_staged_behind() {
        let d = Dir::new("staging");
        write_new_then_rename(&d.0.join("a.lua"), b"one").unwrap();
        write_new_then_rename(&d.0.join("a.lua"), b"two").unwrap();
        let left: Vec<String> = std::fs::read_dir(&d.0)
            .unwrap()
            .filter_map(|e| e.ok())
            .map(|e| e.file_name().to_string_lossy().to_string())
            .filter(|n| n.ends_with(".part"))
            .collect();
        assert!(left.is_empty(), "staging files left: {left:?}");
        assert_eq!(std::fs::read(d.0.join("a.lua")).unwrap(), b"two");
    }

    #[test]
    fn a_staged_name_is_never_the_same_twice() {
        // The old state write used a fixed `state.json.tmp`, which anyone could
        // sit a symlink on and wait.
        let d = Dir::new("names");
        let mut seen = std::collections::HashSet::new();
        for i in 0..40 {
            write_new_then_rename(&d.0.join("s.json"), format!("{i}").as_bytes()).unwrap();
            // The name is gone by the time this returns, so uniqueness is
            // checked through the nonce that builds it.
            seen.insert(NONCE.load(Ordering::Relaxed));
        }
        assert_eq!(seen.len(), 40, "staging names repeated");
    }

    #[test]
    fn a_directory_where_a_file_belongs_is_refused() {
        let d = Dir::new("isdir");
        let p = d.0.join("weird.lua");
        std::fs::create_dir(&p).unwrap();
        let err = read_regular_at_most(&p, 100).unwrap_err();
        assert!(err.contains("regular file"), "{err}");
    }
}
