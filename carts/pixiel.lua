-- title: Pixiel
-- author: pixygon
-- about: a discarded body, running the pit its own way

-- The Pixiels are the body-stock: skeleton and AI brain, printed over. The ones
-- not cleanly reissued end up in the pit. This one is not being carried along by
-- it — it decides where to go.
--
-- The world is a tile grid, eight pixels square, sixteen rows tall, generated a
-- screen ahead and forgotten a screen behind. Nothing is stored for the whole
-- run, so the pit can be endless without ever being large.
--
-- The numbers below are the game. A jump is 4.4 up against 0.30 down, which is
-- an apex of about 32 pixels — four tiles — after 15 frames, and a hair under 60
-- pixels of ground covered at full run. Every gap and every ledge in the
-- generator is sized against those two figures, so nothing it builds is a jump
-- this body cannot make.

local TILE   = 8
local ROWS   = 16
local GROUND = 13          -- the row the floor of the pit sits on

local ACC    = 0.34        -- how hard it can push against the floor
local FRIC   = 0.80        -- and how quickly it stops pushing
local MAXVX  = 2.0
local GRAV   = 0.30
local JUMP   = -4.4
local CUT    = -1.4        -- let go early and the rise is cut short
local COYOTE = 4           -- frames of grace after walking off an edge
local BUFFER = 5           -- frames a jump pressed just before landing is held

local PW, PH = 6, 9        -- the body is six by nine

-- world[col] = { rows... }, 0 empty, 1 floor, 2 ledge. Columns behind the
-- camera are dropped, so this table stays about a screen and a half wide.
local world, coinat, foes
local px, py, vx, vy, onground, coyote, buffered, face
local camx, furthest, coins, dead, best, tick

-- ── the pit builds itself ────────────────────────────────────────────────────

local made          -- highest column decided so far
local plan, planleft, planrow, planhigh, lastgap, needsroom, laidfoe

local function column()
  local t = {}
  for r = 0, ROWS - 1 do t[r] = 0 end
  return t
end

-- Decide one column. The generator is a small state machine: it commits to a
-- run of some shape, lays that shape down column by column, then picks another.
-- Choosing per-column instead would give noise, and noise is not a level.
local function decide()
  if planleft <= 0 then
    local roll = rnd(1)
    local far  = mid(0, made / 900, 1)     -- it gets meaner the further you go
    -- Never two pits in a row; landing and immediately leaping again is a
    -- reflex test, not a platformer.
    if lastgap then roll = mid(0.42, roll, 1) end
    -- A platform overhead is a low ceiling, and a low ceiling in front of a
    -- ledge is a pocket with no jump out of it. Open ground always follows one,
    -- so there is somewhere to gather the jump from.
    if needsroom then roll = 1 end
    if roll < 0.18 + far * 0.10 then
      -- A pit. Two to four tiles: a full run clears seven, so this is a
      -- decision to make rather than a trap to memorise.
      plan, planleft = "gap", 2 + flr(rnd(2 + far * 2))
    elseif roll < 0.42 then
      -- A ledge to climb, one or two tiles up.
      plan, planleft = "step", 3 + flr(rnd(4))
      planrow = GROUND - 1 - flr(rnd(2))
    elseif roll < 0.66 then
      -- A platform to climb onto. Three tiles up: the jump tops out at four,
      -- so this is a landing rather than a ceiling to bump your head on.
      plan, planleft = "float", 4 + flr(rnd(4))
      planhigh = GROUND - 3
    else
      plan, planleft = "flat", 5 + flr(rnd(8))
    end
    lastgap = plan == "gap"
    needsroom = plan == "float"
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
    -- the reason to climb it, sitting just above the deck
    if rnd(1) < 0.45 then coinat[made] = planhigh - 2 end
  elseif plan == "flat" then
    -- One at most per stretch. They pace, turning at every lip, so several laid
    -- on the same run end up shoulder to shoulder in a wall you cannot pass.
    if not laidfoe and made > 22 and planleft > 1 and rnd(1) < 0.09 then
      foes[#foes + 1] = { x = made * TILE, y = (GROUND - 1) * TILE, d = -1 }
      laidfoe = true
    end
    if rnd(1) < 0.06 then coinat[made] = GROUND - 3 end
  end

  world[made] = t
end

local function generate_to(col)
  while made < col do decide() end
end

-- ── reading the world ───────────────────────────────────────────────────────

local function tile(c, r)
  if r < 0 or r >= ROWS then return 0 end
  local t = world[c]
  if not t then return 0 end
  return t[r]
end

local function solid(wx, wy)
  return tile(flr(wx / TILE), flr(wy / TILE)) > 0
end

-- Any of the box's corners, plus the middles of the long edges, so a six-wide
-- body cannot straddle an eight-wide tile unnoticed.
local function boxhit(x, y, w, h)
  return solid(x, y) or solid(x + w - 1, y)
      or solid(x, y + h - 1) or solid(x + w - 1, y + h - 1)
      or solid(x, y + h / 2) or solid(x + w - 1, y + h / 2)
end

-- ── the run ─────────────────────────────────────────────────────────────────

function _init()
  world, coinat, foes = {}, {}, {}
  made, plan, planleft, lastgap, needsroom, laidfoe = 0, "flat", 12, false, false, false
  planrow, planhigh = GROUND - 1, GROUND - 3
  generate_to(40)

  px, py = 24, (GROUND - 2) * TILE
  vx, vy = 0, 0
  onground, coyote, buffered, face = true, 0, 0, 1
  camx, furthest, coins, dead, tick = 0, 0, 0, false, 0
  best = best or 0
  score(0)
end

local function die()
  dead = true
  lose()
end

function _update()
  if dead then
    if btnp(4) then _init() end
    return
  end
  tick = tick + 1

  -- ── what the player asks for ──────────────────────────────────────────────
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
  end
  -- Releasing the button mid-rise cuts the jump, so a tap is a hop and a hold
  -- is the full four tiles. One button, every height in between.
  if not btn(4) and vy < CUT then vy = CUT end

  vy = mid(-8, vy + GRAV, 6)

  -- ── moving, one axis at a time ────────────────────────────────────────────
  -- Resolving x and y together makes a body that catches on flat floors; taken
  -- separately, a wall stops the walk and a floor stops the fall, and nothing
  -- else happens.
  local nx = px + vx
  if boxhit(nx, py, PW, PH) then
    -- back up to the tile edge it hit
    local step, guard = vx > 0 and -1 or 1, 0
    while boxhit(nx, py, PW, PH) and guard < TILE + 2 do
      nx, guard = nx + step, guard + 1
    end
    vx = 0
  end
  px = nx

  -- The camera never gives ground, so neither does the pit behind it.
  if px < camx then px, vx = camx, 0 end

  local ny = py + vy
  if boxhit(px, ny, PW, PH) then
    local step, guard = vy > 0 and -1 or 1, 0
    while boxhit(px, ny, PW, PH) and guard < TILE + 2 do
      ny, guard = ny + step, guard + 1
    end
    if vy > 0 then
      onground, coyote = true, COYOTE
    end
    vy = 0
  else
    if onground then coyote = COYOTE end
    onground = false
  end
  py = ny

  -- ── the world reacts ──────────────────────────────────────────────────────
  local col = flr((px + PW / 2) / TILE)
  local row = flr((py + PH / 2) / TILE)
  if coinat[col] and row >= coinat[col] - 1 and row <= coinat[col] + 1 then
    coinat[col] = nil
    coins = coins + 1
  end

  for i = #foes, 1, -1 do
    local f = foes[i]
    if f.x < camx - 40 then
      table.remove(foes, i)
    else
      f.x = f.x + f.d * 0.5
      -- turn at a wall, or at the lip of anything it would walk off
      if solid(f.x + (f.d > 0 and 6 or -1), f.y + 3)
        or not solid(f.x + (f.d > 0 and 6 or -1), f.y + 7) then
        f.d = -f.d
      end
      if px + PW > f.x and px < f.x + 6 and py + PH > f.y and py < f.y + 6 then
        if vy > 0 and py + PH - vy <= f.y + 3 then
          table.remove(foes, i)
          vy = JUMP * 0.7                 -- a stomp gives half a jump back
          coins = coins + 2
        else
          die()
          return
        end
      end
    end
  end

  if py > 128 then die() return end

  -- ── the camera, and the tail of the world ────────────────────────────────
  if px - camx > 46 then camx = px - 46 end
  generate_to(flr(camx / TILE) + 20)
  local drop = flr(camx / TILE) - 4
  if world[drop] then world[drop], coinat[drop] = nil, nil end

  if px > furthest then furthest = px end
  local total = flr(furthest / TILE) + coins * 5
  score(total)
  if total > best then best = total end
end

-- ── how it looks ────────────────────────────────────────────────────────────

-- Six pixels wide and nine tall is not much of a robot, so the reading comes
-- from contrast rather than detail: a dark visor across the head and one lit
-- pixel where the core is.
local function draw_runner(sx, sy, c)
  rect(sx + 1, sy, 5, 4, c)
  rect(sx + 1, sy + 1, 4, 1, 0)
  pset(sx + (face > 0 and 4 or 1), sy + 1, 6)
  rect(sx + 1, sy + 4, 5, 4, c)
  pset(sx + 3, sy + 6, 6)
  if not onground then
    rect(sx, sy + 8, 2, 1, c)                   -- legs out, in the air
    rect(sx + 4, sy + 8, 2, 1, c)
  elseif vx ~= 0 and flr(tick / 4) % 2 == 0 then
    rect(sx, sy + 8, 2, 1, c)
    rect(sx + 4, sy + 8, 1, 1, c)
  else
    rect(sx + 1, sy + 8, 1, 1, c)
    rect(sx + 4, sy + 8, 1, 1, c)
  end
end

function _draw()
  cls(0)
  local ox = flr(camx)

  -- a few far lights, placed by position so they cost nothing to keep
  for i = 0, 9 do
    pset((i * 53 - flr(ox / 3)) % 128, 14 + (i * 37) % 56, 1)
  end

  local first = flr(ox / TILE)
  for c = first, first + 17 do
    local sx = c * TILE - ox
    for r = 0, ROWS - 1 do
      local t = tile(c, r)
      if t > 0 then
        local sy = r * TILE
        rect(sx, sy, TILE, TILE, t == 1 and 1 or 2)
        -- only the exposed top gets a lit edge, so a stack reads as one mass
        if tile(c, r - 1) == 0 then
          line(sx, sy, sx + TILE - 1, sy, 6)
        end
      end
    end
    local cr = coinat[c]
    if cr then
      local cy = cr * TILE + 3 + (flr(tick / 6) % 2)
      rect(sx + 2, cy, 4, 4, 4)
      pset(sx + 3, cy + 1, 7)
    end
  end

  for i = 1, #foes do
    local f = foes[i]
    local sx = flr(f.x) - ox
    if sx > -8 and sx < 128 then
      rect(sx, flr(f.y) + 1, 6, 5, 3)
      pset(sx + 1, flr(f.y) + 2, 0)
      pset(sx + 4, flr(f.y) + 2, 0)
      rect(sx, flr(f.y) + 6, 6, 1, flr(tick / 5) % 2 == 0 and 3 or 1)
    end
  end

  draw_runner(flr(px) - ox, flr(py), dead and 2 or 7)

  rect(0, 0, 128, 14, 0)
  line(0, 14, 127, 14, 1)
  print(flr(furthest / TILE) .. "M", 2, 3, 7)
  print("O " .. coins, 44, 3, 4)
  print("BEST " .. best, 82, 3, 6)

  if dead then
    rect(20, 50, 88, 26, 0)
    rectb(20, 50, 88, 26, 2)
    print("THE PIT KEEPS IT", 28, 56, 2)
    print("PRESS O", 50, 66, 3)
  end
end

function _cover()
  cls(0)
  for i = 0, 11 do pset((i * 43) % 128, 14 + (i * 29) % 46, 1) end
  for c = 0, 15 do
    local sx = c * 8
    if c < 7 or c > 9 then
      rect(sx, 104, 8, 24, 1)
      line(sx, 104, sx + 7, 104, 6)
    end
  end
  rect(80, 72, 24, 8, 2)
  line(80, 72, 103, 72, 6)
  rect(90, 60, 4, 4, 4)
  face, onground, vx, tick = 1, false, 1, 0
  draw_runner(52, 78, 7)
  rect(0, 96, 128, 32, 0)
  print("PIXIEL", 28, 104, 6, 3)
end
