-- title: Breakout
-- author: pixygon
-- about: clear the wall, keep the ball alive

-- Ball position is kept in floats and only rounded when it is drawn, so it
-- moves at speeds that are not whole pixels. Collision is resolved one axis at
-- a time: that is what stops the ball burrowing into a brick corner and coming
-- out the far side.

local COLS, ROWS   = 8, 5
local BW, BH       = 14, 6
local LEFT, TOP    = 8, 14
local PADW, PADY   = 22, 118
local WALL_COLOUR  = { 2, 3, 4, 5, 6 }

local bricks, left, padx, bx, by, vx, vy, points, lives, stuck

local function reset_ball()
  bx, by = padx + PADW / 2, PADY - 3
  vx, vy = 1.1, -1.4
  stuck = true
end

function _init()
  bricks = {}
  left = 0
  for r = 1, ROWS do
    bricks[r] = {}
    for c = 1, COLS do
      bricks[r][c] = true
      left = left + 1
    end
  end
  padx   = 64 - PADW / 2
  points = 0
  lives  = 3
  score(0)
  reset_ball()
end

local function brick_at(x, y)
  local c = flr((x - LEFT) / BW) + 1
  local r = flr((y - TOP) / BH) + 1
  if r >= 1 and r <= ROWS and c >= 1 and c <= COLS and bricks[r][c] then
    return r, c
  end
end

local function hit(x, y)
  local r, c = brick_at(x, y)
  if not r then return false end
  bricks[r][c] = false
  left = left - 1
  points = points + (ROWS - r + 1) * 10
  score(points)
  return true
end

function _update()
  if lives <= 0 or left == 0 then
    if btnp(4) then _init() end
    return
  end

  if btn(0) then padx = padx - 3 end
  if btn(1) then padx = padx + 3 end
  padx = mid(0, padx, 128 - PADW)

  if stuck then
    bx = padx + PADW / 2
    if btnp(4) then stuck = false end
    return
  end

  -- One axis at a time, each with its own bounce.
  bx = bx + vx
  if bx < 1 then bx, vx = 1, -vx end
  if bx > 126 then bx, vx = 126, -vx end
  if hit(bx, by) then vx = -vx end

  by = by + vy
  if by < 8 then by, vy = 8, -vy end
  if hit(bx, by) then vy = -vy end

  -- The paddle steers: where the ball lands on it decides how far it comes off
  -- sideways, which is the whole game.
  if vy > 0 and by >= PADY - 1 and by <= PADY + 2 and bx >= padx and bx <= padx + PADW then
    by = PADY - 1
    vy = -vy
    vx = mid(-2.2, (bx - (padx + PADW / 2)) / 5, 2.2)
  end

  if by > 127 then
    lives = lives - 1
    if lives > 0 then reset_ball() end
  end
end

function _draw()
  cls(0)

  print("SCORE " .. points, 2, 1, 7)
  for i = 1, lives do
    rect(120 - (i - 1) * 5, 2, 3, 3, 2)
  end
  line(0, 7, 127, 7, 1)

  for r = 1, ROWS do
    for c = 1, COLS do
      if bricks[r][c] then
        rect(LEFT + (c - 1) * BW, TOP + (r - 1) * BH, BW - 1, BH - 1, WALL_COLOUR[r])
      end
    end
  end

  rect(padx, PADY, PADW, 3, 7)
  circ(bx, by, 1, 7)

  if left == 0 then
    print("WALL CLEARED", 40, 60, 5)
    print("PRESS O", 50, 68, 3)
  elseif lives <= 0 then
    print("GAME OVER", 46, 60, 2)
    print("PRESS O", 50, 68, 3)
  elseif stuck then
    print("O TO LAUNCH", 42, 100, 3)
  end
end

function _cover()
  cls(0)
  local rows = { 2, 3, 4, 5, 6 }
  for r = 1, 5 do
    for c = 0, 7 do
      rect(4 + c * 15, 8 + (r - 1) * 9, 14, 8, rows[r])
    end
  end

  rect(46, 108, 36, 5, 7)
  rect(60, 96, 5, 5, 4)

  rect(0, 58, 128, 30, 0)
  print("BREAK", 34, 60, 7, 3)
  print("OUT", 46, 76, 2, 3)
end
