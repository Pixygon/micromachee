-- title: Pixiel
-- author: pixygon
-- about: a discarded body, running the pit in stages

-- The Pixiels are the body-stock: skeleton and AI brain, printed over. The ones
-- not cleanly reissued end up in the pit. This one has stopped drifting and
-- started counting: the pit is climbed in STAGES now, three timed levels each,
-- thirty seconds to reach the beacon at the end of every one.
--
-- The four elements are the classical triangles — fire and air point up, water
-- and earth point down, the barred pair are air and earth — and they drop from
-- the things that live down here. Carrying one turns X into a weapon, and each
-- element throws differently: fire flies flat and fast, water lobs, earth is a
-- short heavy fist, air pierces everything in a line.
--
-- The numbers below are still the game. A jump is 4.4 up against 0.30 down —
-- an apex of four tiles, a hair under 60 pixels of ground at full run — and
-- every gap the generator builds is sized against that.

local TILE   = 8
local ROWS   = 20
local GROUND = 17
local ACC    = 0.34
local FRIC   = 0.80
local MAXVX  = 2.0
local GRAV   = 0.30
local JUMP   = -4.4
local CUT    = -1.4
local COYOTE = 4
local BUFFER = 5
local PW, PH = 6, 9

local LEVEL_SECONDS = 30
local PER_STAGE = 3          -- levels in a stage

-- element kinds: 1 fire, 2 water, 3 earth, 4 air
local ELEMC = { 2, 6, 3, 7 }
local ELEMN = { "FIRE", "WATER", "EARTH", "AIR" }

local world, coinat, foes, drops, shots, bits
local px, py, vx, vy, onground, coyote, buffered, face
local camx, coins, dead, best, tick, timer
local stage, lvl, goalcol, done, donewait, elem, shotcool, kills

-- ── the level builds itself ─────────────────────────────────────────────────

local made, plan, planleft, planrow, planhigh, lastgap, laidfoe

local function column()
  local t = {}
  for r = 0, ROWS - 1 do t[r] = 0 end
  return t
end

local function decide()
  -- Past the goal the ground is flat and safe: the beacon is a finish line,
  -- not one more trap.
  if made >= goalcol then
    made = made + 1
    local t = column()
    for r = GROUND, ROWS - 1 do t[r] = 1 end
    world[made] = t
    return
  end

  if planleft <= 0 then
    local roll = rnd(1)
    local hard = mid(0, (stage - 1) * 0.05 + (lvl - 1) * 0.02, 0.2)
    if lastgap then roll = mid(0.42, roll, 1) end
    if plan == "float" then roll = 1 end          -- open ground after a platform
    if roll < 0.16 + hard then
      plan, planleft = "gap", 2 + flr(rnd(2 + stage))
      if planleft > 6 then planleft = 6 end
    elseif roll < 0.40 then
      plan, planleft = "step", 3 + flr(rnd(4))
      planrow = GROUND - 1 - flr(rnd(2))
    elseif roll < 0.64 then
      plan, planleft = "float", 4 + flr(rnd(4))
      planhigh = GROUND - 3
    else
      plan, planleft = "flat", 5 + flr(rnd(8))
    end
    lastgap = plan == "gap"
    laidfoe = false
  end
  planleft = planleft - 1

  made = made + 1
  local t = column()
  if plan ~= "gap" then
    for r = GROUND, ROWS - 1 do t[r] = 1 end
  end
  if plan == "step" then
    for r = planrow, GROUND - 1 do t[r] = 2 end
  elseif plan == "float" then
    t[planhigh] = 2
    if rnd(1) < 0.45 then coinat[made] = planhigh - 2 end
  elseif plan == "flat" then
    -- One foe at most per stretch, more likely the deeper the stage. The
    -- roster grows with the stages: walkers first, hoppers from stage two,
    -- flyers from stage three.
    local chance = 0.07 + stage * 0.02
    if not laidfoe and made > 20 and planleft > 1 and rnd(1) < chance then
      local kinds = stage >= 3 and 3 or (stage >= 2 and 2 or 1)
      foes[#foes + 1] = {
        x = made * TILE, y = (GROUND - 1) * TILE, d = -1,
        kind = 1 + flr(rnd(kinds)), t = flr(rnd(60)),
      }
      laidfoe = true
    end
    if rnd(1) < 0.06 then coinat[made] = GROUND - 3 end
  end
  world[made] = t
end

local function generate_to(col)
  while made < col do decide() end
end

local function tile(c, r)
  if r < 0 or r >= ROWS then return 0 end
  local t = world[c]
  if not t then return 0 end
  return t[r]
end

local function solid(wx, wy)
  return tile(flr(wx / TILE), flr(wy / TILE)) > 0
end

local function boxhit(x, y, w, h)
  return solid(x, y) or solid(x + w - 1, y)
      or solid(x, y + h - 1) or solid(x + w - 1, y + h - 1)
      or solid(x, y + h / 2) or solid(x + w - 1, y + h / 2)
end

-- ── stages ──────────────────────────────────────────────────────────────────

local function level_len()
  return 120 + (stage - 1) * 18 + (lvl - 1) * 10
end

local function start_level()
  world, coinat, foes, drops, shots, bits = {}, {}, {}, {}, {}, {}
  made, plan, planleft, lastgap, laidfoe = 0, "flat", 12, false, false
  planrow, planhigh = GROUND - 1, GROUND - 3
  goalcol = level_len()
  generate_to(56)
  px, py = 24, (GROUND - 2) * TILE
  vx, vy = 0, 0
  onground, coyote, buffered, face = true, 0, 0, 1
  camx, dead, tick = 0, false, 0
  timer = LEVEL_SECONDS * 30
  done, donewait, shotcool = false, 0, 0
end

function _init()
  stage, lvl = 1, 1
  coins, kills, elem = 0, 0, 0
  best = best or 0
  start_level()
  score(0)
end

local function points()
  return ((stage - 1) * PER_STAGE + (lvl - 1)) * 100 + coins * 5 + kills * 10
end

local function puff(x, y, n, c)
  for _ = 1, n do
    bits[#bits + 1] = { x = x, y = y, dx = rnd(2) - 1, dy = -rnd(1.4),
      life = 6 + flr(rnd(6)), c = c }
  end
end

local function die()
  dead = true
  elem = 0                    -- the pit keeps what you carried
  sfx(2)
  puff(px + 3, py + 4, 10, 2)
  lose()
end

local function kill_foe(i)
  local f = foes[i]
  puff(f.x + 3, f.y + 3, 6, 3)
  sfx(1)
  table.remove(foes, i)
  kills = kills + 1
  -- Some of them were carrying an element. It falls where they fell.
  if rnd(1) < 0.35 then
    drops[#drops + 1] = { x = f.x, y = f.y, kind = 1 + flr(rnd(4)), t = 0 }
  end
end

-- ── the elements as weapons ─────────────────────────────────────────────────

local function shoot()
  if elem == 0 or shotcool > 0 then return end
  shotcool = 12
  sfx(0)
  local sx, sy = px + (face > 0 and PW or 0), py + 3
  if elem == 1 then          -- fire: flat and fast
    shots[#shots + 1] = { x = sx, y = sy, dx = face * 4, dy = 0, life = 26, kind = 1, pierce = 0 }
  elseif elem == 2 then      -- water: a lob
    shots[#shots + 1] = { x = sx, y = sy, dx = face * 2.4, dy = -2.2, life = 50, kind = 2, pierce = 0, grav = true }
  elseif elem == 3 then      -- earth: short heavy fist
    shots[#shots + 1] = { x = sx, y = sy, dx = face * 2, dy = 0, life = 14, kind = 3, pierce = 1, big = true }
  else                       -- air: pierces the whole line
    shots[#shots + 1] = { x = sx, y = sy, dx = face * 5, dy = 0, life = 30, kind = 4, pierce = 99 }
  end
end

-- ── one frame ───────────────────────────────────────────────────────────────

function _update()
  if dead then
    if btnp(4) then start_level() score(points()) end
    return
  end
  if done then
    donewait = donewait - 1
    if donewait <= 0 then
      lvl = lvl + 1
      if lvl > PER_STAGE then lvl, stage = 1, stage + 1 end
      start_level()
    end
    return
  end
  tick = tick + 1
  if shotcool > 0 then shotcool = shotcool - 1 end

  -- the clock is the level's real enemy
  timer = timer - 1
  if timer <= 0 then die() return end

  local want = 0
  if btn(0) then want = want - 1 end
  if btn(1) then want = want + 1 end
  if want ~= 0 then
    vx = mid(-MAXVX, vx + ACC * want, MAXVX)
    face = want
  else
    vx = vx * FRIC
    if vx > -0.05 and vx < 0.05 then vx = 0 end
  end

  if btnp(4) then buffered = BUFFER end
  if buffered > 0 then buffered = buffered - 1 end
  if coyote > 0 then coyote = coyote - 1 end
  if buffered > 0 and coyote > 0 then
    vy, onground, coyote, buffered = JUMP, false, 0, 0
    puff(px + 3, py + 9, 3, 1)
    sfx(4)
  end
  if not btn(4) and vy < CUT then vy = CUT end
  if btnp(5) then shoot() end

  vy = mid(-8, vy + GRAV, 6)

  local nx = px + vx
  if boxhit(nx, py, PW, PH) then
    local step, guard = vx > 0 and -1 or 1, 0
    while boxhit(nx, py, PW, PH) and guard < TILE + 2 do
      nx, guard = nx + step, guard + 1
    end
    vx = 0
  end
  px = nx
  if px < camx then px, vx = camx, 0 end

  local ny = py + vy
  if boxhit(px, ny, PW, PH) then
    local step, guard = vy > 0 and -1 or 1, 0
    while boxhit(px, ny, PW, PH) and guard < TILE + 2 do
      ny, guard = ny + step, guard + 1
    end
    if vy > 0 then onground, coyote = true, COYOTE end
    vy = 0
  else
    if onground then coyote = COYOTE end
    onground = false
  end
  py = ny

  -- coins and dropped elements
  local col = flr((px + PW / 2) / TILE)
  local row = flr((py + PH / 2) / TILE)
  if coinat[col] and row >= coinat[col] - 1 and row <= coinat[col] + 1 then
    coinat[col] = nil
    coins = coins + 1
    puff(col * TILE + 4, row * TILE + 4, 4, 4)
    sfx(3)
  end
  for i = #drops, 1, -1 do
    local d = drops[i]
    d.t = d.t + 1
    if not solid(d.x + 3, d.y + 8) and d.y < 150 then d.y = d.y + 1.5 end
    if px + PW > d.x and px < d.x + 7 and py + PH > d.y and py < d.y + 7 then
      elem = d.kind
      table.remove(drops, i)
      puff(d.x + 3, d.y + 3, 6, ELEMC[elem])
      sfx(3)
    elseif d.t > 600 then
      table.remove(drops, i)
    end
  end

  -- shots against the world and its tenants
  for i = #shots, 1, -1 do
    local s = shots[i]
    s.x = s.x + s.dx
    if s.grav then s.dy = s.dy + 0.18 end
    s.y = s.y + s.dy
    s.life = s.life - 1
    local w = s.big and 5 or 3
    local gone = s.life <= 0 or solid(s.x + w / 2, s.y + 1)
    for j = #foes, 1, -1 do
      local f = foes[j]
      if s.x + w > f.x and s.x < f.x + 6 and s.y + 3 > f.y and s.y < f.y + 7 then
        kill_foe(j)
        if s.pierce > 0 then s.pierce = s.pierce - 1 else gone = true end
      end
    end
    if gone then table.remove(shots, i) end
  end

  -- the roster
  for i = #foes, 1, -1 do
    local f = foes[i]
    if f.x < camx - 40 then
      table.remove(foes, i)
    else
      f.t = (f.t or 0) + 1
      if f.kind == 1 then           -- walker
        f.x = f.x + f.d * 0.5
        if solid(f.x + (f.d > 0 and 6 or -1), f.y + 3)
          or not solid(f.x + (f.d > 0 and 6 or -1), f.y + 7) then
          f.d = -f.d
        end
      elseif f.kind == 2 then       -- hopper: waits, then leaps at you
        f.vy = (f.vy or 0) + GRAV
        if f.grounded == nil then f.grounded = true end
        if f.grounded and f.t % 55 == 0 then
          f.vy = -3.4
          f.d = px < f.x and -1 or 1
          f.grounded = false
        end
        if not f.grounded then f.x = f.x + f.d * 1.1 end
        local nyf = f.y + f.vy
        if f.vy >= 0 and solid(f.x + 3, nyf + 7) then
          f.y = flr((nyf + 7) / TILE) * TILE - 7
          f.vy = 0
          f.grounded = true
        else
          f.y = nyf
          f.grounded = false
        end
        if f.y > 165 then table.remove(foes, i) end
      else                          -- flyer: bobbing patrol at head height
        f.base = f.base or (GROUND - 4) * TILE
        f.x = f.x + f.d * 0.8
        f.y = f.base + math.sin(f.t * 0.08) * 8
        if f.t % 90 == 0 then f.d = -f.d end
      end

      if foes[i] == f and px + PW > f.x and px < f.x + 6
        and py + PH > f.y and py < f.y + 6 then
        if vy > 0 and py + PH - vy <= f.y + 3 then
          kill_foe(i)
          vy = JUMP * 0.7
          coins = coins + 1
        else
          die()
          return
        end
      end
    end
  end

  for i = #bits, 1, -1 do
    local b = bits[i]
    b.x, b.y, b.life = b.x + b.dx, b.y + b.dy, b.life - 1
    b.dy = b.dy + 0.11
    if b.life <= 0 then table.remove(bits, i) end
  end

  if py > 160 then die() return end

  -- the beacon
  if col >= goalcol + 2 then
    done, donewait = true, 40
    sfx(6)
    score(points() + 100)
    if points() + 100 > best then best = points() + 100 end
    return
  end

  if px - camx > 86 then camx = px - 86 end
  generate_to(flr(camx / TILE) + 34)
  local dropcol = flr(camx / TILE) - 4
  if world[dropcol] then world[dropcol], coinat[dropcol] = nil, nil end
  score(points())
end

-- ── how it looks ────────────────────────────────────────────────────────────

local function draw_runner(sx, sy, c)
  rect(sx + 1, sy, 5, 4, c)
  rect(sx + 1, sy + 1, 4, 1, 0)
  pset(sx + (face > 0 and 4 or 1), sy + 1, 6)
  rect(sx + 1, sy + 4, 5, 4, c)
  pset(sx + 3, sy + 6, elem > 0 and ELEMC[elem] or 6)
  if not onground then
    rect(sx, sy + 8, 2, 1, c) rect(sx + 4, sy + 8, 2, 1, c)
  elseif vx ~= 0 and flr(tick / 4) % 2 == 0 then
    rect(sx, sy + 8, 2, 1, c) rect(sx + 4, sy + 8, 1, 1, c)
  else
    rect(sx + 1, sy + 8, 1, 1, c) rect(sx + 4, sy + 8, 1, 1, c)
  end
end

-- The classical triangles, seven pixels wide. Fire and air point up, water and
-- earth point down; air and earth carry the bar.
local function draw_element(kind, x, y)
  local c = ELEMC[kind]
  if kind == 1 or kind == 4 then
    line(x + 3, y, x, y + 6, c) line(x + 3, y, x + 6, y + 6, c) line(x, y + 6, x + 6, y + 6, c)
    if kind == 4 then line(x + 1, y + 4, x + 5, y + 4, c) end
  else
    line(x, y, x + 6, y, c) line(x, y, x + 3, y + 6, c) line(x + 6, y, x + 3, y + 6, c)
    if kind == 3 then line(x + 1, y + 2, x + 5, y + 2, c) end
  end
end

local function draw_foe(f, ox)
  local sx, sy = flr(f.x) - ox, flr(f.y)
  if sx < -8 or sx > 240 then return end
  if f.kind == 1 then
    rect(sx, sy + 1, 6, 5, 3)
    pset(sx + 1, sy + 2, 0) pset(sx + 4, sy + 2, 0)
    rect(sx, sy + 6, 6, 1, flr(tick / 5) % 2 == 0 and 3 or 1)
  elseif f.kind == 2 then
    rect(sx, sy + 2, 6, 5, 5)
    pset(sx + 1, sy + 3, 0) pset(sx + 4, sy + 3, 0)
    if f.grounded then rect(sx + 1, sy + 7, 4, 1, 5) end
  else
    rect(sx + 1, sy + 2, 4, 3, 6)
    pset(sx + 2, sy + 3, 0)
    local w = flr(tick / 4) % 2 == 0 and 0 or 1
    rect(sx - 1, sy + 1 + w, 2, 1, 6) rect(sx + 5, sy + 1 + w, 2, 1, 6)
  end
end

function _draw()
  cls(0)
  local ox = flr(camx)

  for i = 0, 17 do
    pset((i * 53 - flr(ox / 3)) % 240, 16 + (i * 37) % 112, 1)
  end

  local first = flr(ox / TILE)
  for c = first, first + 31 do
    local sx = c * TILE - ox
    for r = 0, ROWS - 1 do
      local t = tile(c, r)
      if t > 0 then
        local sy = r * TILE
        rect(sx, sy, TILE, TILE, t == 1 and 1 or 2)
        if tile(c, r - 1) == 0 then line(sx, sy, sx + TILE - 1, sy, 6) end
      end
    end
    local cr = coinat[c]
    if cr then
      local cy = cr * TILE + 3 + (flr(tick / 6) % 2)
      rect(sx + 2, cy, 4, 4, 4) pset(sx + 3, cy + 1, 7)
    end
    -- the beacon at the end of the level
    if c == goalcol + 2 then
      rect(sx + 2, 40, 2, GROUND * TILE - 40, 7)
      local gl = flr(tick / 4) % 2 == 0 and 4 or 5
      circ(sx + 3, 38, 3, gl)
    end
  end

  for i = 1, #drops do
    local d = drops[i]
    if flr(d.t / 4) % 4 ~= 3 or d.t < 480 then
      draw_element(d.kind, flr(d.x) - ox, flr(d.y))
    end
  end
  for i = 1, #foes do draw_foe(foes[i], ox) end
  for i = 1, #shots do
    local s = shots[i]
    local w = s.big and 5 or 3
    rect(flr(s.x) - ox, flr(s.y), w, s.big and 4 or 2, ELEMC[s.kind])
  end
  for i = 1, #bits do
    local b = bits[i]
    pset(flr(b.x) - ox, flr(b.y), b.life > 4 and 7 or b.c)
  end

  draw_runner(flr(px) - ox, flr(py), dead and 2 or 7)

  rect(0, 0, 240, 14, 0)
  line(0, 14, 239, 14, 1)
  print(stage .. "-" .. lvl, 2, 3, 7)
  local secs = flr(timer / 30)
  print(secs .. "S", 30, 3, secs <= 5 and 2 or 6)
  print("O " .. coins, 60, 3, 4)
  if elem > 0 then
    draw_element(elem, 110, 3)
    print(ELEMN[elem], 120, 4, ELEMC[elem])
  end
  print(points() .. "", 210, 3, 5)

  if dead then
    rect(76, 67, 88, 26, 0)
    rectb(76, 67, 88, 26, 2)
    print(timer <= 0 and "OUT OF TIME" or "THE PIT KEEPS IT",
      timer <= 0 and 98 or 86, 73, 2)
    print("O RETRY " .. stage .. "-" .. lvl, 98, 83, 3)
  elseif done then
    rect(80, 69, 80, 22, 0)
    rectb(80, 69, 80, 22, 5)
    print("LEVEL CLEAR", 98, 75, 5)
  end
end

function _cover()
  cls(0)
  for i = 0, 19 do pset((i * 43) % 240, 12 + (i * 29) % 70, 1) end
  for c = 0, 29 do
    local sx = c * 8
    if c < 13 or c > 16 then
      rect(sx, 100, 8, 24, 1)
      line(sx, 100, sx + 7, 100, 6)
    end
  end
  rect(100, 64, 32, 8, 2)
  line(100, 64, 131, 64, 6)
  draw_element(1, 30, 52) draw_element(2, 48, 52)
  draw_element(3, 30, 68) draw_element(4, 48, 68)
  rect(202, 46, 3, 54, 7) circ(203, 43, 4, 4)
  face, onground, vx, tick, elem = 1, false, 1, 0, 0
  draw_runner(112, 78, 7)
  rect(0, 124, 240, 36, 0)
  print("PIXIEL", 72, 132, 6, 4)
end
