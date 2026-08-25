-- title: Dreadwager
-- author: pixygon
-- about: the horde, the sparks, and the cliff that opens

-- The second pearl, at 128 by 128. You are a broken Pixiel in Limbo — the
-- planet's corrupted recycling bin — and "respawn" is the recycler's curse: a
-- deletion that never completes.
--
-- Sparks are reclaimed compute, and they are literally the levels: enough of
-- them and the run pauses to offer THREE SKILLS, pick one, go again. The pool
-- stacks, so every run builds a different machine out of the same parts.
--
-- The cliff is not an exit any more. It opens somewhere in Limbo on its own
-- schedule, stays a few seconds, and closes; step through and you keep every
-- spark, level and skill — but you are one LAYER deeper, and the recycler sends
-- more of everything after you. Down is the only direction that counts.

local PW = 6
local HITCOOL = 30
local DASH = 9

-- the skill pool: name, blurb, max stacks. A level-up deals three distinct ones.
local POOL = {
  { "SHARD", "one more shot", 2 },
  { "RAPID", "fire faster", 3 },
  { "SWIFT", "move faster", 3 },
  { "VIGOR", "+1 heart, heal", 3 },
  { "REACH", "sparks come far", 2 },
  { "PIERCE", "shots pass thru", 2 },
  { "SPUR", "dash more often", 2 },
}

local px, py, aimx, aimy, dashleft, dashcool, hp, maxhp, hitcool
local foes, shots, sparks, bits, shake
local cool, taken, level, nextlvl, tick, spawn
local cliff, cx, cy, clifft, cliffnext
local layer, dead, best
local choosing, choices, choosesel
local sk

-- ── skills → effective stats ─────────────────────────────────────────────────
local function stacks(name) return sk[name] or 0 end
local function guns() return 1 + stacks("SHARD") end
local function firecool() return mid(3, 10 - stacks("RAPID") * 2, 10) end
local function speed() return 1.6 + stacks("SWIFT") * 0.28 end
local function magnet() return 32 + stacks("REACH") * 16 end
local function pierce() return stacks("PIERCE") end
local function dashcool_max() return 42 - stacks("SPUR") * 9 end

-- ── the horde ────────────────────────────────────────────────────────────────

-- name, hp, speed, half-width, colour, and the sparks it drops when it dies.
-- The variety and toughness grow with the layer, not just the spark count.
local KINDS = {
  { hp = 2, sp = 0.55, w = 6, col = 2, drop = 1 },   -- 1 husk, the baseline
  { hp = 1, sp = 0.98, w = 5, col = 3, drop = 1 },   -- 2 wisp, quick and thin
  { hp = 5, sp = 0.34, w = 9, col = 6, drop = 2 },   -- 3 maw, slow and thick
  { hp = 3, sp = 0.5, w = 6, col = 4, drop = 2 },    -- 4 charger, lunges
  { hp = 4, sp = 0.4, w = 8, col = 5, drop = 2 },    -- 5 splitter, halves on death
}

local function send()
  local side = flr(rnd(4))
  local x, y
  if side == 0 then x, y = rnd(128), -8
  elseif side == 1 then x, y = rnd(128), 132
  elseif side == 2 then x, y = -8, rnd(128)
  else x, y = 132, rnd(128) end

  -- Which kinds are loose depends on how deep you are and how far you have come.
  local avail = 1
  if taken > 8 or layer > 1 then avail = 2 end
  if taken > 20 or layer > 1 then avail = 3 end
  if layer >= 2 then avail = 4 end
  if layer >= 3 then avail = 5 end
  local kind = 1 + flr(rnd(avail))
  local k = KINDS[kind]
  local tough = 1 + flr((layer - 1) / 2)         -- deeper things take more hits
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

local function fire()
  if cool > 0 then return end
  cool = firecool()
  local x, y = px + PW / 2, py + PW / 2
  local g = guns()
  local p = pierce()
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
end

local function burst(x, y, n, c)
  for _ = 1, n do
    bits[#bits + 1] = { x = x, y = y, dx = rnd(3) - 1.5, dy = rnd(3) - 1.5,
      life = 6 + flr(rnd(9)), c = c }
  end
end

-- ── level-ups ────────────────────────────────────────────────────────────────
local function level_cost() return 6 + level * 6 end

local function offer_skills()
  -- every distinct skill not yet maxed, then take three at random
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
  if #choices > 0 then
    choosing, choosesel = true, 1
    sfx(6)
  end
end

local function take_skill(idx)
  local name = POOL[idx][1]
  sk[name] = stacks(name) + 1
  if name == "VIGOR" then maxhp = maxhp + 1 hp = maxhp end
  choosing = false
  sfx(3)
end

-- ── the cliff, as a descent ─────────────────────────────────────────────────
local function open_cliff()
  cliff = true
  clifft = 150                     -- five seconds, then it closes
  sfx(2)
  repeat
    cx, cy = 18 + rnd(92), 26 + rnd(84)
  until (cx - px) ^ 2 + (cy - py) ^ 2 > 1600
end

local function descend()
  layer = layer + 1
  cliff = false
  cliffnext = 220 + flr(rnd(220))
  foes, shots = {}, {}
  hp = mid(0, hp + 1, maxhp)        -- a breath before it gets worse
  burst(px + 3, py + 3, 24, 6)
  shake = 10
  sfx(6)
end

-- ── the run ──────────────────────────────────────────────────────────────────
local function reset()
  px, py = 64, 70
  aimx, aimy = 0, -1
  dashleft, dashcool = 0, 0
  maxhp, hp, hitcool = 3, 3, 0
  foes, shots, sparks, bits, shake = {}, {}, {}, {}, 0
  cool, taken, level, tick = 0, 0, 1, 0
  nextlvl = level_cost()
  spawn = 40
  cliff, cx, cy, clifft = false, 0, 0, 0
  cliffnext = 260 + flr(rnd(200))
  layer, dead = 1, false
  choosing, choices, choosesel = false, {}, 1
  sk = {}
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

local function run_score()
  return taken + (layer - 1) * 25
end

function _update()
  if dead then
    if btnp(4) then reset() score(0) end
    return
  end

  -- the level-up pause: everything holds while you choose
  if choosing then
    if btnp(0) then choosesel = (choosesel - 2) % #choices + 1 sfx(0) end
    if btnp(1) then choosesel = choosesel % #choices + 1 sfx(0) end
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
  local sp = speed()
  if dashleft > 0 then dashleft = dashleft - 1 sp = speed() * 2.6 end
  px = mid(0, px + mx * sp, 128 - PW)
  py = mid(10, py + my * sp, 128 - PW)

  if cool > 0 then cool = cool - 1 end
  if hitcool > 0 then hitcool = hitcool - 1 end
  fire()

  -- ── the cliff ─────────────────────────────────────────────────────────────
  cliffnext = cliffnext - 1
  if not cliff and cliffnext <= 0 then open_cliff() end
  if cliff then
    clifft = clifft - 1
    if clifft <= 0 then
      cliff = false
      cliffnext = 220 + flr(rnd(220))
    else
      local d = (px + 3 - cx) ^ 2 + (py + 3 - cy) ^ 2
      if d < 100 and (btnp(5) or d < 40) then descend() return end
    end
  end

  -- ── them ──────────────────────────────────────────────────────────────────
  spawn = spawn - 1
  if spawn <= 0 and #foes < maxfoes() then
    send()
    spawn = spawn_gap()
  end

  for i = #foes, 1, -1 do
    local f = foes[i]
    local dx, dy = px + 3 - f.x, py + 3 - f.y
    local d = math.sqrt(dx * dx + dy * dy)
    local move = f.sp
    if f.kind == 4 then
      -- the charger paces, then lunges when it has lined you up
      f.t = f.t + 1
      if d < 60 and f.t % 70 < 16 then move = f.sp * 3.4 end
    end
    if d > 0.5 then
      f.x = f.x + dx / d * move
      f.y = f.y + dy / d * move
    end
    if d < f.w and hitcool <= 0 and dashleft <= 0 then
      hp = hp - 1
      hitcool = HITCOOL
      shake = 7
      burst(px + 3, py + 3, 8, 7)
      sfx(5)
      if hp <= 0 then drift() return end
    end
  end

  -- ── yours ─────────────────────────────────────────────────────────────────
  for i = #shots, 1, -1 do
    local s = shots[i]
    s.x = s.x + s.dx
    s.y = s.y + s.dy
    if s.x < -4 or s.x > 132 or s.y < 6 or s.y > 132 then
      table.remove(shots, i)
    else
      for j = #foes, 1, -1 do
        local f = foes[j]
        if math.abs(s.x - f.x) < f.w and math.abs(s.y - f.y) < f.w then
          f.hp = f.hp - 1
          if f.hp <= 0 then
            for _ = 1, f.drop do
              sparks[#sparks + 1] = { x = f.x + rnd(6) - 3, y = f.y + rnd(6) - 3, t = 0 }
            end
            burst(f.x, f.y, 4, f.col)
            sfx(1)
            if f.kind == 5 and not f.small then spawn_small(f) end
            table.remove(foes, j)
          end
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
      s.x = s.x + dx / d * pull
      s.y = s.y + dy / d * pull
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

local function draw_pixiel(x, y, c)
  rect(x + 1, y, 4, 3, c)
  rect(x + 1, y + 1, 3, 1, 0)
  pset(x + 1 + (aimx >= 0 and 2 or 0), y + 1, 6)
  rect(x, y + 3, 6, 3, c)
  pset(x + 2, y + 4, 6)
end

local function draw_foe(f)
  local x, y = flr(f.x), flr(f.y)
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

local function draw_choose()
  rect(6, 30, 116, 68, 0)
  rectb(6, 30, 116, 68, 6)
  print("A LEVEL. CHOOSE.", 26, 34, 5)
  for i = 1, #choices do
    local p = POOL[choices[i]]
    local y = 46 + (i - 1) * 16
    if i == choosesel then rect(10, y - 2, 108, 15, 1) end
    local have = stacks(p[1])
    print(p[1], 14, y, i == choosesel and 4 or 7)
    if have > 0 then print("x" .. have, 14, y + 6, 6) end
    print(p[2], 46, y + 2, i == choosesel and 7 or 1)
  end
end

function _draw()
  cls(0)
  for i = 0, 23 do pset((i * 43 + 11) % 128, 12 + (i * 71) % 112, 1) end

  if cliff then
    local closing = clifft < 40 and flr(clifft / 4) % 2 == 0
    local r = 10 + flr(math.sin(tick * 0.09) * 2)
    circ(cx, cy, r, 0)
    circb(cx, cy, r, closing and 2 or 1)
    circb(cx, cy, r - 3, 1)
    local near = (px + 3 - cx) ^ 2 + (py + 3 - cy) ^ 2 < 100
    if near then
      circb(cx, cy, r, 7)
      local t = "X TO DESCEND"
      print(t, mid(2, cx - #t * 2, 126 - #t * 4), mid(12, cy - r - 9, 118), 7)
    end
  end

  for i = 1, #sparks do
    local s = sparks[i]
    local c = flr(s.t / 3) % 2 == 0 and 5 or 7
    rect(flr(s.x) - 1, flr(s.y) - 1, 3, 3, c)
  end
  for i = 1, #foes do draw_foe(foes[i]) end
  for i = 1, #bits do
    local b = bits[i]
    pset(flr(b.x), flr(b.y), b.life > 6 and 7 or b.c)
  end
  for i = 1, #shots do
    local s = shots[i]
    rect(flr(s.x) - 1, flr(s.y) - 1, 2, 2, 4)
  end

  if not dead and (hitcool == 0 or flr(hitcool / 3) % 2 == 0) then
    draw_pixiel(flr(px), flr(py), dashleft > 0 and 4 or 7)
  end

  -- ── the panel ─────────────────────────────────────────────────────────────
  rect(0, 0, 128, 10, 0)
  line(0, 10, 127, 10, 1)
  print("SPARKS " .. taken, 2, 2, 5)
  -- hearts, up to maxhp
  for i = 1, maxhp do
    rect(52 + (i - 1) * 5, 3, 3, 4, i <= hp and 2 or 1)
  end
  print("L" .. layer, 108, 2, 6)
  print("LV" .. level, 118, 2, 4)
  -- a thin bar toward the next level
  local frac = mid(0, (taken - (nextlvl - level_cost())) / level_cost(), 1)
  rect(0, 9, flr(128 * frac), 1, 5)

  if choosing then draw_choose() end

  if dead then
    rect(8, 48, 112, 34, 0)
    rectb(8, 48, 112, 34, 2)
    print("YOU DRIFTED", 40, 54, 2)
    print("LAYER " .. layer .. "  SPARKS " .. taken, 20, 64, 7)
    print("O AGAIN", 72, 72, 3)
    print("DELETION NEVER COMPLETES", 16, 74, 1)
  end
end

function _cover()
  cls(0)
  for i = 0, 19 do pset((i * 43 + 11) % 128, 8 + (i * 71) % 84, 1) end
  circ(98, 26, 11, 0) circb(98, 26, 11, 1) circb(98, 26, 8, 1)
  local ring = { { 20, 20 }, { 52, 12 }, { 84, 62 }, { 18, 58 }, { 44, 78 }, { 76, 84 }, { 104, 70 }, { 12, 38 } }
  for i = 1, #ring do
    local x, y = ring[i][1], ring[i][2]
    rect(x - 3, y - 3, 7, 7, 2) pset(x - 1, y - 1, 0) pset(x + 1, y - 1, 0)
  end
  rect(60, 34, 5, 5, 3)
  rect(30, 46, 9, 9, 6) rect(32, 48, 5, 5, 0) pset(33, 50, 6) pset(35, 50, 6)
  for i = 0, 3 do rect(56, 26 - i * 6, 3, 3, 4) end
  rect(52, 44, 4, 4, 5) rect(70, 52, 4, 4, 5)
  rect(52, 40, 16, 8, 7) rect(54, 32, 12, 8, 7) rect(54, 34, 9, 3, 0)
  rect(62, 34, 3, 3, 6) rect(58, 42, 4, 4, 6)
  rect(0, 96, 128, 32, 0)
  print("DREADWAGER", 4, 104, 2, 3)
end
