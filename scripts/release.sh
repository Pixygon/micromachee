#!/usr/bin/env bash
# Everything that has to happen AFTER `pearl ship`, in the right order.
#
#   pearl ship && scripts/release.sh
#
# Shipping bumps the version, and two things in this repository are keyed to
# it. Either one missed leaves a release that looks fine and is broken in a way
# nobody sees until someone else installs it:
#
#   * the catalog url carries the version, so a new release points at a shelf
#     that does not exist until it is published
#   * `web/console-data.js` is generated with that url inside it
#
# So this does them together, verifies each, and leaves one commit to push.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$here"

version="$(sed -n '/^\[package\]/,/^\[dependencies\]/ s/^version = "\(.*\)"/\1/p' helper/Cargo.toml | head -1)"
echo "releasing $version"
echo

echo "[1/4] building"
cargo build --release --manifest-path helper/Cargo.toml

echo "[2/4] regenerating the web player's data (it carries the catalog url)"
MICROMACHEE_WRITE_PALETTES=1 cargo test --manifest-path helper/Cargo.toml \
  the_committed_palettes >/dev/null
grep -q "$version" web/console-data.js || {
  echo "✗ web/console-data.js does not mention $version" >&2
  exit 1
}

echo "[3/4] publishing the shelf"
./scripts/publish.sh | tail -2

echo "[4/4] checking it the way a stranger would"
tmp="$(mktemp -d)"
MICROMACHEE_CARTS="$tmp" ./helper/target/release/omarchy-micromachee sync | tail -1
rm -rf "$tmp"

echo
echo "done. Commit and push:"
echo "  git add -A && git commit -m \"Publish the $version shelf and binary\" && git push"
