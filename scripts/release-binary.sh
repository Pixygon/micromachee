#!/usr/bin/env bash
# Build the helper, pin its hash in this repository, and upload it.
#
#   scripts/release-binary.sh              # build, pin, upload
#   scripts/release-binary.sh --dry-run    # build and pin, upload nothing
#
# This exists so a machine without Rust can still install the plugin. The order
# matters and is the whole point of the script:
#
#   1. build          the binary for this version
#   2. pin            write its sha256 into helper/prebuilt.sha256
#   3. upload         to the immutable versioned path
#
# The hash is COMMITTED. `install.sh` checks a downloaded binary against the
# repository rather than against the server that served it — a hash fetched
# alongside the file it describes verifies nothing, and the marketplace's
# security baseline rejects exactly that shape. Commit the pin file in the same
# commit as the source it was built from, or the two say different things.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$here"

dry=0
[ "${1:-}" = "--dry-run" ] && dry=1

bin="omarchy-micromachee"
arch="$(uname -m)"
version="$(sed -n '/^\[package\]/,/^\[dependencies\]/ s/^version = "\(.*\)"/\1/p' helper/Cargo.toml | head -1)"
[ -n "$version" ] || { echo "✗ could not read the version from helper/Cargo.toml" >&2; exit 1; }

echo "building $bin $version for $arch"
cargo build --release --manifest-path helper/Cargo.toml
built="helper/target/release/$bin"
sum="$(sha256sum < "$built" | cut -d' ' -f1)"
size="$(wc -c < "$built")"
echo "  $sum  ($size bytes)"

# ── pin it ──────────────────────────────────────────────────────────────────
pin="helper/prebuilt.sha256"
header='# sha256  version  arch — pinned here so a downloaded binary is checked
# against this repository, not against the server that served it.'
{
  echo "$header"
  # Keep every version that has ever been pinned: an older checkout installs
  # the binary that matches ITS source, not whatever is newest.
  if [ -f "$pin" ]; then
    grep -v '^#' "$pin" | awk -v v="$version" -v a="$arch" '$2 != v || $3 != a' || true
  fi
  echo "$sum  $version  $arch"
} > "$pin.tmp"
mv "$pin.tmp" "$pin"
echo "✓ pinned in $pin"

if [ "$dry" = 1 ]; then
  echo "dry run — nothing uploaded."
  exit 0
fi

# ── upload ──────────────────────────────────────────────────────────────────
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
[ -n "$api_key" ] || { echo "✗ no api key. Set PIXYGON_API_KEY." >&2; exit 1; }

# The CDN is configured by file extension and will not serve an extensionless
# object at all — it answers 404 while the upload reports 201.
name="$bin-$arch-linux.bin"
remote="releases/micromachee/$version"
cdn="https://pixygontech.b-cdn.net/$remote"

code="$(curl -sS -o /dev/null -w '%{http_code}' -X PUT \
  -H "x-api-key: $api_key" -H 'Content-Type: application/octet-stream' \
  --data-binary "@$built" "$api_base/$remote/$name")"
case "$code" in
  200 | 201 | 204) echo "✓ uploaded $name ($code)" ;;
  *) echo "✗ upload failed — HTTP $code" >&2; exit 1 ;;
esac

echo "checking what is actually served"
sleep 3
got="$(curl -sS --max-time 120 "$cdn/$name" | sha256sum | cut -d' ' -f1)"
if [ "$got" != "$sum" ]; then
  echo "✗ the CDN is serving something else (got $got)" >&2
  exit 1
fi
echo "  ✓ $cdn/$name matches the pin"
echo
echo "commit helper/prebuilt.sha256 — install.sh checks downloads against it."
