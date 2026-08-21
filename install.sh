#!/usr/bin/env bash
# Build and install the helper the plugin runs. Nothing here needs root, and
# nothing outside your home directory is touched.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
prefix="${PREFIX:-$HOME/.local}"
id="io.pixygon.micromachee"
bin="omarchy-micromachee"

version="$(sed -n '/^\[package\]/,/^\[dependencies\]/ s/^version = "\(.*\)"/\1/p' "$here/helper/Cargo.toml" | head -1)"

# Building from source is the normal path and the one to prefer: you get the
# binary that matches the code in front of you. The download below exists only
# for a machine without Rust, and it is checked against a hash committed to this
# repository — not one fetched from the same server as the binary, which would
# verify nothing.
build_from_source() {
  echo "building the helper…"
  cargo build --release --manifest-path "$here/helper/Cargo.toml"
  install -Dm755 "$here/helper/target/release/$bin" "$prefix/bin/$bin"
}

fetch_prebuilt() {
  local arch pinned url tmp got
  arch="$(uname -m)"
  [ "$arch" = "x86_64" ] || return 1
  [ -r "$here/helper/prebuilt.sha256" ] || return 1

  # <sha256>  <version>  <arch>
  pinned="$(awk -v v="$version" -v a="$arch" '$2 == v && $3 == a { print $1 }' \
            "$here/helper/prebuilt.sha256")"
  [ -n "$pinned" ] || return 1

  url="https://pixygontech.b-cdn.net/releases/micromachee/$version/$bin-$arch-linux.bin"
  tmp="$(mktemp)"
  echo "no cargo here — fetching the $version build and checking it against the hash in this repo…"
  curl -fsSL --max-time 120 -o "$tmp" "$url" || { rm -f "$tmp"; return 1; }
  got="$(sha256sum < "$tmp" | cut -d" " -f1)"
  if [ "$got" != "$pinned" ]; then
    rm -f "$tmp"
    echo "  ✗ what arrived is not what this repository says it should be — not installing it." >&2
    return 1
  fi
  install -Dm755 "$tmp" "$prefix/bin/$bin"
  rm -f "$tmp"
  echo "  ✓ verified against helper/prebuilt.sha256"
}

if command -v cargo >/dev/null; then
  build_from_source
elif fetch_prebuilt; then
  :
else
  echo "This needs Rust to build the helper: sudo pacman -S rust" >&2
  echo "(or a matching prebuilt binary, which is not available for this version/arch)" >&2
  exit 1
fi

echo "✓ installed $prefix/bin/$bin"

# The shelf looks in ./carts and then in the data directory. The bar widget is
# started by Quickshell from wherever Quickshell happens to be, which is never
# this repo — so without this step the widget comes up with an empty shelf.
carts="${MICROMACHEE_CARTS:-${XDG_DATA_HOME:-$HOME/.local/share}/omarchy-micromachee/carts}"
mkdir -p "$carts"
added=0
kept=0
for f in "$here"/carts/*.lua; do
  # Never overwrite a cart that is already there. A game you wrote, or one you
  # edited, is yours — and a reinstall silently replacing it would be the worst
  # kind of data loss, because you would not find out until you played it.
  if [ -e "$carts/$(basename "$f")" ]; then
    kept=$((kept + 1))
  else
    install -m644 "$f" "$carts/"
    added=$((added + 1))
  fi
done
echo "✓ installed $added cart(s) to $carts${kept:+ (kept $kept already there)}"
case ":$PATH:" in
  *":$prefix/bin:"*) ;;
  *) echo "  note: $prefix/bin is not on your PATH" ;;
esac

# Put the plugin where Omarchy looks. Done here rather than printed as an
# instruction, because "now run this one other command" is where an install
# stops being an install. Idempotent, and it never clobbers a link that points
# somewhere else — that would silently swap out someone's own checkout.
plugins="$HOME/.config/omarchy/plugins"
link="$plugins/$id"
if [ "$here" = "$link" ]; then
  :                                   # already living in the right place
elif [ ! -d "$plugins" ]; then
  echo
  echo "No $plugins here — not an Omarchy machine? To load the plugin there:"
  echo "  ln -s '$here' '$link'"
elif [ -L "$link" ] && [ "$(readlink -f "$link")" = "$(readlink -f "$here")" ]; then
  echo "✓ already linked into Omarchy"
elif [ -e "$link" ]; then
  echo "⚠ $link already exists and is not this directory — leaving it alone."
  echo "  Replace it yourself if you meant to: rm '$link' && ln -s '$here' '$link'"
else
  ln -s "$here" "$link" && echo "✓ linked into Omarchy: $link"
fi
echo "Then add the micromachee widget to your bar."
echo
echo "To play without the bar at all:"
echo "  $bin list"
echo "  $bin tty rogue"
