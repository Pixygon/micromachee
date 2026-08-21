-- title: Dreadwager
-- author: pixygon
-- about: drift into the horde, or author your own end

-- The second pearl, at 128 by 128. You are a broken Pixiel in Limbo — the
-- planet's corrupted recycling bin — and "respawn" is the recycler's curse: a
-- deletion that never completes. That is why the restart line is what it is.
--
-- The spine of Dreadwager is INTENTION: *do you drift into the horde, or author
-- your own death by leaping the cliff?* So there are two endings and they are
-- not the same ending. Being caught calls lose(). Stepping into the cliff on
-- purpose calls win() — it is still your deletion, but it is yours. The cliff
-- only opens once you have taken enough sparks to have something to lose by
-- leaping, which is the whole question asked in one number.
--
-- Sparks are reclaimed compute. They are the score and they are also the
-- upgrades, because in Dreadwager those are the same substance.

local PW = 6
local SPEED = 1.7
local DASH, DASHCOOL = 9, 40
local HITCOOL = 30
local MAXFOES = 64
local CLIFF_AT = 25              -- sparks before the cliff opens

local px, py, aimx, aimy, dashleft, dashcool, hp, hitcool
local foes, shots, sparks
local cool, guns, taken, tick, spawn
local cliff, cx, cy
local dead, authored, best

local function reset()
  px, py = 64, 70
  aimx, aimy = 0, -1
  dashleft, dashcool = 0, 0
  hp, hitcool = 3, 0
  foes, shots, sparks = {}, {}, {}
  cool, guns, taken, tick = 0, 1, 0, 0
  spawn = 40
  cliff, cx, cy = false, 0, 0
  dead, authored = false, false
end

function _init()
  reset()
  best = best or 0
  score(0)
end

-- ── the horde ───────────────────────────────────────────────────────────────

-- Off every edge, never on screen. A thing that appears in front of you is a
-- cheat; a thing that walks in from the dark is the game.
local function send()
  local side = flr(rnd(4))
  local x, y
  if side == 0 then x, y = rnd(128), -8
  elseif side == 1 then x, y = rnd(128), 132
  elseif side == 2 then x, y = -8, rnd(128)
  else x, y = 132, rnd(128) end

  local roll, kind, hp2, sp, w = rnd(1), 1, 1, 0.55, 6
  if taken > 40 and roll < 0.18 then
    kind, hp2, sp, w = 3, 4, 0.34, 9        -- slow and thick
  elseif taken > 12 and roll < 0.45 then
    kind, hp2, sp, w = 2, 1, 0.95, 5        -- quick and thin
  end
  -- Every one of them walks a fraction differently, so a crowd spreads into a
  -- crowd instead of arriving as one solid rank.
  foes[#foes + 1] = { x = x, y = y, hp = hp2, kind = kind, sp = sp * (0.85 + rnd(0.3)), w = w }
end

local function fire()
  if cool > 0 then return end
  cool = mid(4, 11 - guns * 2, 11)
  local x, y = px + PW / 2, py + PW / 2
  -- Firing is aiming: there is no second stick, so the direction you are
  -- travelling IS the direction you shoot, and turning to face something is a
  -- decision about where you are standing.
  if guns >= 3 then
    shots[#shots + 1] = { x = x, y = y, dx = aimx * 4, dy = aimy * 4 }
    shots[#shots + 1] = { x = x, y = y, dx = aimx * 4 - aimy * 1.1, dy = aimy * 4 + aimx * 1.1 }
    shots[#shots + 1] = { x = x, y = y, dx = aimx * 4 + aimy * 1.1, dy = aimy * 4 - aimx * 1.1 }
  elseif guns == 2 then
    shots[#shots + 1] = { x = x - aimy * 2, y = y + aimx * 2, dx = aimx * 4, dy = aimy * 4 }
    shots[#shots + 1] = { x = x + aimy * 2, y = y - aimx * 2, dx = aimx * 4, dy = aimy * 4 }
  else
    shots[#shots + 1] = { x = x, y = y, dx = aimx * 4, dy = aimy * 4 }
  end
end

local function drift()
  dead = true
  lose()
end

local function author()
  dead, authored = true, true
  win()
end

function _update()
  if dead then
    if btnp(4) then reset() score(0) end
    return
  end
  tick = tick + 1

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
    dashleft, dashcool = DASH, DASHCOOL
  end
  local speed = SPEED
  if dashleft > 0 then
    dashleft = dashleft - 1
    speed = SPEED * 2.6
  end

  px = mid(0, px + mx * speed, 128 - PW)
  py = mid(10, py + my * speed, 128 - PW)

  if cool > 0 then cool = cool - 1 end
  if hitcool > 0 then hitcool = hitcool - 1 end
  fire()

  -- ── the cliff ─────────────────────────────────────────────────────────────
  if not cliff and taken >= CLIFF_AT then
    cliff = true
    -- Never under your feet at the moment it opens: the choice has to be walked
    -- to, or it is not a choice.
    repeat
      cx, cy = 18 + rnd(92), 26 + rnd(84)
    until (cx - px) ^ 2 + (cy - py) ^ 2 > 1600
  end
  if cliff then
    local d = (px + 3 - cx) ^ 2 + (py + 3 - cy) ^ 2
    if d < 90 and btnp(5) then author() return end
  end

  -- ── them ──────────────────────────────────────────────────────────────────
  spawn = spawn - 1
  if spawn <= 0 and #foes < MAXFOES then
    send()
    spawn = mid(6, 34 - flr(tick / 90), 34)
  end

  for i = #foes, 1, -1 do
    local f = foes[i]
    local dx, dy = px + 3 - f.x, py + 3 - f.y
    local d = math.sqrt(dx * dx + dy * dy)
    if d > 0.5 then
      f.x = f.x + dx / d * f.sp
      f.y = f.y + dy / d * f.sp
    end
    if d < f.w and hitcool <= 0 and dashleft <= 0 then
      hp = hp - 1
      hitcool = HITCOOL
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
          table.remove(shots, i)
          if f.hp <= 0 then
            sparks[#sparks + 1] = { x = f.x, y = f.y, t = 0 }
            table.remove(foes, j)
          end
          break
        end
      end
    end
  end

  -- ── sparks ────────────────────────────────────────────────────────────────
  for i = #sparks, 1, -1 do
    local s = sparks[i]
    s.t = s.t + 1
    local dx, dy = px + 3 - s.x, py + 3 - s.y
    local d = math.sqrt(dx * dx + dy * dy)
    -- Reclaimed compute comes to you once you are near it, so clearing a corner
    -- does not mean walking every step of it back again.
    if d < 34 and d > 0 then
      local pull = mid(0.6, 3.4 - d / 12, 3.4)
      s.x = s.x + dx / d * pull
      s.y = s.y + dy / d * pull
    end
    if d < 6 then
      table.remove(sparks, i)
      taken = taken + 1
      score(taken)
      if taken > best then best = taken end
      if taken == 12 or taken == 40 then guns = guns + 1 end
    elseif s.t > 900 then
      table.remove(sparks, i)
    end
  end
end

-- ── how it looks ────────────────────────────────────────────────────────────

local function draw_pixiel(x, y, c)
  rect(x + 1, y, 4, 3, c)              -- head
  rect(x + 1, y + 1, 3, 1, 0)          -- visor
  pset(x + 1 + (aimx >= 0 and 2 or 0), y + 1, 6)
  rect(x, y + 3, 6, 3, c)              -- the rest of it, such as it is
  pset(x + 2, y + 4, 6)
end

local function draw_foe(f)
  local x, y = flr(f.x), flr(f.y)
  if f.kind == 3 then
    rect(x - 4, y - 4, 9, 9, 6)
    rect(x - 2, y - 2, 5, 5, 0)
    pset(x - 1, y - 1, 6) pset(x + 1, y - 1, 6)
  elseif f.kind == 2 then
    rect(x - 2, y - 2, 5, 5, 3)
    pset(x - 1, y, 0) pset(x + 1, y, 0)
  else
    rect(x - 3, y - 3, 6, 6, 2)
    pset(x - 1, y - 1, 0) pset(x + 1, y - 1, 0)
  end
end

function _draw()
  cls(0)

  -- Limbo, as a floor that is mostly not there.
  for i = 0, 23 do
    pset((i * 43 + 11) % 128, 12 + (i * 71) % 112, 1)
  end

  if cliff then
    -- A hole, drawn as a hole: a rim you can see and nothing inside it.
    local r = 10 + flr(math.sin(tick * 0.09) * 2)
    circ(cx, cy, r, 0)
    circb(cx, cy, r, 1)
    circb(cx, cy, r - 3, 1)
    local near = (px + 3 - cx) ^ 2 + (py + 3 - cy) ^ 2 < 90
    if near then
      circb(cx, cy, r, 7)
      -- Above the hole and clamped to the screen. Centred ON the hole put it
      -- under the player standing in it, and a cliff near the left edge pushed
      -- half the words off the screen.
      local t = "X TO LEAP"
      print(t, mid(2, cx - #t * 2, 126 - #t * 4), mid(12, cy - r - 9, 118), 7)
    end
  end

  for i = 1, #sparks do
    local s = sparks[i]
    -- Never the bullets' colour: on a dark field two small yellow things are
    -- one thing, and one of them is worth picking up.
    local c = flr(s.t / 3) % 2 == 0 and 5 or 7
    rect(flr(s.x) - 1, flr(s.y) - 1, 3, 3, c)
  end

  for i = 1, #foes do draw_foe(foes[i]) end

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
  for i = 1, 3 do
    rect(56 + (i - 1) * 6, 3, 4, 4, i <= hp and 2 or 1)
  end
  -- Right-aligned rather than placed by eye. "24 TO THE CLIFF" at a guessed x
  -- ran off the edge and rendered as "24 TO THE CLI", which looks like a bug in
  -- the font rather than a number that got too wide.
  local note = cliff and "THE CLIFF" or (CLIFF_AT - taken) .. " TO THE CLIFF"
  print(note, 126 - #note * 4, 2, cliff and 6 or 1)
  if dashcool > 0 then rect(2, 8, flr(24 * (1 - dashcool / DASHCOOL)), 1, 6) end

  if dead then
    rect(8, 48, 112, 32, 0)
    rectb(8, 48, 112, 32, authored and 5 or 2)
    if authored then
      print("YOU AUTHORED IT", 30, 54, 5)
      print("SPARKS " .. taken, 24, 64, 7)
      print("O AGAIN", 72, 64, 3)
    else
      print("YOU DRIFTED", 40, 54, 2)
      print("SPARKS " .. taken, 24, 64, 7)
      print("O AGAIN", 72, 64, 3)
    end
    print("DELETION NEVER COMPLETES", 16, 72, 1)
  end
end

function _cover()
  -- Bold at a third of an inch: one lit thing in the middle, a ring of red
  -- closing on it, and the hole waiting off to one side.
  cls(0)
  for i = 0, 19 do pset((i * 43 + 11) % 128, 8 + (i * 71) % 84, 1) end

  circ(98, 26, 11, 0)
  circb(98, 26, 11, 1)
  circb(98, 26, 8, 1)

  local ring = { { 20, 20 }, { 52, 12 }, { 84, 62 }, { 18, 58 }, { 44, 78 }, { 76, 84 }, { 104, 70 }, { 12, 38 } }
  for i = 1, #ring do
    local x, y = ring[i][1], ring[i][2]
    rect(x - 3, y - 3, 7, 7, 2)
    pset(x - 1, y - 1, 0) pset(x + 1, y - 1, 0)
  end
  rect(60, 34, 5, 5, 3)
  rect(30, 46, 9, 9, 6)
  rect(32, 48, 5, 5, 0)
  pset(33, 50, 6) pset(35, 50, 6)      -- without eyes it is a blue box

  for i = 0, 3 do rect(56, 26 - i * 6, 3, 3, 4) end
  rect(52, 44, 4, 4, 5)
  rect(70, 52, 4, 4, 5)

  -- the Pixiel, four times over
  rect(52, 40, 16, 8, 7)
  rect(54, 32, 12, 8, 7)
  rect(54, 34, 9, 3, 0)
  rect(62, 34, 3, 3, 6)
  rect(58, 42, 4, 4, 6)

  rect(0, 96, 128, 32, 0)
  print("DREADWAGER", 4, 104, 2, 3)
end
