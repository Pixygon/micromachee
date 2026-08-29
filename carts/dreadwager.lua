-- title: Dreadwager
-- author: pixygon
-- about: walk Limbo, empty the mag, take the cliff

-- The second pearl, at 240 by 160. You are a broken Pixiel in Limbo — the
-- planet's corrupted recycling bin — and "respawn" is the recycler's curse: a
-- deletion that never completes.
--
-- Limbo is bigger than the screen: GRASS, SWAMP, ASH and BOG in blotches you
-- walk between, the camera trailing you. The far edges are the recycler's
-- containment — a WALL along the north, sheer CLIFFS on the other three. None
-- of those is THE cliff. THE cliff opens somewhere on its own schedule, holds a
-- few seconds, and closes; step into it and you keep every spark, level and
-- skill, but you are one LAYER deeper and the horde grows.
--
-- Sparks are reclaimed compute, and they are literally the levels: enough of
-- them and the run pauses to offer THREE SKILLS, pick one, go again. Move to
-- aim, hold X to empty the magazine — a shot shoves you, and an empty magazine
-- snaps a fresh one in. O dashes.

local PW = 6
local HITCOOL = 30
local DASH = 9

local WORLD = 480                 -- 2x3 screens of Limbo
local BW = 8                      -- how thick the edge wall / cliffs read
local HUDH = 16
local CELL = 32
local GRID = WORLD / CELL         -- 12x12 biome cells

-- the skill pool: name, blurb, max stacks. A level-up deals three distinct ones.
local POOL = {
  { "SHARD", "one more shot", 2 },
  { "RAPID", "fire faster", 3 },
  { "SWIFT", "move faster", 3 },
  { "VIGOR", "+1 heart, heal", 3 },
  { "REACH", "sparks come far", 2 },
  { "PIERCE", "shots pass thru", 2 },
  { "SPUR", "dash more often", 2 },
  { "DRUM", "bigger magazine", 2 },
  { "CRANK", "reload faster", 2 },
  { "THORN", "touch burns them", 2 },
  { "LEECH", "kills may heal", 3 },
  { "GUARD", "a ward absorbs", 2 },
}

-- name, dark base fill, speck colour, and how much it slows a walker.
local BIOMES = {
  { "GRASS", 0, 5, 1.0 },
  { "SWAMP", 1, 6, 0.55 },
  { "ASH",   0, 1, 1.0 },
  { "BOG",   1, 3, 0.72 },
}

local px, py, aimx, aimy, dashleft, dashcool, hp, maxhp, hitcool
local foes, shots, sparks, bits, shake
local ammo, reload, reloadmax, fireslow, cool
local shield, guardt
local taken, level, nextlvl, tick, spawn
local cliff, cx, cy, clifft, cliffnext
local layer, dead, best
local choosing, choices, choosesel
local sk, map

-- ── skills → effective stats ─────────────────────────────────────────────────
local function stacks(name) return sk[name] or 0 end
local function guns() return 1 + stacks("SHARD") end
local function firecool() return mid(3, 10 - stacks("RAPID") * 2, 10) end
local function speed() return 2.0 + stacks("SWIFT") * 0.35 end
local function magnet() return 32 + stacks("REACH") * 16 end
local function pierce() return stacks("PIERCE") end
local function dashcool_max() return 42 - stacks("SPUR") * 9 end
local function magsize() return 6 + stacks("DRUM") * 3 end
local function reload_len() return mid(10, 28 - stacks("CRANK") * 6, 28) end
local function guard_len() return 260 - stacks("GUARD") * 50 end

-- ── the biomes ───────────────────────────────────────────────────────────────
local function mapget(gx, gy)
  gx = mid(0, gx, GRID - 1)
  gy = mid(0, gy, GRID - 1)
  return map[gy * GRID + gx] or 1
end

local function biome_at(wx, wy)
  return BIOMES[mapget(flr(wx / CELL), flr(wy / CELL))]
end

local function grow_map()
  -- a handful of seeds, each cell painted the nearest seed's biome: blotches,
  -- not static. Fresh every run, so no two descents look the same.
  local seeds = {}
  for _ = 1, 12 do
    seeds[#seeds + 1] = { flr(rnd(GRID)), flr(rnd(GRID)), 1 + flr(rnd(#BIOMES)) }
  end
  map = {}
  for gy = 0, GRID - 1 do
    for gx = 0, GRID - 1 do
      local bd, bi = 1e9, 1
      for _, s in ipairs(seeds) do
        local dd = (gx - s[1]) ^ 2 + (gy - s[2]) ^ 2
        if dd < bd then bd, bi = dd, s[3] end
      end
      map[gy * GRID + gx] = bi
    end
  end
end

-- ── the horde ────────────────────────────────────────────────────────────────
local KINDS = {
  { hp = 2, sp = 0.55, w = 6, col = 2, drop = 1 },   -- 1 husk, the baseline
  { hp = 1, sp = 0.98, w = 5, col = 3, drop = 1 },   -- 2 wisp, quick and thin
  { hp = 5, sp = 0.34, w = 9, col = 6, drop = 2 },   -- 3 maw, slow and thick
  { hp = 3, sp = 0.5, w = 6, col = 4, drop = 2 },    -- 4 charger, lunges
  { hp = 4, sp = 0.4, w = 8, col = 5, drop = 2 },    -- 5 splitter, halves on death
}

local function send()
  -- off-screen but inside the world: on a ring around you, then clamped in.
  local ang, dist = rnd(6.29), 150 + rnd(60)
  local x = mid(BW, px + math.cos(ang) * dist, WORLD - BW)
  local y = mid(BW, py + math.sin(ang) * dist, WORLD - BW)

  local avail = 1
  if taken > 8 or layer > 1 then avail = 2 end
  if taken > 20 or layer > 1 then avail = 3 end
  if layer >= 2 then avail = 4 end
  if layer >= 3 then avail = 5 end
  local kind = 1 + flr(rnd(avail))
  local k = KINDS[kind]
  local tough = 1 + flr((layer - 1) / 2)
  foes[#foes + 1] = {
    x = x, y = y, kind = kind, hp = k.hp + tough - 1,
    sp = k.sp * (0.85 + rnd(0.3)), w = k.w, col = k.col, drop = k.drop,
    t = flr(rnd(60)), small = false,
  }
end

local function spawn_small(f)
  for _ = 1, 2 do
    foes[#foes + 1] = {
      x = f.x + rnd(6) - 3, y = f.y + rnd(6) - 3, kind = 2, hp = 1,
      sp = 1.0, w = 4, col = 3, drop = 1, t = 0, small = true,
    }
  end
end

local function maxfoes() return 60 + layer * 14 end
local function spawn_gap() return mid(4, 34 - flr(tick / 90) - layer * 3, 34) end

local function burst(x, y, n, c)
  for _ = 1, n do
    bits[#bits + 1] = { x = x, y = y, dx = rnd(3) - 1.5, dy = rnd(3) - 1.5,
      life = 6 + flr(rnd(9)), c = c }
  end
end

-- One shot, and the shove it costs. Only ever called on a held X with rounds in
-- the magazine; when it empties the last one, it racks a fresh magazine.
local function fire()
  cool = firecool()
  fireslow = 7                                 -- the recoil that slows you
  ammo = ammo - 1
  local x, y = px + PW / 2, py + PW / 2
  local g, p = guns(), pierce()
  if g >= 3 then
    shots[#shots + 1] = { x = x, y = y, dx = aimx * 4, dy = aimy * 4, pierce = p }
    shots[#shots + 1] = { x = x, y = y, dx = aimx * 4 - aimy * 1.1, dy = aimy * 4 + aimx * 1.1, pierce = p }
    shots[#shots + 1] = { x = x, y = y, dx = aimx * 4 + aimy * 1.1, dy = aimy * 4 - aimx * 1.1, pierce = p }
  elseif g == 2 then
    shots[#shots + 1] = { x = x - aimy * 2, y = y + aimx * 2, dx = aimx * 4, dy = aimy * 4, pierce = p }
    shots[#shots + 1] = { x = x + aimy * 2, y = y - aimx * 2, dx = aimx * 4, dy = aimy * 4, pierce = p }
  else
    shots[#shots + 1] = { x = x, y = y, dx = aimx * 4, dy = aimy * 4, pierce = p }
  end
  sfx(4)
  if ammo <= 0 then reload, reloadmax = reload_len(), reload_len() sfx(0) end
end

-- A foe reaching zero, from a shot or from THORN: it drops, it may heal you,
-- and a splitter halves. One place, so both callers agree.
local function kill_foe(f, j)
  for _ = 1, f.drop do
    sparks[#sparks + 1] = { x = f.x + rnd(6) - 3, y = f.y + rnd(6) - 3, t = 0 }
  end
  burst(f.x, f.y, 4, f.col)
  sfx(1)
  if stacks("LEECH") > 0 and rnd(1) < stacks("LEECH") * 0.06 then hp = mid(0, hp + 1, maxhp) end
  if f.kind == 5 and not f.small then spawn_small(f) end
  table.remove(foes, j)
end

-- ── level-ups ────────────────────────────────────────────────────────────────
local function level_cost() return 6 + level * 6 end

local function offer_skills()
  local avail = {}
  for i = 1, #POOL do
    if stacks(POOL[i][1]) < POOL[i][3] then avail[#avail + 1] = i end
  end
  choices = {}
  for _ = 1, 3 do
    if #avail == 0 then break end
    local pick = flr(rnd(#avail)) + 1
    choices[#choices + 1] = avail[pick]
    table.remove(avail, pick)
  end
  if #choices > 0 then choosing, choosesel = true, 1 sfx(6) end
end

local function take_skill(idx)
  local name = POOL[idx][1]
  sk[name] = stacks(name) + 1
  if name == "VIGOR" then maxhp = maxhp + 1 hp = maxhp end
  if name == "DRUM" then ammo = magsize() end
  choosing = false
  sfx(3)
end

-- ── THE cliff, as a descent ─────────────────────────────────────────────────
local function open_cliff()
  cliff, clifft = true, 150               -- five seconds, then it closes
  sfx(2)
  repeat
    cx, cy = 40 + rnd(WORLD - 80), 40 + rnd(WORLD - 80)
  until (cx - px) ^ 2 + (cy - py) ^ 2 > 3600
end

local function descend()
  layer = layer + 1
  cliff = false
  cliffnext = 220 + flr(rnd(220))
  foes, shots = {}, {}
  hp = mid(0, hp + 1, maxhp)
  ammo, reload = magsize(), 0
  burst(px + 3, py + 3, 24, 6)
  shake = 10
  sfx(6)
end

-- ── the run ──────────────────────────────────────────────────────────────────
local function reset()
  sk = {}                              -- before any stacks()-reading helper runs
  grow_map()
  px, py = WORLD / 2, WORLD / 2
  aimx, aimy = 0, -1
  dashleft, dashcool = 0, 0
  maxhp, hp, hitcool = 3, 3, 0
  foes, shots, sparks, bits, shake = {}, {}, {}, {}, 0
  cool, taken, level, tick = 0, 0, 1, 0
  fireslow = 0
  shield, guardt = false, guard_len()
  nextlvl = level_cost()
  spawn = 40
  cliff, cx, cy, clifft = false, 0, 0, 0
  cliffnext = 260 + flr(rnd(200))
  layer, dead = 1, false
  choosing, choices, choosesel = false, {}, 1
  ammo, reload, reloadmax = magsize(), 0, 1
end

function _init()
  reset()
  best = best or 0
  score(0)
end

local function drift()
  dead = true
  shake = 12
  burst(px + 3, py + 3, 20, 2)
  sfx(7)
  lose()
end

local function run_score() return taken + (layer - 1) * 25 end

function _update()
  if dead then
    if btnp(4) then reset() score(0) end
    return
  end

  if choosing then
    -- vertical list, so up/down are the natural keys; left/right work too.
    if btnp(0) or btnp(2) then choosesel = (choosesel - 2) % #choices + 1 sfx(0) end
    if btnp(1) or btnp(3) then choosesel = choosesel % #choices + 1 sfx(0) end
    if btnp(4) then take_skill(choices[choosesel]) end
    return
  end

  tick = tick + 1
  if shake > 0 then shake = shake - 1 end
  for i = #bits, 1, -1 do
    local b = bits[i]
    b.x, b.y, b.life = b.x + b.dx * 0.8, b.y + b.dy * 0.8, b.life - 1
    if b.life <= 0 then table.remove(bits, i) end
  end

  -- ── moving, and therefore aiming ──────────────────────────────────────────
  local mx, my = 0, 0
  if btn(0) then mx = mx - 1 end
  if btn(1) then mx = mx + 1 end
  if btn(2) then my = my - 1 end
  if btn(3) then my = my + 1 end
  if mx ~= 0 or my ~= 0 then
    local len = math.sqrt(mx * mx + my * my)
    mx, my = mx / len, my / len
    aimx, aimy = mx, my
  end

  if dashcool > 0 then dashcool = dashcool - 1 end
  if btnp(4) and dashcool <= 0 and (mx ~= 0 or my ~= 0) then
    dashleft, dashcool = DASH, dashcool_max()
  end
  local sp = speed() * biome_at(px + 3, py + 3)[4]
  if fireslow > 0 then fireslow = fireslow - 1 sp = sp * 0.5 end
  if dashleft > 0 then dashleft = dashleft - 1 sp = speed() * 2.6 end   -- a dash shrugs slows off
  -- clamped to the walkable world; the edge bands (BW) are the wall and cliffs.
  px = mid(BW, px + mx * sp, WORLD - BW - PW)
  py = mid(BW, py + my * sp, WORLD - BW - PW)

  -- ── firing, and reloading ─────────────────────────────────────────────────
  if cool > 0 then cool = cool - 1 end
  if hitcool > 0 then hitcool = hitcool - 1 end
  if reload > 0 then
    reload = reload - 1
    if reload <= 0 then ammo = magsize() sfx(3) end
  elseif btn(5) and cool <= 0 and ammo > 0 then
    fire()
  end

  -- the ward recharges only while it is down
  if stacks("GUARD") > 0 and not shield then
    guardt = guardt - 1
    if guardt <= 0 then shield = true end
  end

  -- ── THE cliff ─────────────────────────────────────────────────────────────
  cliffnext = cliffnext - 1
  if not cliff and cliffnext <= 0 then open_cliff() end
  if cliff then
    clifft = clifft - 1
    if clifft <= 0 then
      cliff = false
      cliffnext = 220 + flr(rnd(220))
    elseif (px + 3 - cx) ^ 2 + (py + 3 - cy) ^ 2 < 120 then
      descend() return                     -- walk into it; no button needed
    end
  end

  -- ── them ──────────────────────────────────────────────────────────────────
  spawn = spawn - 1
  if spawn <= 0 and #foes < maxfoes() then send() spawn = spawn_gap() end

  for i = #foes, 1, -1 do
    local f = foes[i]
    local dx, dy = px + 3 - f.x, py + 3 - f.y
    local d = math.sqrt(dx * dx + dy * dy)
    local move = f.sp
    if f.kind == 4 then
      f.t = f.t + 1
      if d < 60 and f.t % 70 < 16 then move = f.sp * 3.4 end
    end
    if d > 0.5 then
      f.x = f.x + dx / d * move
      f.y = f.y + dy / d * move
    end
    if d < f.w and hitcool <= 0 and dashleft <= 0 then
      local th = stacks("THORN")
      if th > 0 then
        f.hp = f.hp - th
        burst(f.x, f.y, 3, 4)
        if f.hp <= 0 then kill_foe(f, i) end
      end
      if shield then
        shield, guardt = false, guard_len()
        hitcool = HITCOOL
        burst(px + 3, py + 3, 10, 6)
        sfx(2)
      else
        hp = hp - 1
        hitcool = HITCOOL
        shake = 7
        burst(px + 3, py + 3, 8, 7)
        sfx(5)
        if hp <= 0 then drift() return end
      end
    end
  end

  -- ── yours ─────────────────────────────────────────────────────────────────
  for i = #shots, 1, -1 do
    local s = shots[i]
    s.x, s.y = s.x + s.dx, s.y + s.dy
    if s.x < -4 or s.x > WORLD + 4 or s.y < -4 or s.y > WORLD + 4 then
      table.remove(shots, i)
    else
      for j = #foes, 1, -1 do
        local f = foes[j]
        if math.abs(s.x - f.x) < f.w and math.abs(s.y - f.y) < f.w then
          f.hp = f.hp - 1
          if f.hp <= 0 then kill_foe(f, j) end
          if s.pierce > 0 then s.pierce = s.pierce - 1
          else table.remove(shots, i) break end
        end
      end
    end
  end

  -- ── sparks ────────────────────────────────────────────────────────────────
  local mrange = magnet()
  for i = #sparks, 1, -1 do
    local s = sparks[i]
    s.t = s.t + 1
    local dx, dy = px + 3 - s.x, py + 3 - s.y
    local d = math.sqrt(dx * dx + dy * dy)
    if d < mrange and d > 0 then
      local pull = mid(0.6, 3.6 - d / 12, 3.6)
      s.x, s.y = s.x + dx / d * pull, s.y + dy / d * pull
    end
    if d < 6 then
      table.remove(sparks, i)
      taken = taken + 1
      score(run_score())
      sfx(3)
      if run_score() > best then best = run_score() end
      if taken >= nextlvl then
        level = level + 1
        nextlvl = nextlvl + level_cost()
        offer_skills()
      end
    elseif s.t > 900 then
      table.remove(sparks, i)
    end
  end
end

-- ── how it looks ─────────────────────────────────────────────────────────────
local ox, oy = 0, 0                          -- the camera, set each frame

local function draw_pixiel(x, y, c)
  rect(x + 1, y, 4, 3, c)
  rect(x + 1, y + 1, 3, 1, 0)
  pset(x + 1 + (aimx >= 0 and 2 or 0), y + 1, 6)
  rect(x, y + 3, 6, 3, c)
  pset(x + 2, y + 4, 6)
end

local function draw_foe(f)
  local x, y = flr(f.x - ox), flr(f.y - oy)
  local k = f.kind
  if k == 3 then
    rect(x - 4, y - 4, 9, 9, 6) rect(x - 2, y - 2, 5, 5, 0)
    pset(x - 1, y - 1, 6) pset(x + 1, y - 1, 6)
  elseif k == 2 then
    rect(x - 2, y - 2, 5, 5, 3) pset(x - 1, y, 0) pset(x + 1, y, 0)
  elseif k == 4 then
    rect(x - 3, y - 3, 7, 6, 4) rect(x - 4, y - 1, 1, 2, 4) rect(x + 4, y - 1, 1, 2, 4)
    pset(x - 1, y - 1, 0) pset(x + 1, y - 1, 0)
  elseif k == 5 then
    rect(x - 3, y - 3, 7, 7, 5) rect(x, y - 3, 1, 7, 0)
    pset(x - 2, y - 1, 0) pset(x + 2, y - 1, 0)
  else
    rect(x - 3, y - 3, 6, 6, 2) pset(x - 1, y - 1, 0) pset(x + 1, y - 1, 0)
  end
end

-- the ground: each visible biome cell, filled dark with a stable speck pattern
-- so the blotches read as GRASS / SWAMP / ASH / BOG without ever flickering.
local function draw_ground()
  cls(0)
  local gx0, gx1 = flr(ox / CELL), flr((ox + 240) / CELL)
  local gy0, gy1 = flr(oy / CELL), flr((oy + 160) / CELL)
  for gy = gy0, gy1 do
    for gx = gx0, gx1 do
      local b = BIOMES[mapget(gx, gy)]
      local rx, ry = gx * CELL - ox, gy * CELL - oy
      rect(rx, ry, CELL, CELL, b[2])
      for k = 0, 5 do
        pset(rx + (gx * 7 + k * 13) % CELL, ry + (gy * 11 + k * 17) % CELL, b[3])
      end
    end
  end
end

-- the containment: a built WALL along the north world edge, sheer CLIFFS on the
-- other three. Both stop you; only the look and the lore differ, and neither is
-- THE cliff.
local function draw_edges()
  local n, s = 0 - oy, WORLD - oy        -- screen y of world top / bottom
  local w, e = 0 - ox, WORLD - ox        -- screen x of world left / right
  if w + BW > 0 and w < 240 then
    rect(w, 0, BW, 160, 0) line(w + BW, 0, w + BW, 159, 1)
    for yy = 0, 159, 6 do pset(w + BW - 2, yy, 1) end
  end
  if e - BW < 240 and e > 0 then
    rect(e - BW, 0, BW, 160, 0) line(e - BW, 0, e - BW, 159, 1)
    for yy = 0, 159, 6 do pset(e - BW + 1, yy, 1) end
  end
  if s - BW < 160 and s > 0 then
    rect(0, s - BW, 240, BW, 0) line(0, s - BW, 239, s - BW, 1)
    for xx = 0, 239, 6 do pset(xx, s - BW + 1, 1) end
  end
  -- north wall: solid, filled to the top so the HUD sits on its crown, with a
  -- bright cap line and mortar ticks set in world space.
  if n + BW > 0 and n < 160 then
    rect(0, 0, 240, n + BW, 1) line(0, n + BW, 239, n + BW, 6)
    for wx = 0, WORLD, 8 do
      local sxp = wx - ox
      if sxp >= 0 and sxp < 240 then line(sxp, math.max(0, n), sxp, n + BW - 1, 6) end
    end
  end
end

local function draw_choose()
  rect(50, 36, 140, 88, 0)
  rectb(50, 36, 140, 88, 6)
  print("A LEVEL. CHOOSE.", 88, 40, 5)
  print("UP DOWN  O TAKES", 88, 114, 1)
  for i = 1, #choices do
    local p = POOL[choices[i]]
    local y = 52 + (i - 1) * 18
    if i == choosesel then rect(54, y - 2, 132, 15, 1) end
    local have = stacks(p[1])
    print(p[1], 58, y, i == choosesel and 4 or 7)
    if have > 0 then print("x" .. have, 58, y + 6, 6) end
    print(p[2], 100, y + 3, i == choosesel and 7 or 1)
  end
end

function _draw()
  -- the camera trails you, stopping at the world's edges so the bands show.
  ox = mid(0, flr(px + 3 - 120), WORLD - 240)
  -- the vertical clamp can lift a little ABOVE the world so the north wall
  -- clears the 16px HUD instead of hiding behind it.
  oy = mid(-24, flr(py + 3 - 88), WORLD - 160)
  if shake > 0 then ox = ox + flr(rnd(3)) - 1 oy = oy + flr(rnd(3)) - 1 end

  draw_ground()
  draw_edges()

  if cliff then
    local closing = clifft < 40 and flr(clifft / 4) % 2 == 0
    local r = 10 + flr(math.sin(tick * 0.09) * 2)
    local scx, scy = flr(cx - ox), flr(cy - oy)
    circ(scx, scy, r, 0)
    circb(scx, scy, r, closing and 2 or 1)
    circb(scx, scy, r - 3, 1)
    local near = (px + 3 - cx) ^ 2 + (py + 3 - cy) ^ 2 < 900
    if near then
      circb(scx, scy, r, 7)
      local t = "THE CLIFF"
      print(t, mid(2, scx - #t * 2, 238 - #t * 4), mid(HUDH + 2, scy - r - 9, 150), 7)
    end
  end

  for i = 1, #sparks do
    local s = sparks[i]
    local c = flr(s.t / 3) % 2 == 0 and 5 or 7
    rect(flr(s.x - ox) - 1, flr(s.y - oy) - 1, 3, 3, c)
  end
  for i = 1, #foes do draw_foe(foes[i]) end
  for i = 1, #bits do
    local b = bits[i]
    pset(flr(b.x - ox), flr(b.y - oy), b.life > 6 and 7 or b.c)
  end
  for i = 1, #shots do
    local s = shots[i]
    rect(flr(s.x - ox) - 1, flr(s.y - oy) - 1, 2, 2, 4)
  end

  if not dead and (hitcool == 0 or flr(hitcool / 3) % 2 == 0) then
    local sxp, syp = flr(px - ox), flr(py - oy)
    if shield then circb(sxp + 3, syp + 3, 6, 6) end
    draw_pixiel(sxp, syp, dashleft > 0 and 4 or 7)
  end

  -- ── the panel (two rows) ──────────────────────────────────────────────────
  rect(0, 0, 240, HUDH, 0)
  line(0, HUDH, 239, HUDH, 1)
  print("SPARKS " .. taken, 2, 2, 5)
  for i = 1, maxhp do
    rect(238 - maxhp * 5 + (i - 1) * 5, 2, 3, 4, i <= hp and 2 or 1)
  end
  -- row two: the magazine on the left, layer and level on the right
  if reload > 0 then
    rect(2, 10, flr(80 * (1 - reload / reloadmax)), 4, 3)
    rectb(2, 10, 80, 4, 1)
  else
    for i = 1, magsize() do
      rect(2 + (i - 1) * 3, 10, 2, 4, i <= ammo and 4 or 1)
    end
  end
  print("L" .. layer, 204, 10, 6)
  print("LV" .. level, 218, 10, 4)

  if choosing then draw_choose() end

  if dead then
    rect(58, 57, 124, 46, 0)
    rectb(58, 57, 124, 46, 2)
    print("YOU DRIFTED", 98, 63, 2)
    local s2 = "LAYER " .. layer .. "  SPARKS " .. taken
    print(s2, (240 - #s2 * 4) / 2, 73, 7)
    print("DELETION NEVER COMPLETES", 72, 83, 1)
    print("O AGAIN", 106, 93, 3)
  end
end

function _cover()
  cls(0)
  for i = 0, 35 do pset((i * 43 + 11) % 240, 6 + (i * 71) % 108, 1) end
  circ(196, 32, 15, 0) circb(196, 32, 15, 1) circb(196, 32, 11, 1)
  local ring = { { 26, 26 }, { 74, 14 }, { 148, 78 }, { 22, 84 }, { 62, 102 },
    { 128, 108 }, { 174, 92 }, { 14, 52 }, { 210, 70 }, { 226, 104 },
    { 100, 18 }, { 158, 22 } }
  for i = 1, #ring do
    local x, y = ring[i][1], ring[i][2]
    rect(x - 3, y - 3, 7, 7, 2) pset(x - 1, y - 1, 0) pset(x + 1, y - 1, 0)
  end
  rect(140, 44, 5, 5, 3)
  rect(52, 62, 9, 9, 6) rect(54, 64, 5, 5, 0) pset(55, 66, 6) pset(57, 66, 6)
  for i = 0, 3 do rect(116, 40 - i * 6, 3, 3, 4) end
  rect(104, 60, 4, 4, 5) rect(134, 70, 4, 4, 5)
  rect(104, 54, 16, 8, 7) rect(106, 46, 12, 8, 7) rect(106, 48, 9, 3, 0)
  rect(114, 48, 3, 3, 6) rect(110, 56, 4, 4, 6)
  rect(0, 120, 240, 40, 0)
  print("DREADWAGER", 40, 130, 2, 4)
end
