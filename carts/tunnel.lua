-- title: Down-Shaft
-- author: pixygon
-- about: it looks like a tower rising. fly it down.

-- The cave IS stored — two arrays of column heights, scrolled one step a
-- frame. What is not stored is the SHAPE the ship has to fit through: instead
-- of testing the ship against those numbers, it reads the pixel it is about to
-- occupy with pget() and asks what colour it is. Collision therefore agrees
-- with what is on screen by construction, and cannot drift from it.

local FLOOR = 152
local SHIPX = 44

function _init()
  ship = 76
  vel = 0
  dist = 0
  dead = 0
  best = 0
  -- The cave walls, as a column of gap-centres scrolling right to left.
  top, bot = {}, {}
  centre, width, drift = 76, 56, 0
  for i = 1, 241 do
    top[i], bot[i] = centre - width / 2, centre + width / 2
  end
end

function carve()
  -- One new column of cave per frame, wandering and slowly narrowing.
  if dist < 45 then return end
  drift = drift + (rnd(2) - 1) * 0.35
  drift = mid(-1.4, drift, 1.4)
  centre = mid(28, centre + drift, 124)
  width = mid(24, width - 0.012, 56)
  for i = 1, 240 do
    top[i], bot[i] = top[i + 1], bot[i + 1]
  end
  top[241] = centre - width / 2
  bot[241] = centre + width / 2
end

function _update()
  if dead > 0 then
    dead = dead - 1
    if dead == 0 then _init() end
    return
  end

  if btn(2) or btn(4) then vel = vel - 0.22 else vel = vel + 0.11 end
  vel = mid(-1.7, vel, 1.7)
  ship = ship + vel

  carve()
  dist = dist + 1
  score(dist)

  -- Collision: did the nose of the ship end up inside a wall we drew?
  if ship < 3 or ship > FLOOR - 3 then
    dead = 30
    sfx(2)
    lose()
  elseif pget(SHIPX + 4, flr(ship)) ~= 0 and pget(SHIPX + 4, flr(ship)) ~= 4 then
    dead = 30
    sfx(2)
    lose()
  end
end

function _draw()
  cls(0)

  -- The cave, one vertical pair per column.
  for i = 1, 240 do
    local x = i - 1
    rect(x, 0, 1, top[i], 1)
    rect(x, bot[i], 1, FLOOR - bot[i], 1)
    pset(x, top[i], 6)
    pset(x, bot[i] - 1, 6)
  end

  -- The ship: a little arrow that tilts with its velocity.
  local y = flr(ship)
  local c = 4
  if dead > 0 then c = 2 end
  line(SHIPX, y, SHIPX + 7, y, c)
  line(SHIPX, y - 1 - flr(vel / 2), SHIPX + 4, y, c)
  line(SHIPX, y + 1 - flr(vel / 2), SHIPX + 4, y, c)

  rect(0, FLOOR, 240, 8, 1)
  print(dist, 2, FLOOR + 2, 7)
  if dist > best then best = dist end
  print("BEST " .. best, 190, FLOOR + 2, 6)

  if dead > 0 then
    rect(86, 71, 68, 18, 0)
    rectb(86, 71, 68, 18, 2)
    print("YOU HIT THE WALL", 90, 75, 7)
    print("DISTANCE " .. dist, 90, 82, 4)
  elseif dist < 60 then
    print("HOLD UP OR Z TO FLY", 82, 40, 6)
  end
end

function _cover()
  cls(0)
  -- The cave, as a mouth narrowing to the right.
  for x = 0, 239 do
    local mid = 80 + 24 * math.sin(x / 48)
    local gap = 58 - x * 0.15
    rect(x, 0, 1, mid - gap / 2, 1)
    rect(x, mid + gap / 2, 1, 160, 1)
    pset(x, mid - gap / 2, 6)
    pset(x, mid + gap / 2, 6)
  end

  local sy = 80 + 24 * math.sin(180 / 48)
  rect(172, sy - 4, 14, 8, 7)
  rect(178, sy - 2, 6, 4, 6)
  rect(162, sy - 2, 10, 4, 3)
  rect(156, sy - 1, 6, 2, 4)

  rect(0, 126, 240, 34, 0)
  print("DOWN-SHAFT", 40, 134, 6, 4)
end
