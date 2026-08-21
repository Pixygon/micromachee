#!/usr/bin/env bash
# Publish the shelf: every cart in carts/, plus a freshly generated catalog.
#
# `micromachee sync` reads the catalog and follows each entry's url, so the two
# have to go up together — a catalog naming carts that are not there is worse
# than no catalog at all. This regenerates the catalog from the very carts it is
# about to upload, so the two cannot disagree.
#
#   scripts/publish.sh              # publish, then check what is served
#   scripts/publish.sh --dry-run    # say what it would do, upload nothing
#
# Auth is Pearl's, resolved the way Pearl resolves it: $PIXYGON_API_KEY, then
# ~/.config/pearl/auth.json, then Dyson's config.toml. The key is never printed.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$here"

dry=0
[ "${1:-}" = "--dry-run" ] && dry=1

# ── auth ────────────────────────────────────────────────────────────────────
api_key="${PIXYGON_API_KEY:-}"
api_base="${PIXYGON_API_BASE:-}"

auth_json="$HOME/.config/pearl/auth.json"
if [ -z "$api_key" ] && [ -f "$auth_json" ]; then
  api_key="$(sed -n 's/.*"apiKey"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$auth_json" | head -1)"
fi

dyson="$HOME/.config/dyson-swarm/config.toml"
if [ -z "$api_key" ] && [ -f "$dyson" ]; then
  api_key="$(sed -n 's/^[[:space:]]*api_key[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$dyson" | head -1)"
fi
if [ -z "$api_base" ] && [ -f "$dyson" ]; then
  api_base="$(sed -n 's/^[[:space:]]*api_url[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$dyson" | head -1)"
fi

api_base="${api_base:-https://api.pixygon.com/v1}"
api_base="${api_base%/}"
case "$api_base" in */v1) ;; *) api_base="$api_base/v1" ;; esac

if [ -z "$api_key" ]; then
  echo "✗ no api key. Set PIXYGON_API_KEY, or let Pearl's config provide it." >&2
  exit 1
fi

bin="$here/helper/target/release/omarchy-micromachee"
[ -x "$bin" ] || { echo "✗ build it first: ./install.sh" >&2; exit 1; }

# Where the files land, and therefore the urls the catalog will carry.
#
# The release API's route is <slug>/<channel>/<file> — three segments. Two
# segments is not a shorter version of it, it is a 404, which is what publishing
# to `releases/micromachee/` gets you. `shelf` is the channel: a fixed name, not
# a version, so the catalog url stays put across releases.
# Versioned, and never reused: the CDN caches for thirty days with no purge
# available, so publishing twice to one path means the second time is invisible.
version="$(sed -n '/^\[package\]/,/^\[dependencies\]/ s/^version = "\(.*\)"/\1/p' helper/Cargo.toml | head -1)"
[ -n "$version" ] || { echo "✗ could not read the version from helper/Cargo.toml" >&2; exit 1; }
# The release API's route is <slug>/<channel>/<file> — exactly three segments,
# so the version IS the channel. A fourth segment is a 404, not a subfolder.
remote="${MICROMACHEE_REMOTE:-releases/micromachee/$version}"
cdn="https://pixygontech.b-cdn.net/$remote"

echo "publishing $version to $cdn"
"$bin" catalog --base "$cdn" >/dev/null

carts=(carts/*.lua)
echo "publishing ${#carts[@]} cart(s) + catalog.json"
[ "$dry" = 1 ] && echo "  (dry run — nothing will be uploaded)"

put() { # put <local-file> <remote-name>
  local file="$1" name="$2" code
  if [ "$dry" = 1 ]; then
    printf '  would put %-16s → %s/%s\n' "$name" "$cdn" "$name"
    return 0
  fi
  code="$(curl -sS -o /dev/null -w '%{http_code}' -X PUT \
    -H "x-api-key: $api_key" -H 'Content-Type: application/octet-stream' \
    --data-binary "@$file" "$api_base/$remote/$name")"
  case "$code" in
    200 | 201 | 204) printf '  ✓ %-16s %s\n' "$name" "$code" ;;
    *) printf '  ✗ %-16s HTTP %s\n' "$name" "$code" ; return 1 ;;
  esac
}

failed=0
for f in "${carts[@]}"; do put "$f" "$(basename "$f")" || failed=1; done
# The catalog goes last: until it is up, nothing points at a half-published shelf.
put catalog.json catalog.json || failed=1

if [ "$dry" = 1 ]; then
  echo "dry run done."
  exit 0
fi

if [ "$failed" != 0 ]; then
  echo "✗ something did not upload — the catalog may name files that are not there." >&2
  exit 1
fi

# ── prove it, rather than assume it ─────────────────────────────────────────
# Compare BYTES, not status codes. A stale edge-cached file answers 200 just as
# cheerfully as a fresh one, which is exactly how a republished catalog went
# unnoticed for a whole afternoon.
echo "checking what is actually served"
sleep 3
bad=0
same() { # same <url> <local-file>
  local got want
  got="$(curl -sS --max-time 30 "$1" | sha256sum | cut -d" " -f1)"
  want="$(sha256sum < "$2" | cut -d" " -f1)"
  [ "$got" = "$want" ]
}
for f in "${carts[@]}"; do
  name="$(basename "$f")"
  same "$cdn/$name" "$f" || { echo "  ✗ $name is not what we uploaded"; bad=1; }
done
same "$cdn/catalog.json" catalog.json || { echo "  ✗ catalog.json is not what we uploaded"; bad=1; }
[ "$bad" = 0 ] && echo "  ✓ all $(( ${#carts[@]} + 1 )) files are live and are the bytes we sent"

echo
echo "now try it the way a stranger would, into an empty shelf:"
echo "  MICROMACHEE_CARTS=\"\$(mktemp -d)\" $bin sync"
exit "$bad"
