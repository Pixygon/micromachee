#!/usr/bin/env bash
# Build and install the helper the plugin runs. Nothing here needs root, and
# nothing outside your home directory is touched.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
prefix="${PREFIX:-$HOME/.local}"
id="io.pixygon.micromachee"
bin="omarchy-micromachee"

command -v cargo >/dev/null || { echo "This needs Rust: pacman -S rust"; exit 1; }

echo "building the helper…"
cargo build --release --manifest-path "$here/helper/Cargo.toml"
install -Dm755 "$here/helper/target/release/$bin" "$prefix/bin/$bin"

echo "✓ installed $prefix/bin/$bin"

# The shelf looks in ./carts and then in the data directory. The bar widget is
# started by Quickshell from wherever Quickshell happens to be, which is never
# this repo — so without this step the widget comes up with an empty shelf.
carts="${MICROMACHEE_CARTS:-${XDG_DATA_HOME:-$HOME/.local/share}/omarchy-micromachee/carts}"
mkdir -p "$carts"
install -m644 -t "$carts" "$here"/carts/*.lua
echo "✓ installed $(ls -1 "$here"/carts/*.lua | wc -l) cart(s) to $carts"
case ":$PATH:" in
  *":$prefix/bin:"*) ;;
  *) echo "  note: $prefix/bin is not on your PATH" ;;
esac

if [ "$here" != "$HOME/.config/omarchy/plugins/$id" ]; then
  echo
  echo "To load the plugin, put this directory where Omarchy looks:"
  echo "  ln -s '$here' ~/.config/omarchy/plugins/$id"
fi
echo "Then add the micromachee widget to your bar."
echo
echo "To play without the bar at all:"
echo "  $bin list"
echo "  $bin tty rogue"
