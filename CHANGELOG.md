# Changelog

All notable changes to **micromachee**. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this file is
materialized from the Pixygon Changelog API — edit there, not here.

## [0.30.0] — 2026-08-25

### Added
- Dreadwager adds ammo and reloading: hold the fire button to empty your magazine (each shot gives a little recoil-shove), then it auto-reloads. New skills let you grow the magazine (DRUM), reload faster (CRANK), burn enemies on touch (THORN), heal on kills (LEECH), and absorb a hit with a recharging ward (GUARD).
- The web shelf now also shows large campaign carts that exceed the sync size limit and previously only appeared bundled with the desktop app, so the web catalog matches what you'd see on the plugin.

### Changed
- Dreadwager has been reworked into a bigger, roomier descent: Limbo now spans a scrolling world made of distinct biomes (grass, swamp, ash and bog) that affect your movement speed, bounded by a containment wall to the north and cliffs on the other sides. THE cliff still opens on its own schedule and drops you a layer deeper, but now you simply walk into it to descend instead of pressing a button.

### Improved
- The level-up screen now supports up/down/left/right for choosing a skill, and the HUD has been reorganized into two rows showing sparks, hearts, ammo, layer and level.
- Shelf cover thumbnails on both the desktop app and web now show a faithful, exact miniature of the whole cover image instead of a cropped, blurred approximation, so what you see on the shelf matches the actual cover art.


## [0.29.0] — 2026-08-25

### Added
- Each game on the shelf now has an info card (shown with the X button) listing its title, author, description, best score, and whether it plays in Mega.
- You can now switch the colour theme at any time by pressing 'T', in addition to the theme button, and it applies instantly whether you're browsing the shelf or playing a game.

### Changed
- The web shelf for choosing a game is now drawn right inside the console screen itself, navigated with the same six buttons you use to play — matching the desktop version pixel-for-pixel instead of using a separate HTML grid of covers.

### Improved
- The console stays on screen the whole time now: picking a game, viewing its info card, and playing all happen in one continuous view, with no page layout jump when you go back to the shelf.


## [0.28.1] — 2026-08-24

### Added
- Veilwalkers now has a full class, skill, and job system. Each hero's class grows a small skill tree as they level up (e.g. Whale grows Tide into Crash into Bulwark), and a new Jobs tab lets you assign a second job that adjusts stats and grants an extra skill. Status effects like burn, poison, stun, haste, and slow now factor into combat, with small icons showing what's affecting each combatant. _(a3766ca)_
- Carts can now be marked as paid rather than free, with pricing shown in the shelf, catalog, and store. Veilwalkers is the first paid cart, priced at $5. _(a3766ca)_

### Improved
- The web player is now properly playable on phones: pinch-zoom, double-tap zoom, rubber-banding, and long-press menus are disabled while playing, the layout and controls resize to fit touch screens, and the on-screen hint text adapts for touch devices. _(a3766ca)_


## [0.28.0] — 2026-08-24

### Fixed
- Fixed a crash that could occur when drawing circles with a center point far off-screen; coordinates are now safely clamped instead of causing an arithmetic overflow.


## [0.27.0] — 2026-08-22

### Changed
- Commands that take a cart id (`revise`, `publish`, `discard`, and cart lookup) now reject ids containing slashes, `..`, or other characters that aren't valid in a plain cart name, reporting them as "no draft called <id>" instead of touching the filesystem. **(BREAKING)**

### Fixed
- `micromachee catalog` now refuses to publish a cart whose filename wouldn't pass the same validity check `sync` applies to incoming carts, preventing you from accidentally shipping a catalog entry that well-behaved clients would reject.

### Security
- Cart ids from a catalog or the command line are now validated as plain filenames before being used on disk. This closes a path-traversal issue where a malicious or misconfigured catalog entry (e.g. an id like "../../pwned" or an absolute path) could have made `sync` write, read, or overwrite files outside the cart directory.
- Downloads made by `sync` (the catalog itself and any cart fetched by URL) are now capped at a hard byte limit while streaming, so a server that never stops sending data is refused instead of being buffered into memory indefinitely.


## [0.26.0] — 2026-08-22

### Added
- The console now has sound! Eight fixed effects — blip, hit, boom, pickup, jump, hurt, win, lose — play across every included cart, generated automatically on install so no audio files ship in the repo.
- A mute button on the console body turns sound off in one press (and the console remembers your choice). Games are built to work fine muted, too.
- The shelf now automatically checks for cart updates whenever the panel opens, and shows an amber count when updates are available. A new sync button lets you fetch and apply new/updated carts on demand, keeping old versions as backups.

### Improved
- Several built-in games (Breakout, Firekeeper, Sparrow, Pixiel, Dreadwager, and more) now have screen shake and particle bursts on hits, kills, and deaths, giving impacts a lot more visual punch.

### Fixed
- Dreadwager's on-screen cliff distance counter no longer runs off the edge of the screen or overlaps the life indicators.

### Removed
- The hidden secret button sequence on the shelf (previously an Easter egg for the Ydrast text mode) has been removed since it could no longer reliably trigger. The Ydrast tongue is now toggled via a small, unlabelled dot button in the panel instead. **(BREAKING)**


## [0.25.0] — 2026-08-22

### Added
- The console shelf now plays a brief animated title sequence when you first open the panel (skippable with any button press), instead of showing a static header.
- A "Make a game" tile now lives at the end of the shelf itself, so starting a new game is just another selection on the console rather than a separate button below it.
- The colour mode switcher has moved onto the console face as a compact palette swatch next to the controls, so you can cycle themes without leaving the play view.
- Breakout now features an evolving, endless wall: each level generates a new pattern with drifting and descending bricks, keeping the challenge fresh well beyond the original fixed set of levels.
- Breakout adds falling power-up capsules — widen or narrow your paddle, split your ball into three, or gain a piercing shot — picked up by catching them with the paddle.
- Sparrow now gives you a grace period after taking a hit instead of dying instantly: as long as you have upgraded your gun, a hit costs you a power level rather than the run.
- Sparrow's bird visually evolves as you power up, and reaching the top gun level adds two wingmen that fly alongside you and fire together.

### Changed
- The on-screen control hint text under the console has been removed as part of streamlining the shelf layout.

### Improved
- Cover art thumbnails on the shelf are now generated using a smarter downsampling method that preserves small details and shapes instead of picking a single, often unrepresentative pixel, making game tiles look noticeably clearer.
- The console UI (buttons, text, d-pad, and controls) now scales proportionally with the window size, so resizing keeps everything looking consistent instead of stretching just the screen area.
- Breakout's scoring, life, and game-over screens have been reworked to reflect the new endless-level structure, including a visible level counter.
- Sparrow's max shots and gun levels have been increased, giving more room for sustained fire at higher power.


## [0.24.0] — 2026-08-21

### Added
- `sync` now detects when a cart already on your shelf has changed from the published version and tells you which ones differ, instead of silently treating them as up to date.
- New `sync --update` flag lets you pull the latest version of a changed cart. Your existing copy is preserved as a `.lua.bak` file rather than being overwritten, so any local edits are never lost.

### Changed
- The `sync` summary line now reports how many carts were updated, alongside the counts of new, already-here, and failed carts.


## [0.23.0] — 2026-08-21

### Added
- New cart: Dreadwager — drift into an endless horde of enemies or take control of your own ending by leaping into a cliff once you've gathered enough sparks. Two distinct endings, dash-based movement, and an upgradeable multi-gun system based on how many sparks you collect.
- New cart: The Tower — a raycasted first-person dungeon climb across 9 procedurally built floors. Fight off horrors with a simple shooter, find the way up each floor, and rack up a score from kills, floors cleared, and a bonus for reaching the top.


## [0.22.0] — 2026-08-21

### Added
- The `shot` command now supports a `--keys` option to script a frame-by-frame button track (e.g. `--keys 10:2,11:0,20:16,21:0`). This lets you simulate a tap rather than a held button, which is essential for capturing screenshots of games that read input with `btnp()` — previously `--hold` could only ever show frame 1 of such games since a held button never re-fires.

### Fixed
- Invalid `--keys` values now produce a clear error message explaining the expected `frame:mask` format instead of failing silently or confusingly.


## [0.21.0] — 2026-08-21

### Added
- The `shot` command now supports a `--keys` option to script a frame-by-frame button track (e.g. `--keys 10:2,11:0,20:16,21:0`). This lets you simulate a tap rather than a held button, which is essential for capturing screenshots of games that read input with `btnp()` — previously `--hold` could only ever show frame 1 of such games since a held button never re-fires.

### Fixed
- Invalid `--keys` values now produce a clear error message explaining the expected `frame:mask` format instead of failing silently or confusingly.


## [0.20.1] — 2026-08-21

### Added
- New cart: Firekeeper — hold the line as a descending rank of invaders closes in, using bunkers for cover before they reach and snuff out your light.
- New cart: Sparrow — fly through waves of enemy formations, clearing each wing cleanly to earn gifts that upgrade your gun.
- New cart: The Twins — a tic-tac-toe game against an opponent who plays smart but occasionally blunders, keeping matches winnable.


## [0.20.0] — 2026-08-21

### Improved
- The installer now automatically links the plugin into Omarchy's plugins directory instead of just printing a command to run yourself. It's safe to re-run and won't touch an existing link or file that points somewhere else — you'll get a clear warning instead.


## [0.19.0] — 2026-08-21

### Added
- Press X on a highlighted cart to see more about it — full title, author, description, best score, and whether it's fast enough to appear in Mega Micromachee — before deciding to play.
- Cart authors can now add `-- mega: no` to opt a game out of Mega Micromachee, for games (like nonograms or slow-paced sims) that don't work well as a quick few-second round. This applies consistently across the desktop app and the web player.
- Added a small 'by Pixygon' credit to the panel and the web player.

### Changed
- The game shelf is now drawn by the console itself, in the same 128x128 screen and with the same six buttons a game uses — no more mouse-driven grid outside the screen. Browse covers, see best scores and details, and launch a game entirely from the keyboard. **(BREAKING)**
- The cart 'about' description is now capped at 48 characters, so write a short one-liner.

### Improved
- Pixiel has been reworked into a proper platformer: acceleration-based movement, coyote time and jump buffering, ledges and floating platforms, coins, patrolling enemies you can stomp, and an endless generated pit instead of a simple side-scrolling runner.

### Fixed
- Opening the panel now correctly resumes the shelf or game you left, and closing it pauses activity instead of letting it run unattended in the background.


## [0.18.0] — 2026-08-21

### Added
- On a game's cover screen, press O (or Z/Space) to bring up an info card showing the game's title, description, and best score before you commit to playing. Press O again or click to dismiss it.

### Changed
- The shelf screen now shows just each game's title under its thumbnail; the longer description moved into the new pre-game info card instead of being truncated on the shelf.
- Updated on-screen and web hints to mention the new O button action (e.g. "X STARTS · O TELLS YOU MORE · ESC BACK").
- The web page header now links to Pixygon instead of showing the old technical tagline.


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


