-- title: Pixiel
-- author: pixygon
-- about: a discarded body, still running

-- The Pixiels are the body-stock: skeleton and AI brain, printed over. The ones
-- not cleanly reissued are the ones that end up in the pit. This one has not
-- stopped running yet.
--
-- The ground is a column array shifted one place left per frame, the same trick
-- Down-Shaft uses for its cave: nothing is stored ahead, one new column is
-- decided at the right edge, and the world falls off the left. An endless runner
-- needs no level, only an opinion about the next column.

local SX    = 30          -- where the runner stands; the world moves, not him
local FLOOR = 104         -- the top of a full-height column
local GRAV  = 0.30
local JUMP  = -4.5

local ground, block, x, y, vy, onfloor, dist, best, dead, speed, carry, gap, run, blockleft

-- Decide one new column. Runs of ground, then a gap, then ground again — a
-- pattern the player can read a moment ahead, which is the whole game.
local function next_column()
  if gap > 0 then
    gap = gap - 1
    return 0, false
  end
  run = run - 1
  if run <= 0 then
    -- A column is ONE PIXEL, so a gap counted in single figures is a crack the
    -- runner steps over without noticing. A jump covers about fifty pixels at
    -- the starting speed, so the gaps are sized against that and widen with
    -- distance — never past what a jump can still clear.
    gap = 14 + flr(rnd(mid(2, 4 + dist / 400, 16)))
    run = 34 + flr(rnd(30))
    return 0, false
  end
  -- An occasional block to hop, three columns wide so it reads as a thing
  -- rather than a scratch, and never on the lip of a gap.
  if blockleft > 0 then
    blockleft = blockleft - 1
    return FLOOR, true
  end
  if run > 6 and rnd(1) < 0.012 then
    blockleft = 2
    return FLOOR, true
  end
  return FLOOR, false
end

function _init()
  ground, block = {}, {}
  for i = 1, 130 do ground[i], block[i] = FLOOR, false end
  x, y, vy = SX, FLOOR - 8, 0
  onfloor = true
  dist, dead = 0, false
  speed, carry = 1.6, 0
  gap, run, blockleft = 0, 40, 0
  best = best or 0
  score(0)
end

function _update()
  if dead then
    if btnp(4) then _init() end
    return
  end

  -- Scroll. The speed climbs slowly, so the same gap gets harder without the
  -- gaps themselves having to grow much.
  speed = mid(1.6, 1.6 + dist / 2000, 3.4)
  carry = carry + speed
  while carry >= 1 do
    carry = carry - 1
    for i = 1, 129 do
      ground[i], block[i] = ground[i + 1], block[i + 1]
    end
    ground[130], block[130] = next_column()
    dist = dist + 1
  end
  score(flr(dist / 10))
  if flr(dist / 10) > best then best = flr(dist / 10) end

  -- Jump. Holding O keeps the rise going a little, so a tap is a hop and a
  -- hold is a leap — one button, two jumps.
  if onfloor and btnp(4) then
    vy = JUMP
    onfloor = false
  end
  if not btn(4) and vy < -1.6 then vy = -1.6 end

  vy = vy + GRAV
  y = y + vy

  local col = flr(x) + 1
  local top = ground[col] or FLOOR
  local solid = top > 0

  if solid and vy >= 0 and y + 8 >= top and y + 8 - vy <= top + 2 then
    y = top - 8
    vy = 0
    onfloor = true
  else
    onfloor = false
  end

  -- A block is a wall you must be above to pass.
  if block[col] and y + 8 > top - 8 then
    dead = true
    lose()
  end

  if y > 128 then
    dead = true
    lose()
  end
end

-- Six pixels wide and nine tall is not much of a robot, so the reading comes
-- from contrast rather than detail: a dark visor across the head and one lit
-- pixel where the core is. All one colour and it is a blob.
local function draw_runner(px, py, c)
  rect(px + 1, py, 5, 4, c)          -- head
  rect(px + 1, py + 1, 4, 1, 0)      -- visor
  pset(px + 4, py + 1, 6)            -- the eye that is still on
  rect(px + 1, py + 5, 5, 3, c)      -- chest
  pset(px + 3, py + 6, 6)            -- core
  if onfloor and flr(dist / 5) % 2 == 0 then
    rect(px, py + 8, 2, 2, c)        -- stride
    rect(px + 4, py + 8, 2, 1, c)
  else
    rect(px + 1, py + 8, 2, 2, c)    -- together, and in the air
    rect(px + 4, py + 8, 2, 2, c)
  end
end

function _draw()
  cls(0)

  -- a few far lights, placed by position so they cost nothing
  for i = 0, 9 do
    pset((i * 53 - flr(dist / 3)) % 128, 12 + (i * 37) % 60, 1)
  end

  for i = 1, 128 do
    local top = ground[i]
    if top > 0 then
      rect(i - 1, top, 1, 128 - top, 1)
      pset(i - 1, top, 6)
      if block[i] then rect(i - 1, top - 9, 1, 9, 2) end
    end
  end

  draw_runner(flr(x), flr(y), dead and 2 or 7)

  rect(0, 0, 128, 14, 0)
  line(0, 14, 127, 14, 1)
  print("RUN " .. flr(dist / 10), 2, 3, 7)
  print("BEST " .. best, 74, 3, 6)

  if dead then
    rect(22, 52, 84, 24, 0)
    rectb(22, 52, 84, 24, 2)
    print("IT STOPS RUNNING", 30, 58, 2)
    print("PRESS O", 50, 66, 3)
  end
end

function _cover()
  cls(0)
  for i = 0, 127 do
    if i < 74 or i > 92 then
      rect(i, 84, 1, 44, 1)
      pset(i, 84, 6)
    end
  end
  for i = 0, 11 do pset((i * 43) % 128, 14 + (i * 29) % 50, 1) end
  -- mid-leap over the gap
  draw_runner(58, 62, 7)
  rect(0, 96, 128, 32, 0)
  print("PIXIEL", 28, 104, 6, 3)
end
