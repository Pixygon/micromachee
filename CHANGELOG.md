# Changelog

All notable changes to **micromachee**. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this file is
materialized from the Pixygon Changelog API — edit there, not here.

## [0.5.0] — 2026-08-21

### Added
- New `micromachee tty <id>` command plays a cart right in your terminal, no bar widget or extra process required. Frames are drawn using half-block characters for near full resolution, with arrow keys or WASD plus z/x for buttons and q to quit.

### Changed
- Theme palette generation moved from a Python script into the Rust helper itself, so palettes are now built directly into the binary rather than parsed from JSON at startup. The exported `themes/palettes.json` file is still generated and kept in sync for other consumers.

### Improved
- Running `play` directly at a prompt now prints a helpful note pointing you to `tty` instead of dumping raw frame protocol data to your terminal.


