-- title: Pong
-- author: pixygon
-- about: first to seven, and the machine does not blink

-- The opponent is deliberately imperfect. It only starts tracking once the ball
-- is heading its way and it moves fractionally slower than you do, so it can be
-- beaten by angle rather than by reflex — which is the only thing that makes a
-- machine opponent worth playing at all.

local TOP    = 12         -- the score lives above this line
local PADH   = 20
local PADW   = 3
local LX     = 4
local RX     = 121
local TARGET = 7

local ly, ry, bx, by, vx, vy, sl, sr, serve, over

local function launch(toward)
  bx, by = 63, (TOP + 128) / 2
  vx = 1.3 * toward
  vy = (rnd(1) < 0.5 and -1 or 1) * (0.4 + rnd(0.7))
  serve = 40                       -- a beat before it moves, to find the ball
end

function _init()
  ly, ry = 58, 58
  sl, sr = 0, 0
  over   = false
  score(0)
  launch(rnd(1) < 0.5 and -1 or 1)
end

local function speed_up()
  local s = 1.06
  vx = mid(-3.4, vx * s, 3.4)
  vy = mid(-3.0, vy * s, 3.0)
end

function _update()
  if over then
    if btnp(4) then _init() end
    return
  end

  if btn(2) then ly = ly - 2.6 end
  if btn(3) then ly = ly + 2.6 end
  ly = mid(TOP, ly, 128 - PADH)

  -- The opponent: idles until the ball turns toward it, then closes on the
  -- ball's centre a little slower than a person can move.
  if vx > 0 then
    local aim = by - PADH / 2
    if aim < ry then ry = ry - 2.2 elseif aim > ry then ry = ry + 2.2 end
  end
  ry = mid(TOP, ry, 128 - PADH)

  if serve > 0 then
    serve = serve - 1
    return
  end

  bx = bx + vx
  by = by + vy

  if by < TOP + 1 then by, vy = TOP + 1, -vy end
  if by > 126     then by, vy = 126, -vy end

  -- Where the ball meets the paddle decides the angle it leaves at. Without
  -- this the rally never changes shape and the game has nothing in it.
  if vx < 0 and bx <= LX + PADW and bx > LX - 2 and by >= ly and by <= ly + PADH then
    bx = LX + PADW
    vx = -vx
    vy = mid(-3.0, vy + (by - (ly + PADH / 2)) / 7, 3.0)
    speed_up()
  end
  if vx > 0 and bx >= RX - 1 and bx < RX + PADW + 2 and by >= ry and by <= ry + PADH then
    bx = RX - 1
    vx = -vx
    vy = mid(-3.0, vy + (by - (ry + PADH / 2)) / 7, 3.0)
    speed_up()
  end

  if bx < -2 then
    sr = sr + 1
    if sr >= TARGET then over = true else launch(1) end
  elseif bx > 130 then
    sl = sl + 1
    score(sl)
    if sl >= TARGET then over = true else launch(-1) end
  end
end

function _draw()
  cls(0)

  -- The dashed centre line, which is most of what makes a pong look like one.
  for y = TOP + 2, 126, 8 do
    rect(63, y, 2, 4, 1)
  end

  rect(LX, ly, PADW, PADH, 7)
  rect(RX, ry, PADW, PADH, 6)
  if serve <= 0 then rect(bx - 1, by - 1, 3, 3, 4) end

  rect(0, 0, 128, TOP, 0)
  line(0, TOP, 127, TOP, 1)
  print(sl, 52, 3, 7)
  print(sr, 72, 3, 6)

  if over then
    local won = sl >= TARGET
    rect(20, 52, 88, 24, 0)
    rectb(20, 52, 88, 24, won and 5 or 2)
    print(won and "YOU WIN" or "YOU LOSE", won and 50 or 46, 58, 7)
    print("PRESS O", 50, 66, 3)
  elseif serve > 0 and sl == 0 and sr == 0 then
    print("UP AND DOWN", 42, 100, 1)
  end
end

function _cover()
  cls(0)
  for y = 4, 124, 10 do
    rect(63, y, 2, 6, 1)
  end

  rect(10, 34, 5, 30, 7)
  rect(113, 62, 5, 30, 6)
  rect(58, 52, 6, 6, 4)

  rect(0, 96, 128, 32, 0)
  print("PONG", 40, 102, 7, 3)
end
