# Changelog

All notable changes to **micromachee**. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this file is
materialized from the Pixygon Changelog API — edit there, not here.

## [0.17.0] — 2026-08-21

### Added
- Added a hidden Ydrast language mode — enter a secret button combo on the shelf (or run `micromachee tongue ydrast`) and every cart's on-screen text is rendered in a fully rule-based constructed language, with a fixed lexicon, consistent word-coining, and digits spoken as words. Running carts and covers update immediately when you switch tongues, and the setting persists.
- Added a new cart, Pixiel — an endless runner where you hop and leap over gaps and blocks as a discarded robot body that just keeps going.

### Changed
- Renamed several shipped carts to match their in-world lore: Recycler is now Serpent, The Signs is now Signcarver, and Seedplate is now Farm of Arra, with updated in-game text and cover art to match.

### Improved
- Updated documentation to describe the new hidden language feature and the expanded cart shelf.

### Fixed
- Cart metadata (title, author, about) that gets silently truncated at the length limit is now flagged by the cart checker, so an oversized field is caught before it ships instead of quietly cutting off mid-word.


## [0.16.0] — 2026-08-21

### Added
- Documentation now includes a guide to where each cart's new name comes from in the Pixygon Codex, giving players lore context for Recycler, The Veil, Plate Fall, Down-Shaft, The Whale, The Signs, Abaddon, and Seedplate.

### Changed
- All eight shipped carts have been renamed and re-themed to fit the Pixygon universe: Snake is now Recycler, Breakout is The Veil, Meteor is Plate Fall, Tunnel is Down-Shaft, Pong is The Whale, Picross is The Signs, Rogue is Abaddon, and Farm is Seedplate. In-game text, win/lose messages, cover art, and crop names have been updated to match the new lore-driven names, though the underlying gameplay is unchanged.
- Mega Micromachee's tagline now reads "every pearl, a few seconds each" / "EVERY PEARL. NO TIME." to match the new cart naming.


## [0.15.0] — 2026-08-21

### Added
- install.sh can now install micromachee even without Rust/cargo installed: it will fetch a prebuilt helper binary and verify it against a checksum committed in this repository before installing it. If the checksum doesn't match, nothing is installed and you're told to install Rust instead.

### Changed
- Building from source with cargo remains the preferred install path and is used automatically whenever cargo is available; the prebuilt-binary download only happens as a fallback.
- README now explains the install security model in more detail, including how the prebuilt binary download is verified and how to avoid it entirely by installing Rust first.


## [0.14.0] — 2026-08-21

### Added
- README now documents how to fully remove Micromachee (helper, symlink, carts, saves, and settings) from your system.
- README now clearly explains what the plugin does on your machine — what it builds and runs, the sandboxing limits on cart Lua scripts, when it touches the network, how credentials are handled, and exactly which paths it writes to — plus a full list of dependencies and their licences.

### Changed
- The web build (web/index.html) no longer vendors a copy of wasmoon in the repository. Instead, run `npm install` inside `web/` once to fetch it before serving the folder — the console itself works exactly the same afterward. **(BREAKING)**

### Fixed
- Reinstalling no longer overwrites carts you've already installed or edited. The installer now skips any cart file that already exists at the destination and reports how many were added versus kept.


## [0.13.0] — 2026-08-21

### Added
- Added Mega Micromachee to the web console — a meta-game that cycles through every cart on the shelf for a few seconds each, with the pace and countdown ramping up round after round until you run out of lives.

### Fixed
- The web console's shared module now exports CHAR_WIDTH and LINE_HEIGHT alongside the existing constants, so other parts of the page can size and lay out text correctly.


## [0.12.0] — 2026-08-21

### Added
- Introduced Mega Micromachee, a meta-game that runs through every cart on the shelf a few seconds at a time. Survive each round to move on, but every fifth round the timer shortens and the games speed up, making later rounds a real scramble. You get three lives and the game tracks how many rounds you've survived.
- Carts can now call lose() and win() to report whether the player succeeded or failed at the moment it happens. This is what powers Mega Micromachee's pass/fail detection, and all bundled games (breakout, meteor, pong, rogue, snake, tunnel) have been updated to call lose() at their existing fail points.

### Changed
- The shelf and cart listing now always show Mega Micromachee as the first entry, alongside the regular carts.

### Improved
- Cover art generation and viewing (covers/cover commands) now support Mega Micromachee, rendering its own generated cover image.


## [0.11.0] — 2026-08-21

### Added
- Games can now save and load persistent state (numbers, strings and booleans) plus read the real wall-clock time with the new save(key,value), load(key) and now() cart API functions. This lets games have things happen "while you're away" — like crops that keep growing even after the console is closed.
- Added Farm, a new cart demonstrating save/load and real-time growth: plant crops, close the console, and come back later to find them ripe.
- The console shelf is now a grid of covers you can navigate entirely with the keyboard — arrows or WASD to move the selection, O/X to pick a cart — no mouse required.
- Screen size can now be adjusted directly from the console with +/- buttons, instead of only through a settings page, and your chosen size is remembered.
- Added a new `micromachee scale [2-6]` command-line option to view or set the console's screen size directly from the terminal.
- Web version: cart save data now persists per-cart in the browser via localStorage, so progress in games like Farm carries over between visits.

### Changed
- Closing the panel now pauses the running game instead of stopping it — reopening picks up right where you left off, rather than losing your run.

### Improved
- Switching themes while a game is running no longer restarts the cart or interrupts your play — the palette now updates live, and cover art updates to match the new theme too.

### Fixed
- Fixed screen flicker during gameplay caused by the display briefly going blank while each new frame decoded.
- Fixed mid() and flr() returning floating-point numbers (e.g. "2.0") when given whole numbers, which could corrupt save keys or on-screen text built from clamped coordinates.
- Fixed the Breakout cart not drawing its side walls, so the ball appeared to bounce off empty space at the screen edges.

### Removed
- Removed the separate "Screen size" setting from the plugin's settings page, since screen size is now controlled directly from buttons on the console itself. **(BREAKING)**


## [0.10.0] — 2026-08-21

### Added
- Micromachee now runs entirely in a browser: open web/index.html to browse the shelf and play every cart with a real Lua 5.4 engine, no server or build step needed.
- A verification tool (web/check.mjs) compares every pixel drawn by the browser player against the official console for all carts, guaranteeing the two renderers stay visually identical.

### Changed
- Published carts and catalogs now live at versioned URLs instead of a shared 'shelf' path, so each release's content is immutable and never overwritten by CDN caching issues. **(BREAKING)**
- The catalog now embeds each cart's full Lua source directly, so tools like the browser player and sync can fetch everything from one file instead of one request per cart.

### Improved
- The publish script now verifies uploaded files by comparing actual byte content rather than just HTTP status codes, catching stale CDN caches that would otherwise silently serve outdated carts.


## [0.9.0] — 2026-08-21

### Added
- You can now generate a whole new game from a sentence: use "+ MAKE A GAME" in the panel or `micromachee make "<name>" "<what it is>"` on the command line. Claude writes a cart, checks that it actually loads and survives play, and automatically fixes and re-checks it if it doesn't — what comes back is playable right away.
- New games start as drafts you can play immediately without publishing. Revise them with a follow-up instruction ("make it harder"), keep them to add them to your shelf, or discard them — all from the panel or via `micromachee revise/publish/discard`.
- Generating a game requires Anthropic credentials (an API key or an `ant auth login` profile); the panel now tells you clearly if none are configured instead of failing silently. Nothing you make leaves your machine unless you explicitly publish it with the separate sharing script.

### Improved
- The panel now shows a clear status message while a game is being generated or revised, and reports what went wrong if generation fails.

### Fixed
- Typing in a name, prompt, or revision text field no longer triggers panel keyboard shortcuts (like the theme-cycling "T" key) as you type.


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


