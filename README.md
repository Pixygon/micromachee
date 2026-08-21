# micromachee

A tiny 8-bit fantasy console that lives in your bar. 128x128, 8 colours, one Lua file per game.

A plugin for [Omarchy](https://omarchy.org) Quattro — a widget that lives in
your bar.

## Install

```bash
./install.sh
ln -s "$PWD" ~/.config/omarchy/plugins/io.pixygon.micromachee
```

Then add the **micromachee** widget to your bar in Omarchy's plugin
settings. `install.sh` needs no root and writes nothing outside your home.

## How it is put together

```
manifest.json   what Omarchy reads: id, kind, settings schema
Panel.qml       the bar button and the panel behind it — drawing only
Service.qml     runs the helper and turns its JSON into properties
helper/         a Rust binary: everything that can actually fail
```

**The split is the important part.** QML cannot be unit-tested without a
compositor, so anything written there is only ever verified by looking at it.
Anything in `helper/` can be tested with `cargo test` on any machine. So the
helper holds the logic, and the QML layer stays dumb enough to be obviously
correct.

Two conventions the QML depends on:

- `status` prints **one line of JSON** and exits 0. The bar polls it on a timer,
  so it must be cheap and must never block.
- Every other command prints a **human sentence** to stderr and exits non-zero
  when it fails. The panel shows that last line verbatim — write it for the
  person reading the bar, not for a log.

## Working on it

```bash
cargo test  --manifest-path helper/Cargo.toml
cargo build --release --manifest-path helper/Cargo.toml
./helper/target/release/omarchy-micromachee status | jq
```

After changing QML, reload the bar (Omarchy's plugin settings has a reload, or
restart Quickshell). Changing the helper needs `./install.sh` again.

The bar gives you a glyph and a few characters, read at a glance, beside a dozen
other things competing for the same eye. Show **one** fact there — the one you
would want without clicking — and put everything else in the panel. Inherit
`bar.foreground` and `bar.fontFamily` rather than choosing your own; a widget
that ignores the theme is the one the user removes first.

## Reference

[omarchy-thread](https://github.com/Pixygon/omarchy-thread) is a complete plugin
built this way, if you want to see a finished one.

## License

MIT
