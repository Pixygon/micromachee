-- title: The Veil
-- author: pixygon
-- about: peel it away. that is how a world is born

-- Ball position is kept in floats and only rounded when it is drawn, so it
-- moves at speeds that are not whole pixels. Collision is resolved one axis at
-- a time: that is what stops the ball burrowing into a brick corner and coming
-- out the far side.
--
-- The wall is not a fixed grid any more. Each layer of the veil has a SHAPE, a
-- DRIFT and a DESCENT, and the three are read off the level number rather than
-- stored, so there is no table of levels to run out of — layer forty is as
-- well-defined as layer one and neither of them is written down.
--
-- Everything the wall does happens in ONE PLACE: `ox` and `oy` offset the whole
-- grid, and both the drawing and the collision go through the same two numbers.
-- A moving wall that moves only in the drawing is a wall the ball passes
-- through, and it is the first thing that goes wrong when you add motion to a
-- game that never had any.

local COLS, ROWS   = 8, 5
local BW, BH       = 14, 6
local LEFT, TOP    = 8, 16
local PADY         = 118
local WALL_COLOUR  = { 2, 3, 4, 5, 6 }

local NARROW, NORMAL, WIDE = 14, 22, 34
local DROP_CHANCE  = 0.14
local POWER_FRAMES = 420

local bricks, left, padx, padw, balls, points, lives, level, stuck
local ox, oy, drift, descent, shape, t
local drops, wide, pierce, bits, shake, stop

-- ── the shape of a layer ────────────────────────────────────────────────────

-- Five shapes, chosen by the level and nothing else. `r` and `c` are one-based.
local function filled(kind, r, c)
  if kind == 1 then
    return true                                   -- the whole veil
  elseif kind == 2 then
    return (r + c) % 2 == 0                       -- woven
  elseif kind == 3 then
    return c > r - 1 and c < COLS - r + 2         -- a peak
  elseif kind == 4 then
    return c % 3 ~= 0                             -- pillars
  else
    return r == 1 or r == ROWS or c == 1 or c == COLS   -- a frame
  end
end

local function build_layer()
  shape = (level - 1) % 5 + 1
  -- Drift starts at the second layer and grows, capped so the wall never moves
  -- faster than a ball can be aimed at it.
  -- Capped, and the cap is not arbitrary: the outer column sits 13 pixels from
  -- the wall, so a drift wider than that would swing bricks past where the ball
  -- can follow and leave a layer that cannot be cleared.
  drift = mid(0, (level - 1) * 0.35, 2.4)
  descent = level >= 3 and 0.006 + level * 0.0015 or 0
  ox, oy, t = 0, 0, 0

  bricks, left = {}, 0
  for r = 1, ROWS do
    bricks[r] = {}
    for c = 1, COLS do
      local on = filled(shape, r, c)
      bricks[r][c] = on
      if on then left = left + 1 end
    end
  end
end

-- A brick that blinks out is a brick that was never hit. Six pixels in its own
-- colour, thrown outward, and the eye reads the impact instead of the absence.
local function burst(x, y, n, c)
  for _ = 1, n do
    bits[#bits + 1] = {
      x = x, y = y,
      dx = rnd(2.6) - 1.3, dy = rnd(2.2) - 1.4,
      life = 8 + flr(rnd(8)), c = c,
    }
  end
end

-- ── balls ───────────────────────────────────────────────────────────────────

local function new_ball(x, y, vx, vy)
  balls[#balls + 1] = { x = x, y = y, vx = vx, vy = vy }
end

local function reset_ball()
  balls = {}
  new_ball(padx + padw / 2, PADY - 3, 1.1, -1.4)
  stuck = true
end

function _init()
  level  = 1
  padw   = NORMAL
  padx   = 64 - padw / 2
  points = 0
  lives  = 3
  drops, wide, pierce = {}, 0, 0
  bits, shake, stop = {}, 0, 0
  build_layer()
  score(0)
  reset_ball()
end

-- ── the wall, wherever it currently is ──────────────────────────────────────

local function brick_at(x, y)
  local c = flr((x - LEFT - ox) / BW) + 1
  local r = flr((y - TOP - oy) / BH) + 1
  if r >= 1 and r <= ROWS and c >= 1 and c <= COLS and bricks[r][c] then
    return r, c
  end
end

local function drop_power(x, y)
  -- Four kinds, and one of them is a hazard: a capsule you always want is not
  -- a decision, it is a coin.
  local kind = flr(rnd(4)) + 1
  drops[#drops + 1] = { x = x, y = y, kind = kind }
end

local function hit(x, y)
  local r, c = brick_at(x, y)
  if not r then return false end
  bricks[r][c] = false
  left = left - 1
  burst(LEFT + ox + (c - 1) * BW + BW / 2, TOP + oy + (r - 1) * BH + BH / 2, 5, WALL_COLOUR[r])
  shake = 2
  sfx(1)
  points = points + (ROWS - r + 1) * 10 + (level - 1) * 5
  score(points)
  if rnd(1) < DROP_CHANCE then
    drop_power(LEFT + ox + (c - 1) * BW + BW / 2, TOP + oy + (r - 1) * BH)
  end
  return true
end

local function set_paddle(w)
  local mid_x = padx + padw / 2
  padw = w
  padx = mid(0, mid_x - w / 2, 128 - w)
end

local function take(kind)
  if kind == 1 then
    set_paddle(WIDE)
    wide = POWER_FRAMES
  elseif kind == 2 then
    set_paddle(NARROW)
    wide = POWER_FRAMES
  elseif kind == 3 then
    -- Two more, thrown off the ball that is furthest along. Copying the
    -- velocity and turning it is enough to make three balls that diverge.
    local b = balls[1]
    if b then
      new_ball(b.x, b.y, b.vy * 0.9, b.vx * 0.9)
      new_ball(b.x, b.y, -b.vy * 0.9, -b.vx * 0.9)
    end
  else
    pierce = POWER_FRAMES / 2
  end
end

-- ── one frame ───────────────────────────────────────────────────────────────

local function step_ball(b)
  b.x = b.x + b.vx
  if b.x < 1 then b.x, b.vx = 1, -b.vx end
  if b.x > 126 then b.x, b.vx = 126, -b.vx end
  if hit(b.x, b.y) and pierce <= 0 then b.vx = -b.vx end

  b.y = b.y + b.vy
  if b.y < 10 then b.y, b.vy = 10, -b.vy end
  if hit(b.x, b.y) and pierce <= 0 then b.vy = -b.vy end

  -- The paddle steers: where the ball lands on it decides how far it comes off
  -- sideways, which is the whole game.
  if b.vy > 0 and b.y >= PADY - 1 and b.y <= PADY + 2
    and b.x >= padx and b.x <= padx + padw then
    b.y = PADY - 1
    b.vy = -b.vy
    b.vx = mid(-2.2, (b.x - (padx + padw / 2)) / 5, 2.2)
    sfx(0)
  end
end

function _update()
  if lives <= 0 then
    if btnp(4) then _init() end
    return
  end
  t = t + 1
  if shake > 0 then shake = shake - 1 end
  for i = #bits, 1, -1 do
    local b = bits[i]
    b.x, b.y, b.life = b.x + b.dx, b.y + b.dy, b.life - 1
    b.dy = b.dy + 0.09
    if b.life <= 0 then table.remove(bits, i) end
  end
  -- A beat of nothing after losing a ball. It is four frames and it is the
  -- difference between the ball vanishing and the ball being lost.
  if stop > 0 then stop = stop - 1 return end

  if btn(0) then padx = padx - 3 end
  if btn(1) then padx = padx + 3 end
  padx = mid(0, padx, 128 - padw)

  if wide > 0 then
    wide = wide - 1
    if wide == 0 then set_paddle(NORMAL) end
  end
  if pierce > 0 then pierce = pierce - 1 end

  -- The whole layer, drifting and settling. `oy` stops before the wall could
  -- reach the paddle, so descent is pressure rather than a second way to lose.
  ox = math.sin(t * 0.013) * drift * 5
  oy = mid(0, oy + descent, 26)

  if stuck then
    balls[1].x = padx + padw / 2
    balls[1].y = PADY - 3
    if btnp(4) then stuck = false end
    return
  end

  for i = #balls, 1, -1 do
    local b = balls[i]
    step_ball(b)
    if b.y > 127 then table.remove(balls, i) end
  end

  -- Falling capsules
  for i = #drops, 1, -1 do
    local d = drops[i]
    d.y = d.y + 1.1
    if d.y > 127 then
      table.remove(drops, i)
    elseif d.y >= PADY - 2 and d.y <= PADY + 4 and d.x >= padx - 2 and d.x <= padx + padw + 2 then
      take(d.kind)
      -- The bad one has to sound bad, or a hazard you cannot hear is a hazard
      -- you learn about by losing.
      sfx(d.kind == 2 and 5 or 3)
      table.remove(drops, i)
    end
  end

  if #balls == 0 then
    lives = lives - 1
    shake, stop = 10, 6
    sfx(5)
    lose()
    drops = {}
    if pierce > 0 then pierce = 0 end
    if wide > 0 then wide = 0 set_paddle(NORMAL) end
    if lives > 0 then reset_ball() end
  end

  if left == 0 then
    -- A layer peeled is not the end of it. There is always another underneath.
    sfx(6)
    level = level + 1
    points = points + 100
    score(points)
    build_layer()
    drops = {}
    set_paddle(NORMAL)
    wide, pierce = 0, 0
    reset_ball()
  end
end

-- ── how it looks ────────────────────────────────────────────────────────────

local CAPSULE = { 5, 2, 4, 6 }
local CAPLABEL = { "W", "N", "M", "P" }

function _draw()
  cls(0)
  local sx = shake > 0 and (flr(rnd(3)) - 1) or 0
  local sy = shake > 0 and (flr(rnd(3)) - 1) or 0

  -- The walls the ball bounces off. They were always there in the physics and
  -- never drawn, so the ball turned around in mid-air at the edge of nothing.
  rect(0, 9, 1, 119, 1)
  rect(127, 9, 1, 119, 1)

  for r = 1, ROWS do
    for c = 1, COLS do
      if bricks[r][c] then
        rect(flr(LEFT + ox + (c - 1) * BW) + sx, flr(TOP + oy + (r - 1) * BH) + sy,
             BW - 1, BH - 1, WALL_COLOUR[r])
      end
    end
  end

  for i = 1, #drops do
    local d = drops[i]
    rect(flr(d.x) - 3, flr(d.y), 7, 5, CAPSULE[d.kind])
    print(CAPLABEL[d.kind], flr(d.x) - 1, flr(d.y), 0)
  end

  for i = 1, #bits do
    local b = bits[i]
    pset(flr(b.x) + sx, flr(b.y) + sy, b.life > 5 and 7 or b.c)
  end

  rect(padx, PADY, padw, 3, pierce > 0 and 4 or 7)
  for i = 1, #balls do
    local b = balls[i]
    circ(b.x, b.y, 1, pierce > 0 and 4 or 7)
  end

  rect(0, 0, 128, 8, 0)
  print(points .. "", 2, 1, 7)
  print("L" .. level, 52, 1, 6)
  for i = 1, lives do
    rect(120 - (i - 1) * 5, 2, 3, 3, 2)
  end
  line(0, 8, 127, 8, 1)

  if lives <= 0 then
    rect(20, 52, 88, 24, 0)
    rectb(20, 52, 88, 24, 2)
    print("THE VEIL HOLDS", 34, 58, 2)
    print("PRESS O", 50, 67, 3)
  elseif stuck then
    print("O TO LAUNCH", 42, 100, 3)
  end
end

function _cover()
  cls(0)
  local rows = { 2, 3, 4, 5, 6 }
  for r = 1, 5 do
    for c = 0, 7 do
      if (r + c) % 2 == 0 or r > 3 then
        rect(4 + c * 15, 8 + (r - 1) * 9, 14, 8, rows[r])
      end
    end
  end

  rect(46, 108, 36, 5, 7)
  rect(60, 96, 5, 5, 4)
  rect(30, 92, 7, 5, 5)
  print("W", 32, 92, 0)

  rect(0, 58, 128, 30, 0)
  print("THE", 46, 60, 7, 3)
  print("VEIL", 40, 76, 2, 3)
end
