# Micromachee

**A tiny 8-bit console that lives in your bar.** 128×128, eight colours, thirty
frames a second, and one Lua file per game.

Click the `▦` in your Omarchy bar, pick a cart off the shelf, play it with the
arrow keys, press escape, go back to work.

## The whole machine

| | |
|---|---|
| Screen | 128 × 128 |
| Colours | 8 — black, navy, red, orange, yellow, green, blue, white |
| Buttons | left, right, up, down, O (`z`), X (`x`) |
| Speed | 30 fps |
| A game | **one Lua file, 24 KB maximum** |

That is the entire specification. There is no sprite editor, no map, no sound
chip, no cartridge container — a game draws with rectangles, lines, circles,
pixels and text, and that turns out to be plenty.

## Writing a game

```bash
micromachee new "My Game"        # a starting cart that already plays
micromachee check mygame.lua     # does it hold up for a minute of play?
micromachee shot  mygame.lua --frames 90 --hold 2 -o look.png
```

A cart looks like this, and this is the complete API:

```lua
-- title: My Game
-- author: you
-- about: one line about it

function _init()   end     -- once, at the start   (optional)
function _update() end     -- 30 times a second    (optional)
function _draw()   end     -- 30 times a second    (required)
```

```
cls(c)                    fill the screen
pset(x,y,c)  pget(x,y)    one pixel, written or read back
rect(x,y,w,h,c)  rectb(…) filled box, outlined box
line(x0,y0,x1,y1,c)
circ(x,y,r,c)    circb(…) filled circle, outlined circle
print(text,x,y,c)         3×5 font, 32 characters to a line
btn(i)   btnp(i)          held / pressed just now
t()                       seconds since the cart started
rnd(n)  flr(n)  mid(lo,v,hi)
score(n)                  tell the console your score
```

Lua's own `math.*`, `table.*` and `string.*` are all there too. Colours are
`0`–`7`, buttons `0`–`5`, and everything clips at the screen edge so drawing
off-screen is safe and free.

**Only three rules**: fit in 24 KB, parse as Lua, define `_draw`. Metadata is
optional comments. There is no magic header to forget on your first attempt.

Two things that are not obvious and save a lot of code:

- `pget` reads the framebuffer back, so you can do collision against what you
  drew last frame instead of keeping a parallel model of the world. `tunnel` is
  a cave flyer in sixty lines because of it.
- `score(n)` is fire-and-forget. The **console** keeps the records, per cart. A
  game cannot read, lower, or forge another game's high score.

### It is built for agents to write

`check` and `shot` exist so that writing a game needs no bar, no compositor and
nobody watching. `check` loads the cart and plays it blind for 1,800 frames —
a full minute — mashing buttons, and reports the first frame that errors.
`shot` renders a frame to a PNG you can actually look at, with `--hold` so you
can photograph a game mid-play rather than only its title card.

That is the whole loop: write, check, look, fix. Three of the four carts here
were written by an agent working exactly that way.

## Playing without installing

The bar widget is one front end. `play` is a protocol — one base64 PNG per line
on stdout, a button bitmask on stdin — so anything can be the screen:

```bash
micromachee list         # what is on the shelf
micromachee tty rogue    # play it, right here
```

`tty` runs the cart in this process and draws its framebuffer straight to the
terminal — no PNG, no base64, no second process. Pixels become half-blocks, two
to a character cell, so 128x128 lands in 128x64 of terminal. Give it a window at
least 128x68 for one cell per pixel; it will halve the resolution to fit a
smaller one and say so. Arrows or WASD, `z` and `x`, `q` to quit.

Raw mode and the window size come from `stty`, so this pulls in no crate — the
same reasoning that made the PNG encoder hand-written.

A terminal cannot report a key being *released*, so a press is held briefly and
then let go on a timer — `btnp` games are exact, and `btn` games feel right
because key-repeat keeps renewing the press.

## Installing

```bash
./install.sh
ln -s "$PWD" ~/.config/omarchy/plugins/io.pixygon.micromachee
```

Then add the **Micromachee** widget to your bar. `install.sh` needs no root.

Carts live in `~/.local/share/omarchy-micromachee/carts/`. Installing a game is
copying a `.lua` file there — there is no install step, no index to rebuild, no
registry to tell. `micromachee sync` pulls carts from a catalog on the internet,
but that is only one way for a file to travel, not how carts work.

## What is in the box

| cart | |
|---|---|
| `snake` | eat, grow, do not bite yourself |
| `breakout` | the wall, the ball, the bat |
| `meteor` | fly, shoot, do not get hit |
| `tunnel` | fly the cave; collision is done by reading the screen |

## How it is built

```
manifest.json     what Omarchy reads
Panel.qml         the bar button, the shelf, the screen — drawing only
Service.qml       runs the helper; frames in, button bits out
helper/           the console itself, in Rust
  console.rs      framebuffer, palette, 3×5 font, every drawing primitive
  png.rs          a PNG encoder in ninety lines and no dependencies
  vm.rs           Lua, and the limits a stranger's code runs under
  cart.rs         the format, which is "a Lua file"
  shelf.rs        where carts live and how they arrive
```

The bar runs `micromachee play <id>` as a long-lived process. It prints one
base64 PNG per line and reads a button bitmask on stdin — so the game loop is
ordinary Rust that can be driven from a shell script, and the QML layer stays
thin enough to be obviously correct.

Frames are indexed PNGs at bit depth 4, which puts a full 128×128 frame in
about 8 KB, and the deflate stream is uncompressed — a compressor would be more
code than the encoder it lives in, to save a few percent on a local pipe.

### What a cart can and cannot do

A cart gets `math`, `string` and `table`. `io`, `os`, `package`, `require`,
`dofile` and `loadfile` are not loaded, so a cart cannot open a file or run a
program — the first version did load them, and a test cart wrote to `/tmp` to
prove the point. There is also an instruction budget per frame, so an endless
loop ends the cart rather than freezing your bar, and a memory ceiling.

It is still a Lua interpreter in your process rather than a real sandbox.
**Treat a cart like any other script you were sent** — read it before you run
it. It is one file and it is meant to be read.

## License

MIT.
