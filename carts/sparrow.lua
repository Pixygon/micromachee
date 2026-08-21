-- title: Sparrow
-- author: pixygon
-- about: fly for the temple. clear a wing, take its gift

-- The Sparrow: "the symbol of hope, as it guides those who keep the light to
-- the final temple." So this one flies east, alone, and everything in the sky
-- is in the way.
--
-- Enemies arrive in WINGS rather than one at a time, and the wing is the unit
-- that matters: clear one without letting a single member past you and it
-- leaves a gift behind, which is the only way the gun ever grows. That turns
-- "shoot the things" into "shoot the things in time", and it is the whole
-- reason to fly forward into a formation instead of sitting at the left edge
-- picking them off as they arrive.

local PW, PH = 8, 5
local SPEED = 2
local MAXSHOT = 8
local GUNMAX = 3

local px, py, cool
local shots, foes, fire, gifts
local wing, wingleft, wingclean, spawn
local gun, kills, dist, best, dead, tick, shake

function _init()
  px, py = 14, 62
  cool = 0
  shots, foes, fire, gifts = {}, {}, {}, {}
  wing, spawn = 0, 16
  wingleft, wingclean = {}, {}
  gun, kills, dist, dead, tick, shake = 1, 0, 0, false, 0, 0
  best = best or 0
  score(0)
end

local function die()
  dead = true
  shake = 8
  lose()
end

-- ── what comes at you ───────────────────────────────────────────────────────

-- A wing of drifters, entering in a staggered line so it reads as a formation
-- crossing the screen rather than four separate things that happen to arrive.
local function send_wing()
  wing = wing + 1
  local n = 4 + flr(rnd(3))
  local base = 20 + rnd(76)
  local gunner = dist > 400 and rnd(1) < 0.45
  wingleft[wing] = n
  wingclean[wing] = true
  for i = 0, n - 1 do
    foes[#foes + 1] = {
      x = 132 + i * 11,
      y = base,
      home = base,
      t = i * 0.5,
      kind = (gunner and i == flr(n / 2)) and 2 or 1,
      wing = wing,
      cool = 30 + flr(rnd(30)),
    }
  end
end

local function shoot()
  if cool > 0 then return end
  cool = 6
  local x, y = px + PW, py + 2
  if gun == 1 then
    shots[#shots + 1] = { x = x, y = y, vy = 0 }
  elseif gun == 2 then
    shots[#shots + 1] = { x = x, y = y - 2, vy = 0 }
    shots[#shots + 1] = { x = x, y = y + 2, vy = 0 }
  else
    shots[#shots + 1] = { x = x, y = y, vy = 0 }
    shots[#shots + 1] = { x = x, y = y, vy = -1 }
    shots[#shots + 1] = { x = x, y = y, vy = 1 }
  end
  while #shots > MAXSHOT do table.remove(shots, 1) end
end

local function kill(i)
  local f = foes[i]
  table.remove(foes, i)
  kills = kills + 1
  wingleft[f.wing] = wingleft[f.wing] - 1
  -- The gift is for the whole wing, not the last one of it, and only if none
  -- of them got behind you.
  if wingleft[f.wing] == 0 then
    if wingclean[f.wing] and gun < GUNMAX then
      gifts[#gifts + 1] = { x = f.x, y = f.y, t = 0 }
    end
    -- A wing that is done is done. Left in, these two tables grow by one entry
    -- every couple of seconds for as long as the run lasts.
    wingleft[f.wing], wingclean[f.wing] = nil, nil
  end
end

local function hits(ax, ay, aw, ah, bx, by, bw, bh)
  return ax < bx + bw and ax + aw > bx and ay < by + bh and ay + ah > by
end

function _update()
  if dead then
    if shake > 0 then shake = shake - 1 end
    if btnp(4) then _init() end
    return
  end
  tick = tick + 1
  dist = dist + 1

  if btn(0) then px = px - SPEED end
  if btn(1) then px = px + SPEED end
  if btn(2) then py = py - SPEED end
  if btn(3) then py = py + SPEED end
  px = mid(2, px, 120 - PW)
  py = mid(14, py, 122 - PH)

  if cool > 0 then cool = cool - 1 end
  if btn(4) then shoot() end

  -- The sky keeps arriving, a little sooner each time.
  spawn = spawn - 1
  if spawn <= 0 then
    send_wing()
    spawn = mid(24, 48 - flr(dist / 60), 48)
  end

  -- Yours
  for i = #shots, 1, -1 do
    local s = shots[i]
    s.x = s.x + 5
    s.y = s.y + s.vy
    if s.x > 128 or s.y < 12 or s.y > 127 then table.remove(shots, i) end
  end

  -- Theirs
  for i = #foes, 1, -1 do
    local f = foes[i]
    f.t = f.t + 0.11
    if f.kind == 1 then
      -- A drifter rides a wave. The whole wing shares the wave and differs only
      -- by where in it each one started, which is what makes the line ripple.
      f.x = f.x - 1.7
      f.y = f.home + math.sin(f.t) * 16
    else
      f.x = f.x - 1.1
      f.y = f.y + (py - f.y) * 0.012      -- a gunner leans toward you
      f.cool = f.cool - 1
      if f.cool <= 0 and f.x < 126 then
        f.cool = 55 + flr(rnd(30))
        fire[#fire + 1] = { x = f.x, y = f.y + 2 }
      end
    end

    if f.x < -10 then
      -- It got past. That costs the wing its gift and nothing else.
      wingclean[f.wing] = false
      wingleft[f.wing] = wingleft[f.wing] - 1
      if wingleft[f.wing] == 0 then wingleft[f.wing], wingclean[f.wing] = nil, nil end
      table.remove(foes, i)
    elseif hits(px, py, PW, PH, f.x, f.y, 8, 6) then
      die()
      return
    else
      for j = #shots, 1, -1 do
        local s = shots[j]
        if hits(s.x, s.y, 3, 1, f.x, f.y, 8, 6) then
          table.remove(shots, j)
          kill(i)
          break
        end
      end
    end
  end

  for i = #fire, 1, -1 do
    local b = fire[i]
    b.x = b.x - 2.6
    if b.x < -4 then
      table.remove(fire, i)
    elseif hits(px, py, PW, PH, b.x, b.y, 3, 2) then
      die()
      return
    end
  end

  for i = #gifts, 1, -1 do
    local g = gifts[i]
    g.x = g.x - 0.8
    g.t = g.t + 1
    if g.x < -8 then
      table.remove(gifts, i)
    elseif hits(px, py, PW, PH, g.x, g.y, 7, 7) then
      table.remove(gifts, i)
      gun = mid(1, gun + 1, GUNMAX)
    end
  end

  -- Distance counts as well as kills, so the console has to hear about it every
  -- frame and not only when something dies.
  local total = kills * 10 + flr(dist / 10)
  score(total)
  if total > best then best = total end
end

-- ── how it looks ────────────────────────────────────────────────────────────

local function draw_sparrow(x, y, c)
  rect(x, y + 1, 6, 3, c)          -- body
  rect(x + 5, y + 2, 3, 1, c)      -- beak, pointing the way it is going
  rect(x + 1, y, 3, 1, c)          -- wing up
  rect(x + 1, y + 4, 3, 1, c)      -- wing down
  pset(x + 4, y + 1, 6)            -- the eye
end

local function draw_foe(f)
  local x, y = flr(f.x), flr(f.y)
  if f.kind == 1 then
    rect(x + 2, y + 1, 5, 4, 2)
    rect(x, y + 2, 2, 2, 2)
    pset(x + 3, y + 2, 0)
  else
    rect(x + 1, y, 6, 6, 3)
    rect(x, y + 2, 2, 2, 3)
    pset(x + 2, y + 2, 0)
    pset(x + 5, y + 2, 0)
  end
end

function _draw()
  cls(0)

  -- Three depths of star, each scrolling at its own rate, because one rate is
  -- a wallpaper and three is a distance.
  for i = 0, 11 do
    pset((i * 47 - flr(dist * 2)) % 128, 16 + (i * 31) % 100, 1)
  end
  for i = 0, 8 do
    pset((i * 61 - flr(dist * 3)) % 128, 18 + (i * 43) % 96, 1)
  end
  for i = 0, 5 do
    pset((i * 71 - flr(dist * 5)) % 128, 20 + (i * 53) % 92, 6)
  end

  for i = 1, #gifts do
    local g = gifts[i]
    local c = flr(g.t / 4) % 2 == 0 and 5 or 4
    rect(flr(g.x), flr(g.y), 7, 7, c)
    rect(flr(g.x) + 2, flr(g.y) + 2, 3, 3, 0)
  end

  for i = 1, #foes do draw_foe(foes[i]) end

  for i = 1, #fire do
    local b = fire[i]
    rect(flr(b.x), flr(b.y), 3, 2, 2)
  end
  for i = 1, #shots do
    local s = shots[i]
    rect(flr(s.x), flr(s.y), 3, 1, 4)
  end

  if not dead then
    draw_sparrow(flr(px), flr(py), 7)
  elseif shake > 0 then
    circb(flr(px) + 4, flr(py) + 2, 10 - shake, 2)
    circb(flr(px) + 4, flr(py) + 2, 14 - shake, 3)
  end

  rect(0, 0, 128, 12, 0)
  line(0, 12, 127, 12, 1)
  print(kills * 10 + flr(dist / 10) .. "", 2, 3, 7)
  print("BEST " .. best, 78, 3, 6)
  for i = 1, GUNMAX do
    rect(46 + (i - 1) * 5, 4, 3, 4, i <= gun and 5 or 1)
  end

  if dead then
    rect(16, 52, 96, 26, 0)
    rectb(16, 52, 96, 26, 2)
    print("IT DOES NOT ARRIVE", 24, 58, 2)
    print("PRESS O", 50, 68, 3)
  end
end

function _cover()
  -- Drawn for the SHELF first, where it is a thumbnail a third of an inch
  -- across. The in-game sparrow is eight pixels wide and vanishes at that size,
  -- so the cover carries one big bird, three thick tracers and a column of
  -- things in the way — shapes that survive being made small.
  cls(0)
  for i = 0, 15 do pset((i * 37) % 128, 8 + (i * 29) % 84, 1) end
  for i = 0, 6 do pset((i * 71) % 128, 14 + (i * 53) % 74, 6) end

  local x, y = 12, 40
  rect(x, y + 4, 24, 12, 7)          -- body
  rect(x + 22, y + 8, 12, 4, 7)      -- beak
  rect(x + 4, y - 4, 14, 8, 7)       -- wing up
  rect(x + 4, y + 16, 14, 8, 7)      -- wing down
  rect(x + 16, y + 6, 5, 4, 6)       -- the eye

  rect(48, y + 2, 64, 4, 4)
  rect(48, y + 9, 46, 3, 4)
  rect(48, y + 16, 56, 4, 4)

  for i = 0, 3 do
    local ex, ey = 100 + (i % 2) * 10, 8 + i * 22
    rect(ex + 4, ey, 10, 8, 2)
    rect(ex, ey + 2, 5, 4, 2)
    rect(ex + 6, ey + 2, 3, 3, 0)
  end

  rect(0, 92, 128, 36, 0)
  print("SPARROW", 20, 100, 6, 3)
end
