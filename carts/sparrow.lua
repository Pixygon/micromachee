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
local SPEED = 3          -- the sky grew; the sparrow keeps its old feel
local MAXSHOT = 12
local GUNMAX = 4
local INVULN = 48          -- frames of grace after losing a feather

local px, py, cool, invuln
local shots, foes, fire, gifts, bots
local wing, wingleft, wingclean, spawn
local gun, kills, dist, best, dead, tick, shake
local bits

function _init()
  px, py = 16, 78
  cool = 0
  shots, foes, fire, gifts = {}, {}, {}, {}
  bots = { { x = px - 8, y = py - 9 }, { x = px - 8, y = py + 9 } }
  invuln = 0
  wing, spawn = 0, 16
  wingleft, wingclean = {}, {}
  gun, kills, dist, dead, tick, shake = 1, 0, 0, false, 0, 0
  bits = {}
  best = best or 0
  score(0)
end

local function burst(x, y, n, c)
  for _ = 1, n do
    bits[#bits + 1] = {
      x = x, y = y, dx = rnd(3) - 1.5, dy = rnd(3) - 1.5,
      life = 6 + flr(rnd(8)), c = c,
    }
  end
end

local function die()
  dead = true
  shake = 8
  burst(px + 4, py + 2, 16, 3)
  sfx(2)
  lose()
end

-- A hit costs you a feather, not the run. Only a bird with nothing left to
-- lose dies to one — which makes every upgrade a life as well as a gun, and
-- makes flying into a wing to clear it a real wager rather than a mistake.
local function damage()
  if invuln > 0 or dead then return end
  if gun > 1 then
    gun = gun - 1
    invuln = INVULN
    burst(px + 4, py + 2, 8, 4)
    sfx(5)
  else
    die()
  end
end

-- ── what comes at you ───────────────────────────────────────────────────────

-- A wing of drifters, entering in a staggered line so it reads as a formation
-- crossing the screen rather than four separate things that happen to arrive.
local function send_wing()
  wing = wing + 1
  local n = 4 + flr(rnd(3))
  local base = 24 + rnd(112)
  local gunner = dist > 400 and rnd(1) < 0.45
  wingleft[wing] = n
  wingclean[wing] = true
  for i = 0, n - 1 do
    foes[#foes + 1] = {
      x = 244 + i * 11,
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
  -- The gun gets faster as well as wider. Extra barrels alone made an upgrade
  -- you could see and not feel.
  cool = mid(4, 8 - gun, 8)
  sfx(0)
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
  burst(f.x + 4, f.y + 3, 5, f.kind == 1 and 2 or 3)
  sfx(1)
  table.remove(foes, i)
  kills = kills + 1
  wingleft[f.wing] = wingleft[f.wing] - 1
  -- The gift is for the whole wing, not the last one of it, and only if none
  -- of them got behind you.
  if wingleft[f.wing] == 0 then
    if wingclean[f.wing] and gun < GUNMAX then
      gifts[#gifts + 1] = { x = f.x, y = f.y, t = 0 }
      sfx(6)
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
  px = mid(2, px, 232 - PW)
  py = mid(14, py, 154 - PH)

  if cool > 0 then cool = cool - 1 end
  if invuln > 0 then invuln = invuln - 1 end
  if btn(4) then shoot() end

  -- They chase their station rather than holding it, so they swing out behind
  -- a turn and settle back. A rigid offset reads as three sprites glued
  -- together; a lag reads as a formation.
  for i = 1, 2 do
    local b = bots[i]
    local tx, ty = px - 9, py + (i == 1 and -9 or 9)
    b.x = b.x + (tx - b.x) * 0.16
    b.y = b.y + (ty - b.y) * 0.16
  end

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
    if s.x > 240 or s.y < 12 or s.y > 159 then table.remove(shots, i) end
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
      if f.cool <= 0 and f.x < 238 then
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
    elseif invuln <= 0 and hits(px, py, PW, PH, f.x, f.y, 8, 6) then
      -- The thing that hit you dies with the feather it took.
      table.remove(foes, i)
      damage()
      if dead then return end
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
    elseif invuln <= 0 and hits(px, py, PW, PH, b.x, b.y, 3, 2) then
      table.remove(fire, i)
      damage()
      if dead then return end
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
      burst(px + 4, py + 2, 8, 5)
      sfx(3)
    end
  end

  -- Distance counts as well as kills, so the console has to hear about it every
  -- frame and not only when something dies.
  for i = #bits, 1, -1 do
    local b = bits[i]
    b.x, b.y, b.life = b.x + b.dx * 0.7, b.y + b.dy * 0.7, b.life - 1
    if b.life <= 0 then table.remove(bits, i) end
  end

  local total = kills * 10 + flr(dist / 10)
  score(total)
  if total > best then best = total end
end

-- ── how it looks ────────────────────────────────────────────────────────────

-- The bird you are flying is the bird you have earned. Each upgrade adds a
-- visible piece, so the gun level is legible from the sprite and not only from
-- the pips in the corner — you can see what a hit just cost you.
--
-- The HITBOX does not grow with it. PW and PH stay where they are, because an
-- upgrade that makes you easier to hit is a punishment for doing well.
local function draw_sparrow(x, y, c, lv)
  lv = lv or 1
  if lv >= 3 then
    rect(x - 3, y + 2, 3, 1, c)    -- tail, streaming behind
    pset(x - 4, y + 2, 6)
  end
  if lv >= 2 then
    rect(x, y - 1, 4, 1, c)        -- the wings reach further
    rect(x, y + 5, 4, 1, c)
  end
  rect(x, y + 1, 6, 3, c)          -- body
  rect(x + 5, y + 2, 3, 1, c)      -- beak, pointing the way it is going
  rect(x + 1, y, 3, 1, c)          -- wing up
  rect(x + 1, y + 4, 3, 1, c)      -- wing down
  pset(x + 4, y + 1, 6)            -- the eye
  if lv >= 3 then pset(x + 2, y + 2, 4) end   -- a lit core
  if lv >= 4 then
    pset(x + 6, y + 1, 4)
    pset(x + 6, y + 3, 4)
  end
end

local function draw_bot(b, c)
  local x, y = flr(b.x), flr(b.y)
  rect(x, y, 4, 3, c)
  pset(x + 4, y + 1, 4)
  pset(x + 1, y + 1, 0)
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
  for i = 0, 21 do
    pset((i * 47 - flr(dist * 2)) % 240, 16 + (i * 31) % 132, 1)
  end
  for i = 0, 16 do
    pset((i * 61 - flr(dist * 3)) % 240, 18 + (i * 43) % 128, 1)
  end
  for i = 0, 10 do
    pset((i * 71 - flr(dist * 5)) % 240, 20 + (i * 53) % 124, 6)
  end

  for i = 1, #gifts do
    local g = gifts[i]
    local c = flr(g.t / 4) % 2 == 0 and 5 or 4
    rect(flr(g.x), flr(g.y), 7, 7, c)
    rect(flr(g.x) + 2, flr(g.y) + 2, 3, 3, 0)
  end

  for i = 1, #foes do draw_foe(foes[i]) end
  for i = 1, #bits do
    local b = bits[i]
    pset(flr(b.x), flr(b.y), b.life > 5 and 7 or b.c)
  end

  for i = 1, #fire do
    local b = fire[i]
    rect(flr(b.x), flr(b.y), 3, 2, 2)
  end
  for i = 1, #shots do
    local s = shots[i]
    rect(flr(s.x), flr(s.y), 3, 1, 4)
  end

  if gun >= 4 and not dead then
    for i = 1, 2 do draw_bot(bots[i], 5) end
  end

  -- Flashing while the grace lasts, so being hit is something you see happen
  -- rather than something you notice in the pips a second later.
  if not dead and (invuln == 0 or flr(invuln / 3) % 2 == 0) then
    draw_sparrow(flr(px), flr(py), 7, gun)
  elseif shake > 0 then
    circb(flr(px) + 4, flr(py) + 2, 10 - shake, 2)
    circb(flr(px) + 4, flr(py) + 2, 14 - shake, 3)
  end

  rect(0, 0, 240, 12, 0)
  line(0, 12, 239, 12, 1)
  print(kills * 10 + flr(dist / 10) .. "", 2, 3, 7)
  print("BEST " .. best, 190, 3, 6)
  for i = 1, GUNMAX do
    rect(110 + (i - 1) * 5, 4, 3, 4, i <= gun and 5 or 1)
  end

  if dead then
    rect(72, 67, 96, 26, 0)
    rectb(72, 67, 96, 26, 2)
    print("IT DOES NOT ARRIVE", 84, 73, 2)
    print("PRESS O", 106, 83, 3)
  end
end

function _cover()
  -- Drawn for the SHELF first, where it is a thumbnail a third of an inch
  -- across. The in-game sparrow is eight pixels wide and vanishes at that size,
  -- so the cover carries one big bird, three thick tracers and a column of
  -- things in the way — shapes that survive being made small.
  cls(0)
  for i = 0, 23 do pset((i * 37) % 240, 8 + (i * 29) % 104, 1) end
  for i = 0, 10 do pset((i * 71) % 240, 14 + (i * 53) % 94, 6) end

  local x, y = 24, 48
  rect(x, y + 4, 32, 16, 7)          -- body
  rect(x + 30, y + 9, 16, 6, 7)      -- beak
  rect(x + 6, y - 6, 18, 10, 7)      -- wing up
  rect(x + 6, y + 20, 18, 10, 7)     -- wing down
  rect(x + 21, y + 8, 6, 5, 6)       -- the eye

  rect(72, y + 2, 120, 5, 4)
  rect(72, y + 11, 92, 4, 4)
  rect(72, y + 20, 106, 5, 4)

  for i = 0, 4 do
    local ex, ey = 196 + (i % 2) * 14, 8 + i * 24
    rect(ex + 4, ey, 12, 10, 2)
    rect(ex, ey + 3, 6, 5, 2)
    rect(ex + 7, ey + 2, 4, 4, 0)
  end

  rect(0, 118, 240, 42, 0)
  print("SPARROW", 64, 128, 6, 4)
end
