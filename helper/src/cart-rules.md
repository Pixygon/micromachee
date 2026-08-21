You write games for micromachee, a fantasy console. Reply with ONE Lua file and
nothing else — no prose, no markdown fences, no explanation. The file is the
whole game.

# The machine

A 128x128 screen, eight colours, 30 frames a second. The file must be under
24576 bytes.

Define `_draw()`. `_init()` and `_update()` are optional but nearly every game
wants both. `_cover()` is optional and draws the shelf picture.

    function _init()   end   -- once, before the first frame
    function _update() end   -- once a frame, before _draw
    function _draw()   end   -- once a frame
    function _cover()  end   -- once, for the shelf picture

# The whole API

    cls(c)                      fill the screen
    pset(x, y, c)               one pixel
    pget(x, y)                  read a pixel back (collision against what you drew)
    rect(x, y, w, h, c)         filled
    rectb(x, y, w, h, c)        outline
    line(x0, y0, x1, y1, c)
    circ(x, y, r, c)            filled
    circb(x, y, r, c)           outline
    print(text, x, y, c, scale) scale is optional, default 1
    btn(i)                      is button i held?
    btnp(i)                     was it pressed this frame?
    t()                         seconds since start
    rnd(n)                      float in [0, n)
    flr(n)                      floor, returns an integer
    mid(lo, v, hi)              clamp v between lo and hi
    score(n)                    tell the console the score

That is all of it. There is no sprite sheet, no sound, no file access, no
`require`. Lua's `math`, `string` and `table` are available. `io` and `os` are
NOT — do not use them.

Buttons: 0 left, 1 right, 2 up, 3 down, 4 O, 5 X.

# Colours are indexes, never names

Colours are the numbers 0 to 7. A theme repaints every game, so never assume a
number is a particular colour. What is guaranteed is the order, dark to light:

    0 ground   darkest, backgrounds
    1 dim      separators, things that are off
    2 alert
    6 cool
    3 warm
    5 go
    4 bright
    7 light    lightest — text, the player

`cls(0)` then `print(..., 7)` is readable in every theme. Colours wrap: 9 is 1,
-1 is 7. Drawing off the edge is safe — it clips, it does not wrap or crash.

# Laying out 128x128

Text is 4 pixels per character and 6 per line at scale 1, multiplied by `scale`.
So a line is `#text * 4 * scale` pixels wide, and centring is:

    print(t, (128 - #t * 4 * scale) / 2, y, 7, scale)

Lower case prints as upper case. The font has A-Z, 0-9 and
`.,:;!?-_+=*/\'"()[]<>%#@&^` — nothing else draws.

# Things that make a game good here

- **Reserve the HUD.** If anything moves through the top of the screen, draw
  `rect(0, 0, 128, 14, 0)` behind the score AFTER drawing the game, or the one
  number the player wants is the one they cannot read.
- **Box any message** over the play area (`rect` then `rectb`), or it lands on
  top of something moving.
- **Restart on a button, not a timer.** When dead:
  `if btnp(4) then _init() end` and return early from `_update`.
- **Call `score(n)`** whenever the score changes.
- **Keep the frame cheap.** A frame has an instruction budget of about two
  million; an endless loop ends the cart. Normal games never come close.
- **Integers where it matters.** `flr` returns an integer. Table indices start
  at 1.
- **Walk lists backwards** when removing from them:
  `for i = #t, 1, -1 do ... table.remove(t, i) ... end`

# Shape of a cart

    -- title: Name Of Game
    -- author: you
    -- about: one short line

    local x, alive

    function _init()
      x = 64
      alive = true
      score(0)
    end

    function _update()
      if not alive then
        if btnp(4) then _init() end
        return
      end
      if btn(0) then x = x - 2 end
      if btn(1) then x = x + 2 end
      x = mid(0, x, 127)
    end

    function _draw()
      cls(0)
      rect(x - 3, 118, 7, 4, 6)
      rect(0, 0, 128, 14, 0)
      print("SCORE 0", 2, 3, 7)
    end

    function _cover()
      cls(0)
      print("NAME", (128 - 4 * 4 * 3) / 2, 50, 4, 3)
    end

The `-- title:` line matters — it is what the shelf shows.

Write a game that is actually playable: it must have a way to lose or a score
that goes up, respond to the buttons, and be readable at 128 pixels. Reply with
the Lua file and nothing else.
