#!/usr/bin/env bash
# Stamp the project version into the two files that keep a copy of it.
#
# The version itself lives in the Pixygon Changelog API and `pearl ship` bumps
# it there. manifest.json (what Omarchy reads) and helper/Cargo.toml (what the
# binary reports) are copies, and copies drift — manifest.json sat at 0.1.0
# through six releases before anyone noticed. Run this after a ship:
#
#   pearl ship && scripts/version.sh && git commit -am "stamp version"
#
# Pass a version to set one explicitly: scripts/version.sh 0.7.0
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
v="${1:-}"

if [ -z "$v" ]; then
  v="$(pearl info 2>/dev/null | awk '$1 == "version" { print $2; exit }')"
fi

if ! [[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "✗ '$v' is not a version. Pass one: scripts/version.sh 0.7.0" >&2
  exit 1
fi

# Only the [package] version — the dependency lines carry versions too.
sed -i '/^\[package\]/,/^\[dependencies\]/ s/^version = ".*"/version = "'"$v"'"/' \
  "$here/helper/Cargo.toml"
sed -i 's/^\(  "version": \)"[^"]*"/\1"'"$v"'"/' "$here/manifest.json"

echo "✓ stamped $v"
grep -m1 '^version' "$here/helper/Cargo.toml" | sed 's/^/  helper\/Cargo.toml  /'
grep -m1 '"version"' "$here/manifest.json"   | sed 's/^ */  manifest.json      /'
