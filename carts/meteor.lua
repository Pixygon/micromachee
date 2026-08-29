-- title: Plate Fall
-- author: pixygon
-- about: the sphere is shedding. do not be under it

-- A dodger that gets harder by spawning more often rather than by moving
-- faster, so it stays readable across 240 pixels: at speed the screen fills
-- up, but nothing ever crosses the screen faster than the eye can follow.

local SHIPY  = 146
local SPAWN0 = 14      -- frames between rocks at the start
local SPAWN1 = 4       -- and once it has fully warmed up
local WARMUP = 45 * 30 -- frames to get from one to the other

local shipx, rocks, alive, frames, cooldown, points, best

local function spawn()
  local w = 6 + flr(rnd(10))
  rocks[#rocks + 1] = {
    x = flr(rnd(240 - w)),
    y = -8,
    w = w,
    h = 4 + flr(rnd(4)),
    v = 1.2 + rnd(1.4),
    c = 2 + flr(rnd(3)),
  }
end

local function spawn_gap()
  -- Linear from SPAWN0 down to SPAWN1 across the warm-up, then flat.
  local k = mid(0, frames / WARMUP, 1)
  return SPAWN0 + (SPAWN1 - SPAWN0) * k
end

function _init()
  shipx    = 120
  rocks    = {}
  alive    = true
  frames   = 0
  cooldown = 0
  points   = 0
  best     = best or 0
  score(0)
end

function _update()
  if not alive then
    if btnp(4) then _init() end
    return
  end

  frames = frames + 1
  points = flr(frames / 3)
  score(points)
  sfx(3)
  if points > best then best = points end

  -- 240 wide now: the ship crosses the field at the old feel, not the old pixels
  if btn(0) then shipx = shipx - 3.5 end
  if btn(1) then shipx = shipx + 3.5 end
  shipx = mid(3, shipx, 236)

  cooldown = cooldown - 1
  if cooldown <= 0 then
    spawn()
    cooldown = spawn_gap()
  end

  -- Walk backwards so removing the rock under the cursor cannot skip the next.
  for i = #rocks, 1, -1 do
    local r = rocks[i]
    r.y = r.y + r.v
    if r.y > 160 then
      table.remove(rocks, i)
    elseif r.y + r.h >= SHIPY - 2 and r.y <= SHIPY + 2
       and shipx + 2 >= r.x and shipx - 2 <= r.x + r.w then
      alive = false
      sfx(5)
      lose()
    end
  end
end

function _draw()
  cls(0)

  -- A few stars, placed by position rather than stored, so they cost nothing.
  for i = 0, 23 do
    local sy = (i * 37 + flr(t() * 18)) % 160
    pset((i * 53) % 240, sy, 1)
  end

  for i = 1, #rocks do
    local r = rocks[i]
    rect(r.x, r.y, r.w, r.h, r.c)
  end

  if alive then
    rect(shipx - 1, SHIPY - 3, 3, 4, 6)
    rect(shipx - 3, SHIPY + 1, 7, 2, 6)
    pset(shipx, SHIPY + 3, 4)
  else
    circ(shipx, SHIPY, 3, 3)
    circb(shipx, SHIPY, 5, 2)
  end

  -- The HUD gets its own ground, drawn over the rocks: without it a rock
  -- falling past the top makes the score unreadable at the moment you most
  -- want to read it. Rocks spawn above the bar and slide out from under it,
  -- which reads as entering the screen rather than popping into it.
  rect(0, 0, 240, 16, 0)
  line(0, 16, 239, 16, 1)
  print("SCORE " .. points, 2, 2, 7)
  print("BEST " .. best, 2, 9, 6)

  if not alive then
    rect(81, 68, 78, 24, 0)
    rectb(81, 68, 78, 24, 2)
    print("A PLATE TAKES YOU", 86, 74, 2)
    print("PRESS O", 106, 82, 3)
  end
end

function _cover()
  cls(0)
  for i = 0, 59 do
    pset((i * 53) % 240, (i * 37) % 160, 1)
  end

  rect(24, 18, 30, 11, 2)
  rect(150, 30, 22, 9, 3)
  rect(88, 50, 34, 12, 2)
  rect(196, 64, 18, 8, 4)
  rect(48, 78, 24, 9, 3)
  rect(170, 96, 26, 10, 2)

  rect(117, 116, 5, 9, 6)
  rect(112, 124, 15, 5, 6)
  pset(119, 130, 4)
  pset(119, 132, 3)

  rect(0, 136, 240, 24, 0)
  print("PLATE FALL", 40, 139, 3, 4)
end
