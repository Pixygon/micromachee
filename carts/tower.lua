-- title: The Tower
-- author: pixygon
-- about: climb it. the journey's end is so close
-- mega: no

-- The Tower sign: "a massive tower guides them all. The journey's end is so
-- close." So you climb, and each floor is further up and worse.
--
-- This is a raycaster, which on a 128x128 screen with eight colours is less mad
-- than it sounds. One ray per screen column, walked over a grid by DDA until it
-- meets a wall; the distance to that wall becomes the height of a ONE PIXEL
-- WIDE rectangle. That is the whole renderer: 128 calls to rect() and two more
-- for the floor and the ceiling. No per-pixel work anywhere, which is the only
-- reason it fits in a frame's instruction budget.
--
-- Depth is drawn with the palette's own ordering rather than with light. The
-- theme guarantees 0 < 1 < 2 < 6 < 3 < 5 < 4 < 7 from dark to light, so walking
-- that list backwards as distance grows makes far walls darker in every colour
-- mode there will ever be. A cart that hardcoded "grey" would have one.

local MAPW, MAPH = 24, 24
local FOV = 0.66
local TURN = 0.075
local WALK = 0.085
local REACH = 0.28          -- how close to a wall you may stand

-- Light to dark, which is the palette's rank read backwards. Index 1 is the
-- nearest wall and the last is the furthest thing still worth drawing.
local RAMP = { 7, 4, 5, 3, 6, 2, 1 }
local BAND = 1.7            -- world units per step down the ramp

-- Walls use the whole ramp, so no single colour is safe to give a monster. What
-- is safe is a WARM one: the ramp only reaches 2 and 1 at the far end, so a
-- near thing drawn in 2 can never be confused with the near wall behind it.
local FOE = { 2, 2, 3, 1 }

local map
local px, py, ang, dirx, diry, planex, planey
local zbuf
local foes, exitx, exity
local hp, floor, kills, bonus, best, dead, won, hurt, flash, tick

local TOP = 9               -- floors in the tower

local function points()
  return kills * 10 + (floor - 1) * 50 + bonus
end

local function tile(x, y)
  if x < 0 or y < 0 or x >= MAPW or y >= MAPH then return 1 end
  return map[y * MAPW + x + 1]
end

local function set_tile(x, y, v)
  if x < 0 or y < 0 or x >= MAPW or y >= MAPH then return end
  map[y * MAPW + x + 1] = v
end

local function solid(x, y) return tile(flr(x), flr(y)) > 0 end

-- ── building a floor ────────────────────────────────────────────────────────

local rooms

local function carve_room(rx, ry, rw, rh)
  for y = ry, ry + rh - 1 do
    for x = rx, rx + rw - 1 do set_tile(x, y, 0) end
  end
end

local function carve_corridor(x0, y0, x1, y1)
  local x, y = x0, y0
  while x ~= x1 do
    set_tile(x, y, 0)
    set_tile(x, y + 1, 0)      -- two wide, so a corridor is walkable at speed
    x = x + (x1 > x and 1 or -1)
  end
  while y ~= y1 do
    set_tile(x, y, 0)
    set_tile(x + 1, y, 0)
    y = y + (y1 > y and 1 or -1)
  end
end

local function build()
  map = {}
  for i = 1, MAPW * MAPH do map[i] = 1 end

  rooms = {}
  local want = 5 + flr(rnd(3))
  for _ = 1, want do
    local rw = 4 + flr(rnd(4))
    local rh = 4 + flr(rnd(4))
    local rx = 1 + flr(rnd(MAPW - rw - 2))
    local ry = 1 + flr(rnd(MAPH - rh - 2))
    carve_room(rx, ry, rw, rh)
    rooms[#rooms + 1] = { x = rx + flr(rw / 2), y = ry + flr(rh / 2) }
  end
  for i = 2, #rooms do
    carve_corridor(rooms[i - 1].x, rooms[i - 1].y, rooms[i].x, rooms[i].y)
  end

  -- The border is always wall. A ray that leaves the grid would walk until the
  -- step cap and draw a stripe of nothing at the horizon.
  for i = 0, MAPW - 1 do
    set_tile(i, 0, 1) set_tile(i, MAPH - 1, 1)
    set_tile(0, i, 1) set_tile(MAPW - 1, i, 1)
  end

  local last = rooms[#rooms]
  exitx, exity = last.x, last.y
  -- The way up is a PILLAR standing in the last room, not a floor tile. Every
  -- tile above zero is solid, so a floor-tile exit was one you could see across
  -- the room and never once reach — you touch this one instead.
  set_tile(exitx, exity, 2)

  px, py = rooms[1].x + 0.5, rooms[1].y + 0.5
  -- Face the next room rather than a random direction. Spawning nose-first
  -- into a blank wall is a flat field of one colour, and it reads as a broken
  -- renderer rather than as a wall.
  local look = rooms[2] or rooms[1]
  ang = math.atan(look.y - py, look.x - px)

  foes = {}
  local n = 3 + floor
  for i = 1, n do
    local r = rooms[2 + flr(rnd(#rooms - 1))]
    if r then
      foes[#foes + 1] = {
        x = r.x + 0.5 + rnd(1) - 0.5,
        y = r.y + 0.5 + rnd(1) - 0.5,
        hp = 2,
        cool = 0,
      }
    end
  end
end

function _init()
  floor, hp, kills, bonus = 1, 100, 0, 0
  dead, won, hurt, flash, tick = false, false, 0, 0, 0
  zbuf = {}
  build()
  best = best or 0
  score(0)
end

local function die()
  dead = true
  lose()
end

-- ── looking ─────────────────────────────────────────────────────────────────

local function face()
  dirx, diry = math.cos(ang), math.sin(ang)
  -- The camera plane is the direction turned a quarter turn and scaled by the
  -- field of view. Everything projected uses it, so it is computed once.
  planex, planey = -diry * FOV, dirx * FOV
end

local function walk(amount)
  local nx = px + dirx * amount
  local ny = py + diry * amount
  -- Each axis on its own, so sliding along a wall works instead of stopping
  -- dead at every corner.
  if not solid(nx + (dirx > 0 and REACH or -REACH), py) then px = nx end
  if not solid(px, ny + (diry > 0 and REACH or -REACH)) then py = ny end
end

-- ── the horrors ─────────────────────────────────────────────────────────────

local function step_foes()
  for i = #foes, 1, -1 do
    local f = foes[i]
    local dx, dy = px - f.x, py - f.y
    local d = math.sqrt(dx * dx + dy * dy)
    if d < 9 and d > 0 then
      local sp = 0.028 + floor * 0.002
      local nx, ny = f.x + dx / d * sp, f.y + dy / d * sp
      if not solid(nx, f.y) then f.x = nx end
      if not solid(f.x, ny) then f.y = ny end
    end
    if f.cool > 0 then f.cool = f.cool - 1 end
    if d < 0.7 and f.cool <= 0 then
      f.cool = 24
      hp = hp - (6 + floor)
      hurt = 6
      if hp <= 0 then die() return end
    end
  end
end

-- A shot goes straight down the middle of the view, so the thing it hits is
-- whatever the sprite pass decided was drawn over the centre column — which
-- means the crosshair never lies about what is about to be shot.
local function shoot()
  flash = 4
  local best_i, best_d = 0, 1e9
  for i = 1, #foes do
    local f = foes[i]
    local relx, rely = f.x - px, f.y - py
    local det = planex * diry - dirx * planey
    if det ~= 0 then
      local inv = 1 / det
      local tx = inv * (diry * relx - dirx * rely)
      local ty = inv * (-planey * relx + planex * rely)
      if ty > 0.3 then
        local sx = 64 * (1 + tx / ty)
        local w = 64 / ty
        if sx - w / 2 < 64 and sx + w / 2 > 64 and ty < best_d then
          best_i, best_d = i, ty
        end
      end
    end
  end
  if best_i > 0 and best_d < (zbuf[64] or 1e9) then
    local f = foes[best_i]
    f.hp = f.hp - 1
    if f.hp <= 0 then
      table.remove(foes, best_i)
      kills = kills + 1
      score(points())
    end
  end
end

function _update()
  if dead or won then
    if btnp(4) then _init() end
    return
  end
  tick = tick + 1
  if hurt > 0 then hurt = hurt - 1 end
  if flash > 0 then flash = flash - 1 end

  face()
  -- X turns the shoulder buttons into strafe, which is the only way to circle
  -- something on six buttons.
  if btn(5) then
    local sx, sy = -diry * WALK, dirx * WALK
    if btn(0) then
      if not solid(px - sx * 3, py) then px = px - sx end
      if not solid(px, py - sy * 3) then py = py - sy end
    end
    if btn(1) then
      if not solid(px + sx * 3, py) then px = px + sx end
      if not solid(px, py + sy * 3) then py = py + sy end
    end
  else
    if btn(0) then ang = ang - TURN end
    if btn(1) then ang = ang + TURN end
  end
  face()
  if btn(2) then walk(WALK) end
  if btn(3) then walk(-WALK) end

  if btnp(4) then shoot() end

  step_foes()
  if dead then return end

  -- Close enough to put a hand on it. REACH keeps you 0.78 off the centre of a
  -- solid tile at best, so the test has to be reach, not occupancy.
  local ex, ey = px - (exitx + 0.5), py - (exity + 0.5)
  if ex * ex + ey * ey < 1.4 then
    if floor >= TOP then
      -- Reaching the top ON the top floor, rather than counting to ten and
      -- then saying nine: the HUD and the ending have to agree.
      won = true
      bonus = 200
      win()
    else
      floor = floor + 1
      hp = mid(0, hp + 25, 100)
      build()
    end
    score(points())
  end

  if points() > best then best = points() end
end

-- ── drawing the view ────────────────────────────────────────────────────────

local HORIZON = 62

local function cast()
  for x = 0, 127 do
    local camx = 2 * x / 128 - 1
    local rdx = dirx + planex * camx
    local rdy = diry + planey * camx

    local mx, my = flr(px), flr(py)
    local ddx = rdx == 0 and 1e9 or math.abs(1 / rdx)
    local ddy = rdy == 0 and 1e9 or math.abs(1 / rdy)

    local stepx, sidex, stepy, sidey
    if rdx < 0 then stepx, sidex = -1, (px - mx) * ddx
    else stepx, sidex = 1, (mx + 1 - px) * ddx end
    if rdy < 0 then stepy, sidey = -1, (py - my) * ddy
    else stepy, sidey = 1, (my + 1 - py) * ddy end

    local side, hitv, steps = 0, 0, 0
    while steps < 64 do
      steps = steps + 1
      if sidex < sidey then
        sidex = sidex + ddx
        mx = mx + stepx
        side = 0
      else
        sidey = sidey + ddy
        my = my + stepy
        side = 1
      end
      hitv = tile(mx, my)
      if hitv > 0 then break end
    end

    -- Perpendicular distance, not the ray's own length: using the ray length
    -- bends every wall into a fisheye.
    local dist
    if side == 0 then dist = sidex - ddx else dist = sidey - ddy end
    if dist < 0.05 then dist = 0.05 end
    zbuf[x] = dist

    local h = flr(128 / dist)
    local top = HORIZON - flr(h / 2)
    local bot = top + h
    if top < 0 then top = 0 end
    if bot > 127 then bot = 127 end

    -- Where along the wall the ray landed. Untextured walls make huge flat
    -- fields with nothing to judge distance or angle by; a seam at every half
    -- cell is one comparison per column and gives back the whole perspective.
    local wallx
    if side == 0 then wallx = py + dist * rdy else wallx = px + dist * rdx end
    wallx = wallx - flr(wallx)
    local seam = wallx < 0.045 or wallx > 0.955 or math.abs(wallx - 0.5) < 0.028

    local c
    if hitv == 2 then
      -- The way up is always the same colour however far off it is, because
      -- being able to pick it out across a room is the point of it.
      c = 5
    else
      local band = flr(dist / BAND) + 1 + side + (seam and 2 or 0)
      c = RAMP[mid(1, band, #RAMP)]
    end
    if bot >= top then rect(x, top, 1, bot - top + 1, c) end
  end
end

-- Billboards. A sprite is drawn one column at a time so that each column can be
-- tested against the wall distance for that column — otherwise anything behind
-- a corner is painted straight through it.
local function draw_foes()
  -- Furthest first, so nearer ones land on top.
  for i = 1, #foes do
    local f = foes[i]
    f.d = (f.x - px) ^ 2 + (f.y - py) ^ 2
  end
  for i = 2, #foes do
    local v = foes[i]
    local j = i - 1
    while j >= 1 and foes[j].d < v.d do
      foes[j + 1] = foes[j]
      j = j - 1
    end
    foes[j + 1] = v
  end

  local det = planex * diry - dirx * planey
  if det == 0 then return end
  local inv = 1 / det

  for i = 1, #foes do
    local f = foes[i]
    local relx, rely = f.x - px, f.y - py
    local tx = inv * (diry * relx - dirx * rely)
    local ty = inv * (-planey * relx + planex * rely)
    if ty > 0.3 then
      local sx = flr(64 * (1 + tx / ty))
      local h = flr(72 / ty)
      local w = flr(h * 0.7)
      local top = HORIZON - flr(h / 2) + flr(h / 6)
      local body = FOE[mid(1, flr(ty / BAND) + 1, #FOE)]
      local eye = 4

      for col = sx - flr(w / 2), sx + flr(w / 2) do
        if col >= 0 and col <= 127 and ty < (zbuf[col] or 0) then
          local t = (col - (sx - w / 2)) / w      -- 0..1 across the sprite
          -- A shoulders-and-head silhouette, made of two heights rather than
          -- any real art: at this size, outline is all that survives.
          local hh = (t > 0.32 and t < 0.68) and h or flr(h * 0.72)
          local y0 = top + (h - hh)
          if y0 < 0 then y0 = 0 end
          local y1 = top + h
          if y1 > 127 then y1 = 127 end
          if y1 >= y0 then rect(col, y0, 1, y1 - y0 + 1, body) end
        end
      end
      -- Two eyes, once it is close enough for them to be more than noise.
      if ty < 5 and h > 14 then
        local ey = top + flr(h * 0.18)
        local off = flr(w * 0.16)
        if sx - off >= 0 and sx - off <= 127 and ty < (zbuf[sx - off] or 0) then
          rect(sx - off - 1, ey, 2, 2, eye)
        end
        if sx + off >= 0 and sx + off <= 127 and ty < (zbuf[sx + off] or 0) then
          rect(sx + off, ey, 2, 2, eye)
        end
      end
    end
  end
end

function _draw()
  cls(0)
  -- Ceiling dim, floor dark. Two flat fields the walls are then drawn over, so
  -- a distant wall always has something above and below it to be distant
  -- against. Anything fancier needs a per-pixel floor cast, which is the one
  -- thing the frame budget will not pay for.
  rect(0, 0, 128, HORIZON, 1)
  rect(0, HORIZON, 128, 128 - HORIZON, 0)
  cast()
  draw_foes()

  -- the weapon, and the crosshair that tells the truth about it
  local kick = flash > 0 and 2 or 0
  rect(52, 112 + kick, 24, 16, 1)
  rect(56, 106 + kick, 16, 8, 6)
  rect(60, 100 + kick, 8, 8, flash > 0 and 4 or 1)
  line(62, 62, 66, 62, 7)
  line(64, 60, 64, 64, 7)

  if hurt > 0 then rectb(0, 0, 128, 128, 2) end

  rect(0, 0, 128, 10, 0)
  print("HP", 2, 2, 1)
  rect(12, 3, 40, 4, 1)
  rect(12, 3, flr(mid(0, hp, 100) * 0.4), 4, hp > 30 and 5 or 2)
  print("FLOOR " .. floor, 58, 2, 6)
  print(points() .. "", 104, 2, 4)

  if dead then
    rect(12, 50, 104, 28, 0)
    rectb(12, 50, 104, 28, 2)
    print("THE TOWER KEEPS YOU", 22, 56, 2)
    print("FLOOR " .. floor, 30, 67, 1)
    print("PRESS O", 74, 67, 3)
  elseif won then
    rect(10, 48, 108, 32, 0)
    rectb(10, 48, 108, 32, 5)
    print("YOU REACH THE TOP", 26, 54, 5)
    print(TOP .. " FLOORS", 46, 64, 7)
    print("PRESS O", 50, 72, 3)
  end
end

function _cover()
  -- Drawn rather than played: a cover is the one frame that has to read at a
  -- third of an inch, and a corridor drawn on purpose beats a screenshot of one.
  cls(0)
  rect(0, 0, 128, 62, 1)
  rect(0, 62, 128, 42, 0)
  -- a corridor in one-point perspective, straight down the ramp
  local depth = { { 0, 128, 7 }, { 14, 100, 4 }, { 26, 76, 5 }, { 36, 56, 3 }, { 44, 40, 6 } }
  for i = 1, #depth do
    local inset, h, c = depth[i][1], depth[i][2], depth[i][3]
    rect(inset, 62 - flr(h / 2), 6, h, c)
    rect(122 - inset, 62 - flr(h / 2), 6, h, c)
  end
  rect(50, 46, 28, 32, 5)          -- the way up, at the end of it
  -- something in the way
  rect(56, 52, 16, 24, 2)
  rect(52, 60, 24, 16, 2)
  rect(59, 57, 3, 3, 4)
  rect(66, 57, 3, 3, 4)
  rect(0, 100, 128, 28, 0)
  print("THE TOWER", 10, 106, 6, 3)
end
