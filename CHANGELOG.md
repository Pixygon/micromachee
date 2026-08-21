# Changelog

All notable changes to **micromachee**. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this file is
materialized from the Pixygon Changelog API — edit there, not here.

## [0.8.0] — 2026-08-21

### Added
- Carts can now draw their own cover art with an optional _cover() function, giving each game a proper thumbnail on the shelf and a full-size splash screen before it starts, drawn with the same primitives and eight-colour palette as the game itself. Carts without a _cover() still get a cover automatically, generated from a few seconds of real gameplay.
- New micromachee cover <id|file> [-o out.png] command lets you preview a cart's cover art (or its auto-generated fallback) as a PNG.
- print() now accepts an optional scale argument, letting carts render text at larger sizes — handy for bold titles on cover art and title screens. Existing calls without the argument behave exactly as before.
- The panel now shows an on-screen d-pad and O/X buttons under the game screen, each labeled with the keyboard key that triggers it. They can be clicked with the mouse and light up in sync with keyboard input.
- Every cart on the shelf list now shows a small thumbnail of its cover art (or an initial letter as a fallback) instead of just text.
- All seven bundled carts (breakout, meteor, picross, pong, rogue, snake, tunnel) now ship with hand-drawn cover art.

### Changed
- Choosing a cart on the shelf now raises its cover art full-size with a "PRESS X TO START" prompt instead of jumping straight into play, giving you a moment to see the game and get your hands on the controls first.
- Escape now backs out one step at a time: it stops a running game, then returns from the cover prompt to the shelf, then closes the panel — rather than closing immediately.


## [0.7.0] — 2026-08-21

### Added
- Added a Screen Size setting for the console panel, letting you choose how large the emulated screen renders (2x–6x console pixels) to suit your display.

### Changed
- The panel now resizes to fit the selected screen size, with a taller maximum panel height to accommodate larger console displays.

### Fixed
- The console screen now scales in whole-pixel steps and renders at crisp integer sizes, eliminating the shimmering/blurring that occurred when the display didn't line up evenly with screen pixels.


## [0.6.1] — 2026-08-21

### Added
- `micromachee sync` now verifies each cart's SHA-256 checksum as it downloads, so a cart that arrives corrupted or tampered with is refused rather than saved.
- New `micromachee catalog` command generates catalog.json directly from the carts/ folder, so the published shelf listing can never go stale or drift from what's actually there.
- The shelf catalog is now published for real, with five new carts available via `micromachee sync`: Picross, Pong, Rogue, plus the existing Breakout, Meteor, Snake, and Tunnel.

### Changed
- Carts and the catalog are now served from a new URL path. Existing setups will pick this up automatically the next time they sync.


## [0.6.0] — 2026-08-21

### Changed
- Documentation now clarifies that `micromachee sync` currently has no published catalog to fetch from, so running it will report a failure to fetch until one is published.

### Improved
- After installing, the script now tells you exactly how many carts were installed and prints quick commands to try the game in a terminal (`list` and `tty <cart>`) without needing the bar widget.

### Fixed
- The bar widget no longer comes up with an empty shelf: install.sh now copies the shipped carts into the data directory it reads from, instead of leaving them only in the repo where Quickshell never looks.


## [0.5.0] — 2026-08-21

### Added
- New `micromachee tty <id>` command plays a cart right in your terminal, no bar widget or extra process required. Frames are drawn using half-block characters for near full resolution, with arrow keys or WASD plus z/x for buttons and q to quit.

### Changed
- Theme palette generation moved from a Python script into the Rust helper itself, so palettes are now built directly into the binary rather than parsed from JSON at startup. The exported `themes/palettes.json` file is still generated and kept in sync for other consumers.

### Improved
- Running `play` directly at a prompt now prints a helpful note pointing you to `tty` instead of dumping raw frame protocol data to your terminal.


