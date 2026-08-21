-- title: Down-Shaft
-- author: pixygon
-- about: it looks like a tower rising. fly it down.

-- The cave IS stored — two arrays of column heights, scrolled one step a
-- frame. What is not stored is the SHAPE the ship has to fit through: instead
-- of testing the ship against those numbers, it reads the pixel it is about to
-- occupy with pget() and asks what colour it is. Collision therefore agrees
-- with what is on screen by construction, and cannot drift from it.

local FLOOR = 122

function _init()
  ship = 64
  vel = 0
  dist = 0
  dead = 0
  best = 0
  -- The cave walls, as a column of gap-centres scrolling right to left.
  top, bot = {}, {}
  centre, width, drift = 64, 46, 0
  for i = 1, 129 do
    top[i], bot[i] = centre - width / 2, centre + width / 2
  end
end

function carve()
  -- One new column of cave per frame, wandering and slowly narrowing.
  if dist < 45 then return end
  drift = drift + (rnd(2) - 1) * 0.35
  drift = mid(-1.4, drift, 1.4)
  centre = mid(22, centre + drift, 106)
  width = mid(20, width - 0.012, 46)
  for i = 1, 128 do
    top[i], bot[i] = top[i + 1], bot[i + 1]
  end
  top[129] = centre - width / 2
  bot[129] = centre + width / 2
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
    lose()
  elseif pget(30, flr(ship)) ~= 0 and pget(30, flr(ship)) ~= 4 then
    dead = 30
    lose()
  end
end

function _draw()
  cls(0)

  -- The cave, one vertical pair per column.
  for i = 1, 128 do
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
  line(26, y, 33, y, c)
  line(26, y - 1 - flr(vel / 2), 30, y, c)
  line(26, y + 1 - flr(vel / 2), 30, y, c)

  rect(0, FLOOR, 128, 6, 1)
  print(dist, 2, FLOOR + 1, 7)
  if dist > best then best = dist end
  print("BEST " .. best, 74, FLOOR + 1, 6)

  if dead > 0 then
    rect(30, 54, 68, 18, 0)
    rectb(30, 54, 68, 18, 2)
    print("YOU HIT THE WALL", 34, 58, 7)
    print("DISTANCE " .. dist, 34, 65, 4)
  elseif dist < 60 then
    print("HOLD UP OR Z TO FLY", 22, 30, 6)
  end
end

function _cover()
  cls(0)
  -- The cave, as a mouth narrowing to the right.
  for x = 0, 127 do
    local mid = 64 + 18 * math.sin(x / 26)
    local gap = 46 - x * 0.22
    rect(x, 0, 1, mid - gap / 2, 1)
    rect(x, mid + gap / 2, 1, 128, 1)
    pset(x, mid - gap / 2, 6)
    pset(x, mid + gap / 2, 6)
  end

  local sy = 64 + 18 * math.sin(96 / 26)
  rect(90, sy - 4, 14, 8, 7)
  rect(96, sy - 2, 6, 4, 6)
  rect(80, sy - 2, 10, 4, 3)
  rect(74, sy - 1, 6, 2, 4)

  rect(0, 100, 128, 28, 0)
  print("DOWN-SHAFT", 4, 106, 6, 3)
end
