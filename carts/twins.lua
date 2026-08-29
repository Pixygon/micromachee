-- title: The Twins
-- author: pixygon
-- about: sun and moon. three in a row
-- mega: no

-- The Prince and the Princess: "the warmth of the sun belongs to The Prince,
-- while he goes out into the world after his moon." He never catches her.
--
-- On a board this small nobody catches anybody: three in a row is a solved
-- game, and two sides both playing perfectly draw every time. So the moon does
-- not play perfectly. She takes a win when she has one and blocks yours when
-- she must — but one move in five she does neither and plays somewhere else.
-- That single number is the whole difficulty setting, and it is the difference
-- between a game and a demonstration.

local BLUNDER = 0.2

local LINES = {
  { 1, 2, 3 }, { 4, 5, 6 }, { 7, 8, 9 },
  { 1, 4, 7 }, { 2, 5, 8 }, { 3, 6, 9 },
  { 1, 5, 9 }, { 3, 5, 7 },
}

-- The board is thirty-six a side rather than something bigger so that
-- everything else gets a strip of its own: the tally along the top and whatever
-- there is to say along the bottom. A message box laid over the board hides the
-- board, and the one time that matters most is the moment it draws the line
-- through three.
local CELL, OX, OY = 36, 66, 22
local SAY = 140
local SUN, MOON = 1, 2
local THINK = 16          -- frames the moon takes, so a reply reads as a reply

local board, cx, cy, over, winline, winner, wait
local myside, picking, picksel
local wins, losses, draws

local function slot(x, y) return y * 3 + x + 1 end

-- Which side holds a line, and which line it is.
local function decided(b)
  for i = 1, #LINES do
    local l = LINES[i]
    local a = b[l[1]]
    if a ~= 0 and a == b[l[2]] and a == b[l[3]] then return a, i end
  end
  return 0, 0
end

local function full(b)
  for i = 1, 9 do
    if b[i] == 0 then return false end
  end
  return true
end

-- The one square that completes a line for `side`, if there is one. Used twice:
-- once to win, once — with the other side's mark — to see what must be blocked.
local function completing(b, side)
  for i = 1, #LINES do
    local l = LINES[i]
    local mine, empty = 0, 0
    for j = 1, 3 do
      if b[l[j]] == side then mine = mine + 1
      elseif b[l[j]] == 0 then empty = l[j] end
    end
    if mine == 2 and empty ~= 0 then return empty end
  end
  return 0
end

local function empties(b)
  local t = {}
  for i = 1, 9 do
    if b[i] == 0 then t[#t + 1] = i end
  end
  return t
end

local function ai_move()
  local me = myside == SUN and MOON or SUN
  local foe = myside
  local free = empties(board)
  if #free == 0 then return 0 end

  -- The blunder comes first, so it can throw away a win as well as a block.
  -- An opponent that only ever fumbles the boring moves is not fumbling.
  if rnd(1) < BLUNDER then
    return free[flr(rnd(#free)) + 1]
  end

  local take = completing(board, me)
  if take ~= 0 then return take end
  local block = completing(board, foe)
  if block ~= 0 then return block end

  if board[5] == 0 then return 5 end
  -- A cart gets math, string and table and nothing else, so there is no
  -- ipairs to walk this with.
  local pick, corners = { 1, 3, 7, 9 }, {}
  for j = 1, 4 do
    if board[pick[j]] == 0 then corners[#corners + 1] = pick[j] end
  end
  if #corners > 0 then return corners[flr(rnd(#corners)) + 1] end
  return free[flr(rnd(#free)) + 1]
end

local function finish()
  local side, line = decided(board)
  if side ~= 0 then
    over, winner, winline = true, side, line
    if side == SUN then
      wins = wins + 1
      save("wins", wins)
      sfx(6)
      win()
    else
      losses = losses + 1
      save("losses", losses)
      sfx(7)
      lose()
    end
  elseif full(board) then
    over, winner, winline = true, 0, 0
    draws = draws + 1
    save("draws", draws)
  end
  score(wins)
end

local function fresh()
  board = {}
  for i = 1, 9 do board[i] = 0 end
  cx, cy = 1, 1
  over, winner, winline, wait = false, 0, 0, 0
  -- The sun always opens, the way X always opens. Playing the moon means the
  -- other side has already moved by the time the board is yours.
  if myside == MOON then wait = THINK end
end

function _init()
  wins = load("wins") or 0
  losses = load("losses") or 0
  draws = load("draws") or 0
  myside = SUN
  picking, picksel = true, 1
  score(wins)
end

function _update()
  if picking then
    if btnp(0) or btnp(1) then picksel = 3 - picksel sfx(0) end
    if btnp(4) then
      myside = picksel == 1 and SUN or MOON
      picking = false
      fresh()
      sfx(3)
    end
    return
  end
  if over then
    if btnp(4) then fresh() end
    if btnp(5) then picking, picksel = true, 1 sfx(0) end
    return
  end

  -- The moon is thinking. Nothing you press does anything, which is the point
  -- of the pause: it is her turn and the board should look like it.
  if wait > 0 then
    wait = wait - 1
    if wait == 0 then
      local at = ai_move()
      if at ~= 0 then board[at] = (myside == SUN and MOON or SUN) end
      finish()
    end
    return
  end

  if btnp(0) then cx = cx - 1 end
  if btnp(1) then cx = cx + 1 end
  if btnp(2) then cy = cy - 1 end
  if btnp(3) then cy = cy + 1 end
  cx = mid(0, cx, 2)
  cy = mid(0, cy, 2)

  if btnp(4) then
    local at = slot(cx, cy)
    if board[at] == 0 then
      board[at] = myside
      sfx(0)
      finish()
      if not over then wait = THINK end
    end
  end
end

-- ── how it looks ────────────────────────────────────────────────────────────

local function centre_of(i)
  local x = (i - 1) % 3
  local y = flr((i - 1) / 3)
  return OX + x * CELL + CELL / 2, OY + y * CELL + CELL / 2
end

local function draw_sun(x, y, c)
  circ(x, y, 9, c)
  -- eight rays, by hand: a loop with sin and cos costs more than it buys at
  -- this size, and the diagonals would land on half pixels anyway.
  rect(x - 1, y - 14, 2, 3, c)
  rect(x - 1, y + 12, 2, 3, c)
  rect(x - 14, y - 1, 3, 2, c)
  rect(x + 12, y - 1, 3, 2, c)
  pset(x - 9, y - 9, c) pset(x - 10, y - 10, c) pset(x - 11, y - 11, c)
  pset(x + 9, y - 9, c) pset(x + 10, y - 10, c) pset(x + 11, y - 11, c)
  pset(x - 9, y + 9, c) pset(x - 10, y + 10, c) pset(x - 11, y + 11, c)
  pset(x + 9, y + 9, c) pset(x + 10, y + 10, c) pset(x + 11, y + 11, c)
end

-- A crescent is a disc with a disc taken out of it, which is one circle more
-- than it sounds like and no arcs at all. The taking-out is painted in the
-- background colour, so both circles have to stay well inside the cell — the
-- first pass reached the grid line and quietly rubbed a notch out of it.
local function draw_moon(x, y, c)
  circ(x, y, 11, c)
  circ(x + 6, y - 4, 10, 0)
end

function _draw()
  cls(0)

  if picking then
    print("THE TWINS", (240 - 9 * 4 * 2) / 2, 24, 7, 2)
    print("WHO ARE YOU?", (240 - 12 * 4) / 2, 52, 1)
    -- the two of them, side by side, the chosen one framed
    draw_sun(84, 90, 4)
    draw_moon(156, 90, 6)
    rectb(picksel == 1 and 64 or 136, 70, 40, 40, picksel == 1 and 4 or 6)
    print("SUN", 78, 116, picksel == 1 and 4 or 1)
    print("MOON", 148, 116, picksel == 2 and 6 or 1)
    print("O TO CHOOSE", (240 - 11 * 4) / 2, 138, 3)
    return
  end

  print("YOU " .. wins, 4, 3, myside == SUN and 4 or 6)
  print("THEM " .. losses, 100, 3, myside == SUN and 6 or 4)
  print("DRAW " .. draws, 192, 3, 1)
  line(0, 12, 239, 12, 1)

  -- the board, drawn as four lines rather than nine boxes
  for i = 1, 2 do
    line(OX + i * CELL, OY, OX + i * CELL, OY + 3 * CELL, 1)
    line(OX, OY + i * CELL, OX + 3 * CELL, OY + i * CELL, 1)
  end

  for i = 1, 9 do
    local x, y = centre_of(i)
    if board[i] == SUN then draw_sun(x, y, 4)
    elseif board[i] == MOON then draw_moon(x, y, 6) end
  end

  if not over and wait == 0 then
    rectb(OX + cx * CELL + 1, OY + cy * CELL + 1, CELL - 1, CELL - 1, 7)
  end

  if winline ~= 0 then
    local l = LINES[winline]
    local x0, y0 = centre_of(l[1])
    local x1, y1 = centre_of(l[3])
    line(x0, y0, x1, y1, 7)
  end

  rect(0, SAY, 240, 160 - SAY, 0)
  line(0, SAY, 239, SAY, 1)
  if over then
    local text, c
    if winner == SUN then text, c = "THE SUN CATCHES HER", 4
    elseif winner == MOON then text, c = "THE MOON TAKES IT", 6
    else text, c = "SHE SLIPS AWAY", 7 end
    print(text, (240 - #text * 4) / 2, SAY + 3, c)
    print("O AGAIN   X SWAP SIDE", (240 - 21 * 4) / 2, SAY + 12, 3)
  elseif wait > 0 then
    print("HER TURN", (240 - 8 * 4) / 2, SAY + 7, 1)
  else
    print("O TO PLACE", (240 - 10 * 4) / 2, SAY + 7, 1)
  end
end

function _cover()
  cls(0)
  for i = 1, 2 do
    line(66 + i * 36, 8, 66 + i * 36, 116, 1)
    line(66, 8 + i * 36, 174, 8 + i * 36, 1)
  end
  draw_sun(84, 26, 4)
  draw_moon(156, 62, 6)
  draw_sun(120, 62, 4)
  draw_moon(84, 98, 6)
  draw_sun(156, 98, 4)
  line(84, 26, 156, 98, 7)
  rect(0, 126, 240, 34, 0)
  print("THE TWINS", (240 - 9 * 4 * 4) / 2, 133, 4, 4)
end
