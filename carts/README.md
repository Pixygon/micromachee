# The shelf

Seven carts, and between them they are the best documentation this console has.
Every one is a complete game in a single Lua file, and each was written to show
one thing clearly — so when you are about to write something and want to see how
it is done here, open the cart in the right-hand column rather than guessing.

The rules, the API and the traps are in [`../CLAUDE.md`](../CLAUDE.md).

| cart | the game | read it for | size |
|---|---|---|---|
| [`snake.lua`](snake.lua) | eat, grow, do not bite yourself | grid movement, and queuing a turn so two taps in one step cannot reverse you into your own neck | 11% |
| [`breakout.lua`](breakout.lua) | clear the wall, keep the ball alive | float positions rounded only at draw time, and resolving collision one axis at a time so the ball cannot burrow through a corner | 11% |
| [`meteor.lua`](meteor.lua) | fall forever, hit nothing | spawning, a difficulty ramp that adds rocks rather than speed, and drawing the HUD **last** on its own ground so nothing falls through the score | 11% |
| [`tunnel.lua`](tunnel.lua) | fly the cave, do not touch the walls | `pget` collision — the cave is stored as column heights, but the ship tests the *pixel* it is moving into rather than the numbers, so collision cannot disagree with what you can see | 9% |
| [`pong.lua`](pong.lua) | first to seven | an opponent worth playing: it idles until the ball turns toward it and moves fractionally slower than you, so it loses to angle rather than to reflex | 12% |
| [`picross.lua`](picross.lua) | fill the squares the numbers describe | dense layout on a small screen — clue gutters sized for the worst case (four clues per line), a cursor, and satisfied clues dimming as you go | 20% |
| [`rogue.lua`](rogue.lua) | down as far as you can get | generated levels, turn order (you move, then everything else does), a remembered map, and stats that carry between floors | 39% |

Sizes are of the 24K a cart may be. **The largest thing anyone has built for
this console uses 39% of the budget** — the limit has not been the constraint on
any game yet, and is not meant to be.

## Playing them here

```bash
micromachee tty rogue
```

No install, no bar, no compositor — the cart runs in the process and its
framebuffer is drawn to the terminal in half-blocks. Arrows or WASD, `z` and
`x`, `q` to quit.

## Publishing them

The shelf on the internet is generated, not hand-kept:

```bash
scripts/publish.sh
```

That regenerates `catalog.json` from these files, uploads both, and checks what
is actually being served. `micromachee sync` then pulls them onto any machine,
verifying each cart's SHA-256 on the way in.

## Adding one

```bash
B=./helper/target/release/omarchy-micromachee
$B new "My Game"                       # writes a cart that already plays
$B check carts/my-game.lua             # loads? survives a minute of mashing?
$B shot  carts/my-game.lua --frames 90 -o /tmp/look.png
```

Then **look at the PNG**. A clean `check` is necessary and not sufficient: every
visual bug in the seven above passed one and was caught by looking. See
[`../CLAUDE.md`](../CLAUDE.md) for how to drive a game `--hold` cannot reach —
turn-based and menu games need taps, not held buttons.

## One thing that is true of all seven

None of them names a colour. They ask for slot 0 through 7, dark to light, and
the active theme decides what that looks like — which is why all seven are
readable in Game Boy green, in amber and in greyscale without a line changing.
If you are copying from these, copy that too.
