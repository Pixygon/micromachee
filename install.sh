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

# Built from source, always.
#
# There used to be a fallback here that downloaded a prebuilt helper and checked
# it against a SHA-256 committed to this repository. That proved the bytes
# matched the ones we published — it did not prove those bytes were built from
# this source. Nothing tied the executable to the commit you are reading, so
# "verified" meant rather less than it looked like it meant.
#
# The honest options were a CI build with signed provenance that the installer
# checks, or no downloaded executable at all. This plugin is a few thousand
# lines of Rust and Arch is one command away from a compiler, so it is the
# second one: what runs on your machine is built on your machine, from the
# source you can read.
if ! command -v cargo >/dev/null; then
  echo "Micromachee builds its helper from source and needs Rust to do it:" >&2
  echo "" >&2
  echo "    sudo pacman -S rust" >&2
  echo "" >&2
  echo "Then run this again. Nothing is downloaded and run — the binary is built here." >&2
  exit 1
fi
build_from_source

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

# The sound bank is generated, not shipped: eight short WAVs written by the
# helper itself. Regenerating on every install means the files always match the
# binary that plays them, and it keeps audio out of the repository.
# `$bin`, not `$id`. This ran the plugin id as if it were a program for two
# releases, and because the failure was sent to /dev/null the only symptom was
# a console that never made a sound and a note that did not say why. Errors are
# shown now: a step that can only report success is a step nobody can debug.
if sound_err="$("$prefix/bin/$bin" sounds 2>&1 >/dev/null)"; then
  echo "✓ generated the sound bank"
else
  echo "  note: could not generate sounds — the console will be quiet" >&2
  [ -n "$sound_err" ] && echo "  $(printf '%s' "$sound_err" | tail -1)" >&2
fi

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
