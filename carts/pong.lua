-- title: The Whale
-- author: pixygon
-- about: first to seven. it does not blink

-- The opponent is deliberately imperfect. It only starts tracking once the ball
-- is heading its way and it moves fractionally slower than you do, so it can be
-- beaten by angle rather than by reflex — which is the only thing that makes a
-- machine opponent worth playing at all.

local TOP    = 12         -- the score lives above this line
local PADH   = 20
local PADW   = 3
local LX     = 4
local RX     = 233
local TARGET = 7

local ly, ry, bx, by, vx, vy, sl, sr, serve, over

local function launch(toward)
  bx, by = 119, (TOP + 160) / 2
  vx = 1.3 * toward
  vy = (rnd(1) < 0.5 and -1 or 1) * (0.4 + rnd(0.7))
  serve = 40                       -- a beat before it moves, to find the ball
end

function _init()
  ly, ry = 76, 76
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

  -- the court is 160 tall now; both paddles scale by the same 1.25
  if btn(2) then ly = ly - 3.2 end
  if btn(3) then ly = ly + 3.2 end
  ly = mid(TOP, ly, 160 - PADH)

  -- The opponent: idles until the ball turns toward it, then closes on the
  -- ball's centre a little slower than a person can move.
  if vx > 0 then
    local aim = by - PADH / 2
    if aim < ry then ry = ry - 2.75 elseif aim > ry then ry = ry + 2.75 end
  end
  ry = mid(TOP, ry, 160 - PADH)

  if serve > 0 then
    serve = serve - 1
    return
  end

  bx = bx + vx
  by = by + vy

  if by < TOP + 1 then by, vy = TOP + 1, -vy sfx(0) end
  if by > 158     then by, vy = 158, -vy end

  -- Where the ball meets the paddle decides the angle it leaves at. Without
  -- this the rally never changes shape and the game has nothing in it.
  if vx < 0 and bx <= LX + PADW and bx > LX - 2 and by >= ly and by <= ly + PADH then
    bx = LX + PADW
    vx = -vx
    sfx(0)
    vy = mid(-3.0, vy + (by - (ly + PADH / 2)) / 7, 3.0)
    speed_up()
  end
  if vx > 0 and bx >= RX - 1 and bx < RX + PADW + 2 and by >= ry and by <= ry + PADH then
    bx = RX - 1
    vx = -vx
    sfx(0)
    vy = mid(-3.0, vy + (by - (ry + PADH / 2)) / 7, 3.0)
    speed_up()
  end

  if bx < -2 then
    sr = sr + 1
    sfx(5)
    lose()
    if sr >= TARGET then over = true else launch(1) end
  elseif bx > 242 then
    sl = sl + 1
    score(sl)
    sfx(6)
    if sl >= TARGET then over = true else launch(-1) end
  end
end

function _draw()
  cls(0)

  -- The dashed centre line, which is most of what makes a pong look like one.
  for y = TOP + 2, 158, 8 do
    rect(119, y, 2, 4, 1)
  end

  rect(LX, ly, PADW, PADH, 7)
  rect(RX, ry, PADW, PADH, 6)
  if serve <= 0 then rect(bx - 1, by - 1, 3, 3, 4) end

  rect(0, 0, 240, TOP, 0)
  line(0, TOP, 239, TOP, 1)
  print(sl, 108, 3, 7)
  print(sr, 128, 3, 6)

  if over then
    local won = sl >= TARGET
    rect(76, 68, 88, 24, 0)
    rectb(76, 68, 88, 24, won and 5 or 2)
    print(won and "IT YIELDS" or "IT HOLDS", won and 102 or 104, 74, 7)
    print("PRESS O", 106, 82, 3)
  elseif serve > 0 and sl == 0 and sr == 0 then
    print("UP AND DOWN", 98, 120, 1)
  end
end

function _cover()
  cls(0)
  for y = 4, 156, 10 do
    rect(119, y, 2, 6, 1)
  end

  rect(14, 40, 6, 38, 7)
  rect(220, 60, 6, 38, 6)
  rect(112, 64, 7, 7, 4)

  rect(0, 108, 240, 52, 0)
  print("THE WHALE", 48, 122, 7, 4)
end
