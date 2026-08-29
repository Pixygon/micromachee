# micromachee

A 240×160, eight-colour fantasy console — GBA-shaped — that lives in an Omarchy bar widget.
One Lua file per game.

## How it is put together

```
manifest.json   what Omarchy reads
Panel.qml       the bar button and the panel — drawing only
Service.qml     runs the helper, turns its output into properties
helper/         Rust: everything that can actually fail
carts/          the games
themes/         palettes + the rules a palette must keep
```

**The split is the point.** QML cannot be unit-tested without a compositor, so
anything written there is only ever verified by looking at it. Anything in
`helper/` is reachable by `cargo test` on any machine. Logic goes in the helper;
the QML layer stays dumb enough to be obviously correct.

Two conventions the QML depends on:

- `status` prints **one line of JSON** and exits 0. It is polled on a timer, so
  it must be cheap and must never block.
- Every other command prints a **human sentence** to stderr and exits non-zero
  when it fails. The panel shows that last line verbatim — write it for the
  person reading the bar, not for a log.

```bash
cargo test  --manifest-path helper/Cargo.toml
./install.sh                      # after changing the helper
```

---

# Writing a cart

This is the part most sessions are here for. A cart is **one Lua file, at most
24K**. It needs `_draw()`. `_init()`, `_update()` and `_cover()` are optional.
30 frames a second.

```lua
-- title: Dodge
-- author: you
-- about: one line, optional

local x

function _init()  x = 120 end
function _update()
  if btn(0) then x = x - 2 end
  if btn(1) then x = x + 2 end
  x = mid(0, x, 239)
end
function _draw()
  cls(0)
  print("SCORE 0", 2, 2, 7)
  rect(x - 3, 150, 7, 4, 6)
end
```

The `-- title:` / `-- author:` / `-- about:` comments are optional metadata, not
a required header. There is no magic line. If you write valid Lua under 24K with
a `_draw`, it is a cart.

## The whole API

```
cls(c)  pset(x,y,c)  pget(x,y)
rect(x,y,w,h,c)  rectb(x,y,w,h,c)  line(x0,y0,x1,y1,c)
circ(x,y,r,c)  circb(x,y,r,c)  print(text,x,y,c,scale)
btn(i)  btnp(i)  t()  rnd(n)  flr(n)  mid(lo,v,hi)  score(n)
save(key,value)  load(key)  now()  lose()  win()
```

That is all of it. There is no sprite sheet and no sound. Lua's `math.*`,
`table.*` and `string.*` are available.

**A cart gets `math`, `string` and `table`, and nothing else.** `io`, `os`,
`package`, `require`, `dofile` and `loadfile` are all absent, so a cart cannot
open a file, run a program, or reach anything outside the console. This was not
always true: the first version loaded the whole standard library, and a test
cart wrote a file to `/tmp` to prove it. Since `sync` pulls carts off a CDN,
that was a hole rather than a footnote.

It is still not a security boundary in the strong sense — it is a Lua
interpreter in your process, and the per-frame instruction budget and memory
ceiling exist to stop a cart hanging your bar rather than to contain a
determined attacker. Treat a cart from a stranger the way you would any script
they sent you: read it first. It is one file and at most 24K, which is the
point.

- `btn(i)` is held, `btnp(i)` is newly pressed this frame.
  **0** left · **1** right · **2** up · **3** down · **4** O · **5** X
- `t()` is seconds since the cart started. `rnd(n)` is a float in `[0, n)`.
- `mid(lo, v, hi)` clamps — the usual way to keep a player on screen.
- `score(n)` is fire-and-forget. The console owns high scores per cart; a cart
  cannot read or lower them. Call it when the score changes.
- `pget(x,y)` reads the framebuffer back, so you can collide against what you
  drew last frame instead of keeping a parallel model. Very effective for cave,
  tunnel and maze games.
- **`lose()`** at the moment the player fails — the same line where you already
  set `alive = false`. It changes nothing in normal play, and it is the only
  thing that lets **Mega Micromachee** tell whether you survived your few
  seconds of your game. A cart that never calls it always survives its round.
  `win()` is the mirror, for a game that can be finished.
- `save(k,v)` / `load(k)` persist across runs — numbers, strings and booleans
  only. `now()` is wall-clock seconds since 1970, where `t()` is seconds since
  this run began. Together they make time pass while the console is closed:
  store *when* something started and compare, never a countdown, because
  nothing counts down while the widget is shut. `farm.lua` is the worked
  example.
- `flr` and `mid` both return an **integer** when given integers, so
  `"p" .. mid(0, x, 3)` is `"p2"` and not `"p2.0"`. That mattered the day a
  game started using a clamped coordinate as a save key.
- `print`'s fifth argument is an optional **scale**, defaulting to 1: every
  pixel of the glyph becomes a block that many wide. It is how you get a title
  worth looking at out of a 3x5 font. A scaled line is `#text * 4 * scale`
  pixels wide, so centring is `(240 - #text * 4 * scale) / 2`.

## Give it a cover

`_cover()` draws the picture the shelf shows, and the one that comes up full
size before the game starts. It runs once, after `_init()`, on the same 240x160
screen with the same eight colours:

```lua
function _cover()
  cls(0)
  print("SNAKE", 90, 130, 5, 3)   -- scale 3, so it reads at thumbnail size
end
```

That is the whole mechanism. **A cover is a thing the cart draws, not a file
beside it** — which is what keeps a game one Lua file, needs no asset pipeline,
and means covers follow the colour mode like everything else.

Without `_cover()` a cart still gets a cover: forty-five frames of itself being
played, which is honest but rarely flattering. Look at yours:

```bash
micromachee cover mygame.lua -o /tmp/cover.png
```

Design it for the **small** size first. On the shelf it is a thumbnail, and the
title is already written beside it in ordinary text — so a bold shape carries
further than clever detail, and a scale-3 title reads where a scale-1 one is
mush.

## Colours are indexes, never names

**A cart indexes colours. It never names them.** Themes repaint every game —
Game Boy green, amber CRT, greyscale — and a cart that assumes slot 2 is red
breaks under all of them. If a game draws blood it draws it in **2** because 2
is dark-mid, not because 2 is red.

What you can rely on is the **rank**, which every theme preserves:

| slot | role | default |
|---|---|---|
| 0 | ground — darkest, backgrounds | black |
| 1 | dim — separators, inactive | navy |
| 2 | alert | red |
| 6 | cool | blue |
| 3 | warm | orange |
| 5 | go | green |
| 4 | bright | yellow |
| 7 | light — text, the player | white |

Read top-to-bottom as dark to light. `cls(0)` then `print(..., 7)` is readable
in every theme, forever. See `themes/README.md`.

## Laying out 240×160

Text is **4 pixels per character, 6 pixels per line**, drawn from the top-left
of the first glyph. So a 60-character line exactly fills the screen, and
centring is `x = (240 - #text * 4) / 2`.

Lower case prints as upper — there is one case in the font. Characters the font
lacks are skipped silently, leaving a hole; `check` warns about it in a title.

Everything clips. Drawing off the edge is safe and normal — it will not panic
and will not wrap to the far side. Colours wrap: `c % 8`, so `9` is `1` and a
stray `-1` is `7`.

## Things that bite

- **A frame has an instruction budget** (about 5M). A `while true do end` ends
  the cart with "a frame ran forever", it does not lock the bar. Plenty for a
  real game; you will not meet it by accident.
- **Reserve the HUD area.** If things move through the top of the screen, draw a
  `rect(0,0,240,16,0)` behind the score *after* drawing them, or the one number
  the player wants is the one they cannot read.
- **Put game-over text in a box** (`rect` then `rectb`) rather than straight on
  the field, or it lands on top of whatever was moving.
- **Restart on a button, not a timer.** `if btnp(4) then _init() end` in
  `_update` when dead is the convention all the shipped carts use.

## Sharing a game

```bash
micromachee submit mygame.lua     # or a shelf id
```

One command sends a cart to the **public community shelf**. Verification is
automatic and takes ten-odd seconds: the API runs it sandboxed for 900 frames
of button-mashing (the same spirit as `check`), then two Claude reviewers read
it — one for safety and content, one for whether it is actually a game. Both
must accept; an accepted cart is live on the web shelf at pixygon.io/micromachee
within the minute, and a rejection always says why. The same upload exists on
the website ("SUBMIT A GAME" under the console). The pipeline lives in
PixygonAPI (`services/micromacheeVerifier.js`) and reads the same 24K limit —
if you change the console's limits, that mirror has to move too.

## The rules are also the generator's contract

`micromachee make "<name>" "<what it is>"` has Claude write a cart from
`helper/src/cart-rules.md` — a tighter restatement of this document, aimed at a
model rather than a person. It is embedded in the binary and covered by a test
that fails if the essentials go missing.

**If you change the API or the limits, change that file too.** The generator
depends on it being true, and a rule that is documented here but absent there
produces carts that fail validation for reasons nobody can see.

## Verify it, then look at it

```bash
B=./helper/target/release/omarchy-micromachee
$B check carts/yourgame.lua                          # loads? survives a minute?
$B shot  carts/yourgame.lua --frames 90 -o /tmp/x.png
```

`check` runs 1800 frames with pseudo-random button-mashing and reports size,
metadata and warnings. **A clean `check` is necessary and not sufficient** —
then open the PNG and *look at it*. Every visual bug in the shipped carts got
through a green `check` and was caught by looking: rocks falling through the
score, a game-over message landing on a moving object, `"SCORE " .. flr(n)`
rendering as `30.0`. Look at the death and start screens too, not just frame 90.

## Driving a game you cannot play

`shot` renders one frame with buttons held down. That is enough for anything
driven by `btn` — `breakout.lua`, `pong.lua`, `meteor.lua` all play themselves
under `--hold`. It is **useless for anything driven by `btnp`**: holding a button
fires `btnp` exactly once, so a menu never moves and a turn-based game never
takes its second turn. `picross.lua` and `rogue.lua` need *taps* — press,
release, press — which means alternating the held mask frame by frame.

To reach a state that is many correct moves away — a solved puzzle, depth four,
a death — do not make the cart's internals global and do not edit the cart.
**Copy it and append to the copy.** Appended code is in the same file, so the
cart's `local`s are still in lexical scope:

```lua
-- appended to a COPY of rogue.lua, for testing only
local real_update, n = _update, 0
function _update()
  n = n + 1
  if n == 4 then descend() end                    -- a local function, still visible
  if n == 40 then hp = 0; over = true end         -- a local variable, still visible
  real_update()
end
```

That reaches the game-over screen in forty frames instead of a lucky hour, and
the shipped cart never learns it was tested. Every end screen in `carts/` was
checked this way, and two were wrong the first time.

## The worked examples

The shipped carts in `carts/` each demonstrate one thing:

| cart | for |
|---|---|
| `snake.lua` | *Serpent* — grid movement, queued turns |
| `breakout.lua` | *The Veil* — float physics, per-axis collision |
| `meteor.lua` | *Plate Fall* — spawning, difficulty ramp, HUD layering |
| `tunnel.lua` | *Down-Shaft* — `pget` collision against the framebuffer |
| `pong.lua` | *The Whale* — an opponent worth playing, imperfect on purpose |
| `picross.lua` | *Signcarver* — dense layout, a cursor, clue gutters that fit |
| `rogue.lua` | *Abaddon* — generated levels, turn order, remembered map, stats |
| `farm.lua` | *Farm of Arra* — `save`/`load` and `now()`, real time while closed |

All seven draw their own `_cover()`, so they double as worked examples of that.
