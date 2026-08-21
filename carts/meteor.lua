-- title: Meteor
-- author: pixygon
-- about: fall forever, hit nothing

-- A dodger that gets harder by spawning more often rather than by moving
-- faster, so it stays readable at 128 pixels: at speed the screen fills up,
-- but nothing ever crosses the screen faster than the eye can follow.

local SHIPY  = 112
local SPAWN0 = 26      -- frames between rocks at the start
local SPAWN1 = 7       -- and once it has fully warmed up
local WARMUP = 45 * 30 -- frames to get from one to the other

local shipx, rocks, alive, frames, cooldown, points, best

local function spawn()
  local w = 6 + flr(rnd(10))
  rocks[#rocks + 1] = {
    x = flr(rnd(128 - w)),
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
  shipx    = 64
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
  if points > best then best = points end

  if btn(0) then shipx = shipx - 2 end
  if btn(1) then shipx = shipx + 2 end
  shipx = mid(3, shipx, 124)

  cooldown = cooldown - 1
  if cooldown <= 0 then
    spawn()
    cooldown = spawn_gap()
  end

  -- Walk backwards so removing the rock under the cursor cannot skip the next.
  for i = #rocks, 1, -1 do
    local r = rocks[i]
    r.y = r.y + r.v
    if r.y > 128 then
      table.remove(rocks, i)
    elseif r.y + r.h >= SHIPY - 2 and r.y <= SHIPY + 2
       and shipx + 2 >= r.x and shipx - 2 <= r.x + r.w then
      alive = false
    end
  end
end

function _draw()
  cls(0)

  -- A few stars, placed by position rather than stored, so they cost nothing.
  for i = 0, 11 do
    local sy = (i * 37 + flr(t() * 18)) % 128
    pset((i * 53) % 128, sy, 1)
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

  -- The HUD gets its own black backing, drawn over the rocks: without it a
  -- rock falling past the top makes the score unreadable at the moment you
  -- most want to read it. Rocks spawn above the bar and slide out from under
  -- it, which reads as entering the screen rather than popping into it.
  rect(0, 0, 128, 16, 0)
  line(0, 16, 127, 16, 1)
  print("SCORE " .. points, 2, 2, 7)
  print("BEST " .. best, 2, 9, 6)

  if not alive then
    rect(28, 52, 72, 24, 0)
    rectb(28, 52, 72, 24, 2)
    print("YOU HIT A ROCK", 36, 58, 2)
    print("PRESS O", 50, 66, 3)
  end
end
