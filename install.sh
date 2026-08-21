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
