-- title: Firekeeper
-- author: pixygon
-- about: hold the light. they come down in ranks

-- The Firekeeper: "protect the dying light with all means possible, ruin the
-- world if necessary. The light is all." So the fire is drawn along the bottom
-- of the screen and it dims with every life, and the ranks coming down are only
-- ever trying to reach it.
--
-- The block of them moves as ONE THING — a single origin, stepped sideways and
-- dropped at the wall — rather than thirty-five things each deciding. That is
-- what makes the whole rank turn at once, and it is why the last one alive
-- still tracks across the full width the way the first thirty-five did.
--
-- The step interval is the difficulty and there is no other: it falls from 24
-- frames to 2 as they die, so a nearly-cleared rank is frantic without a single
-- number anywhere having been called "speed".

local ROWS, COLS = 5, 12
local AW, AH = 8, 6         -- one of them
local SX, SY = 15, 12       -- and the space one takes up
local DROP = 6

local SLOW, FAST = 24, 2    -- frames between steps, full rank to last one

local BUNKERS = 6
local BW, BH = 7, 3         -- blocks across and down, each two pixels square
local BUNKY = 128

local GUNY = 146

local alive, count, bx, by, dir, tick, step, wave
local bits, shake
local px, shot, bombs, bunker
local lives, points, best, dead, hitpause, flash

local function at(r, c) return r * COLS + c + 1 end

-- A rank that simply vanishes when shot reads as a bug. Six pixels thrown
-- outward for a third of a second is the difference between "it is gone" and
-- "you destroyed it", and it costs one table.
local function burst(x, y, n, c)
  for _ = 1, n do
    bits[#bits + 1] = {
      x = x, y = y,
      dx = rnd(2.4) - 1.2, dy = rnd(2.4) - 1.2,
      life = 7 + flr(rnd(7)), c = c,
    }
  end
end

local function build_wave()
  alive, count = {}, ROWS * COLS
  for i = 1, count do alive[i] = true end
  bx = 12
  -- Each wave starts lower than the last, which is the only thing that makes a
  -- cleared screen worse news than it looks.
  by = 16 + mid(0, (wave - 1) * 4, 20)
  dir, tick = 1, 0
end

local function build_bunkers()
  bunker = {}
  for i = 1, BUNKERS do
    local b = {}
    for j = 1, BW * BH do b[j] = true end
    bunker[i] = b
  end
end

function _init()
  wave = 1
  build_wave()
  build_bunkers()
  px = 115
  shot = nil
  bombs = {}
  lives, points, dead, hitpause, flash = 3, 0, false, 0, 0
  bits, shake = {}, 0
  best = best or 0
  score(0)
end

local function bunker_x(i) return 14 + (i - 1) * 38 end

-- ── where the rank is ───────────────────────────────────────────────────────

local function extent()
  local lo, hi = COLS, -1
  for c = 0, COLS - 1 do
    for r = 0, ROWS - 1 do
      if alive[at(r, c)] then
        if c < lo then lo = c end
        if c > hi then hi = c end
        break
      end
    end
  end
  return lo, hi
end

local function lowest_row(c)
  for r = ROWS - 1, 0, -1 do
    if alive[at(r, c)] then return r end
  end
  return -1
end

local function bottom_of_rank()
  for r = ROWS - 1, 0, -1 do
    for c = 0, COLS - 1 do
      if alive[at(r, c)] then return by + r * SY + AH end
    end
  end
  return 0
end

local function value(r)
  if r == 0 then return 30 end
  if r <= 2 then return 20 end
  return 10
end

local function colour_of(r)
  if r == 0 then return 2 end
  if r <= 2 then return 6 end
  return 3
end

local function die()
  dead = true
  shake = 10
  sfx(7)
  lose()
end

-- ── the rank takes a step ───────────────────────────────────────────────────

local function advance()
  local lo, hi = extent()
  if lo > hi then return end
  local left = bx + lo * SX
  local right = bx + hi * SX + AW

  if (dir > 0 and right + 2 > 238) or (dir < 0 and left - 2 < 2) then
    dir = -dir
    by = by + DROP
  else
    bx = bx + dir * 3.5   -- 240 wide: the keeper keeps the old feel
  end

  if bottom_of_rank() >= BUNKY then
    -- They are in among the bunkers; anything they touch is gone.
    for i = 1, BUNKERS do
      local b = bunker[i]
      for j = 1, BW * BH do b[j] = false end
    end
  end
  if bottom_of_rank() >= GUNY then die() end
end

-- ── things hitting things ───────────────────────────────────────────────────

-- A bunker eats one block and the shot that found it. Two pixels at a time, so
-- a bunker wears through rather than popping.
local function hit_bunker(x, y)
  for i = 1, BUNKERS do
    local ox = bunker_x(i)
    if x >= ox and x < ox + BW * 2 and y >= BUNKY and y < BUNKY + BH * 2 then
      local bc = flr((x - ox) / 2)
      local br = flr((y - BUNKY) / 2)
      local j = br * BW + bc + 1
      if bunker[i][j] then
        bunker[i][j] = false
        return true
      end
    end
  end
  return false
end

local function fire()
  -- One shot in the air at a time. It is the oldest rule in this kind of game
  -- and it is what makes each one a decision.
  if shot then return end
  shot = { x = px + 4, y = GUNY - 2 }
  sfx(0)
end

local function drop_bomb()
  local c = flr(rnd(COLS))
  local r = lowest_row(c)
  if r < 0 then return end
  bombs[#bombs + 1] = { x = bx + c * SX + 3, y = by + r * SY + AH }
end

function _update()
  if dead then
    if btnp(4) then _init() end
    return
  end
  if flash > 0 then flash = flash - 1 end
  if shake > 0 then shake = shake - 1 end
  for i = #bits, 1, -1 do
    local b = bits[i]
    b.x, b.y, b.life = b.x + b.dx, b.y + b.dy, b.life - 1
    b.dy = b.dy + 0.06
    if b.life <= 0 then table.remove(bits, i) end
  end

  -- A beat after being hit, so you see what happened before it resumes.
  if hitpause > 0 then
    hitpause = hitpause - 1
    return
  end

  if btn(0) then px = px - 2 end
  if btn(1) then px = px + 2 end
  px = mid(2, px, 228)
  if btnp(4) then fire() end

  -- The rank
  tick = tick + 1
  step = mid(FAST, flr(SLOW * count / (ROWS * COLS)), SLOW)
  if tick >= step then
    tick = 0
    advance()
    if dead then return end
  end

  if rnd(1) < 0.035 and #bombs < 3 then drop_bomb() end

  -- Your shot
  if shot then
    shot.y = shot.y - 4
    if shot.y < 12 then
      shot = nil
    elseif hit_bunker(shot.x, shot.y) then
      shot = nil
    else
      for r = 0, ROWS - 1 do
        for c = 0, COLS - 1 do
          local i = at(r, c)
          if alive[i] then
            local ax, ay = bx + c * SX, by + r * SY
            if shot.x >= ax and shot.x < ax + AW and shot.y >= ay and shot.y < ay + AH then
              alive[i] = false
              count = count - 1
              burst(ax + AW / 2, ay + AH / 2, 6, colour_of(r))
              shake = 2
              sfx(1)
              points = points + value(r)
              score(points)
              if points > best then best = points end
              shot = nil
              flash = 3
              break
            end
          end
        end
        if not shot then break end
      end
    end
  end

  -- Theirs
  for i = #bombs, 1, -1 do
    local b = bombs[i]
    b.y = b.y + 2
    if b.y > 159 then
      table.remove(bombs, i)
    elseif hit_bunker(b.x, b.y) then
      table.remove(bombs, i)
    elseif b.y >= GUNY and b.y < GUNY + 6 and b.x >= px and b.x < px + 10 then
      table.remove(bombs, i)
      lives = lives - 1
      hitpause = 24
      shake = 8
      burst(px + 5, GUNY + 2, 12, 7)
      sfx(5)
      if lives <= 0 then die() end
    end
  end

  if count == 0 then
    sfx(6)
    wave = wave + 1
    build_wave()
    shot, bombs = nil, {}
    hitpause = 20
  end
end

-- ── how it looks ────────────────────────────────────────────────────────────

-- Two frames, and the whole rank is on the same one, because they step together.
local function draw_alien(x, y, c, other)
  rect(x + 1, y, 6, 3, c)
  rect(x, y + 3, 8, 2, c)
  pset(x + 2, y + 1, 0)
  pset(x + 5, y + 1, 0)
  if other then
    pset(x, y + 5, c) pset(x + 7, y + 5, c)
  else
    pset(x + 1, y + 5, c) pset(x + 6, y + 5, c)
  end
end

function _draw()
  cls(0)

  -- One offset, applied to the field and not to the panel. A HUD that shakes
  -- with the screen is a HUD you cannot read at the exact moment you need it.
  local sx = shake > 0 and (flr(rnd(3)) - 1) or 0
  local sy = shake > 0 and (flr(rnd(3)) - 1) or 0

  local other = dir > 0

  for r = 0, ROWS - 1 do
    for c = 0, COLS - 1 do
      if alive[at(r, c)] then
        draw_alien(bx + c * SX + sx, by + r * SY + sy, colour_of(r), other)
      end
    end
  end

  for i = 1, BUNKERS do
    local ox = bunker_x(i)
    local b = bunker[i]
    for br = 0, BH - 1 do
      for bc = 0, BW - 1 do
        if b[br * BW + bc + 1] then
          rect(ox + bc * 2, BUNKY + br * 2, 2, 2, 5)
        end
      end
    end
  end

  for i = 1, #bombs do
    local b = bombs[i]
    rect(b.x + sx, b.y + sy, 1, 3, 2)
  end
  if shot then rect(shot.x, shot.y, 1, 4, 4) end
  for i = 1, #bits do
    local b = bits[i]
    pset(flr(b.x) + sx, flr(b.y) + sy, b.life > 4 and 7 or b.c)
  end

  -- the keeper, unless they are being put back together
  if hitpause == 0 or flr(hitpause / 3) % 2 == 0 then
    rect(px, GUNY + 2, 10, 4, 7)
    rect(px + 4, GUNY, 2, 3, 7)
  end

  -- The light itself. It is what all of this is for, so it is on screen the
  -- whole time and it dims as you lose.
  local glow = lives >= 2 and 3 or 1
  for x = 0, 239, 2 do
    local h = 1 + flr(rnd(lives))
    rect(x, 160 - h, 2, h, glow)
  end

  rect(0, 0, 240, 12, 0)
  line(0, 12, 239, 12, 1)
  print(points .. "", 2, 3, flash > 0 and 7 or 4)
  print("WAVE " .. wave, 104, 3, 1)
  for i = 1, lives do
    rect(232 - (i - 1) * 8, 4, 6, 2, 7)
    rect(234 - (i - 1) * 8, 2, 2, 2, 7)
  end

  if dead then
    rect(70, 66, 100, 28, 0)
    rectb(70, 66, 100, 28, 2)
    print("THE LIGHT GOES OUT", 84, 72, 2)
    print("BEST " .. best, 86, 83, 1)
    print("PRESS O", 130, 83, 3)
  end
end

function _cover()
  cls(0)
  for r = 0, 3 do
    for c = 0, 13 do
      draw_alien(14 + c * 16, 14 + r * 14, r == 0 and 2 or (r <= 1 and 6 or 3), r % 2 == 0)
    end
  end
  rect(118, 72, 2, 24, 4)
  for i = 1, 6 do
    local ox = 14 + (i - 1) * 38
    for br = 0, 2 do
      for bc = 0, 6 do
        if not (i == 3 and br == 0 and bc > 3) then
          rect(ox + bc * 2, 100 + br * 2, 2, 2, 5)
        end
      end
    end
  end
  rect(112, 112, 10, 4, 7)
  rect(116, 110, 2, 3, 7)
  rect(0, 122, 240, 38, 0)
  for x = 0, 239, 2 do rect(x, 156, 2, 3, 3) end
  print("FIREKEEPER", 60, 130, 3, 3)
end
