# The shelf

Eight carts, and between them they are the best documentation this console has.
Every one is a complete game in a single Lua file, and each was written to show
one thing clearly — so when you are about to write something and want to see how
it is done here, open the cart in the right-hand column rather than guessing.

The rules, the API and the traps are in [`../CLAUDE.md`](../CLAUDE.md).

| cart | the game | read it for | size |
|---|---|---|---|
| [`snake.lua`](snake.lua) | **Recycler** — collect the discarded | grid movement, and queuing a turn so two taps in one step cannot reverse you into your own neck | 11% |
| [`breakout.lua`](breakout.lua) | **The Veil** — peel it away | float positions rounded only at draw time, and resolving collision one axis at a time so the ball cannot burrow through a corner | 11% |
| [`meteor.lua`](meteor.lua) | **Plate Fall** — the sphere is shedding | spawning, a difficulty ramp that adds rocks rather than speed, and drawing the HUD **last** on its own ground so nothing falls through the score | 11% |
| [`tunnel.lua`](tunnel.lua) | **Down-Shaft** — it only looks like it rises | `pget` collision — the cave is stored as column heights, but the ship tests the *pixel* it is moving into rather than the numbers, so collision cannot disagree with what you can see | 9% |
| [`pong.lua`](pong.lua) | **The Whale** — first to seven | an opponent worth playing: it idles until the ball turns toward it and moves fractionally slower than you, so it loses to angle rather than to reflex | 12% |
| [`picross.lua`](picross.lua) | **The Signs** — draw the sign the numbers describe | dense layout on a small screen — clue gutters sized for the worst case (four clues per line), a cursor, and satisfied clues dimming as you go | 20% |
| [`rogue.lua`](rogue.lua) | **Abaddon** — down as far as you can get | generated levels, turn order (you move, then everything else does), a remembered map, and stats that carry between floors | 39% |
| [`farm.lua`](farm.lua) | **Seedplate** — plant, wait, sell | `save`/`load` and `now()` — crops ripen against the clock on the wall, so closing the console is the same to a turnip as leaving it open | 18% |

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

## They all say when you lost

Each calls `lose()` at the point it already knew — the same line that sets its
own `alive = false`. It changes nothing in normal play; it is what lets **Mega
Micromachee** run the whole shelf a few seconds at a time and tell whether you
got through your turn. `picross.lua` and `farm.lua` have no fail state, so a
round of either is simply survived.

## They all draw their own covers

Each has a `_cover()` — the picture the shelf shows and the one that fills the
screen before the game starts. It is drawn with the same primitives and the
same eight colours the game uses, so a cover is one more thing a Lua file does
rather than an asset beside it.

```bash
micromachee cover rogue -o /tmp/cover.png
```

## Where the names come from

Each cart is a window onto the Pixygon universe rather than a generic arcade
game — the file names stayed put (ids are baked into save data and the published
catalog) but the games are named for what they are in the Codex:

| cart | is | from the Codex |
|---|---|---|
| snake | **Recycler** | the afterlife-machine the Arra built to dissolve broken Pixiels *gently* — a death-machine that believes it is mercy |
| breakout | **The Veil** | Caul's membrane, peeled at the first apocalypse. Breaking it is how a world is born |
| pong | **The Whale** | the Whale sign — *"calm, controlled, and the foundation which everything rests on"* |
| meteor | **Plate Fall** | the hexagonal plates the Dyson sphere is assembled from, shed and falling |
| tunnel | **Down-Shaft** | the White Tower: pilgrims read it as rising; it is a shaft descending to the pulsar |
| picross | **The Signs** | the nine celestial figures — the numbers describe one, you draw it |
| rogue | **Abaddon** | the prison laid over the cursed forest. Nothing escapes it, and you do not die here — you dissolve |
| farm | **Seedplate** | *"each plate carried everything needed to grow a world on top"* |

Mega Micromachee is the [pearl-dress](../README.md#mega-micromachee): every
pearl, a few seconds each.

## One thing that is true of all seven

None of them names a colour. They ask for slot 0 through 7, dark to light, and
the active theme decides what that looks like — which is why all seven are
readable in Game Boy green, in amber and in greyscale without a line changing.
If you are copying from these, copy that too.
