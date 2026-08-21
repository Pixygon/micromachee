-- title: The Signs
-- author: pixygon
-- about: the numbers describe a sign. draw it

-- A nonogram. The clues along a row say how many squares are filled and in what
-- runs, so "3 1" means three together, a gap, then one.
--
-- Layout is the whole difficulty at this size. Eight cells need at most four
-- clues (1-0-1-0-1-0-1-0), each one digit wide, so the clue gutters are sized
-- for exactly that and no more.

local N     = 8
local CELL  = 10
local CLW   = 26          -- left gutter: four clues at six pixels each
local CLH   = 29          -- top gutter: four clues at seven pixels each
local OX    = 11          -- centres the 106-pixel block on a 128-pixel screen
local OY    = 1
local GX    = OX + CLW
local GY    = OY + CLH

local sol, mark, rowclue, colclue, cx, cy, won, moved

-- Runs of filled squares, which is exactly what a clue is.
local function runs(get)
  local out, n = {}, 0
  for i = 1, N do
    if get(i) then n = n + 1
    elseif n > 0 then out[#out + 1] = n; n = 0 end
  end
  if n > 0 then out[#out + 1] = n end
  if #out == 0 then out[1] = 0 end
  return out
end

local function same(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do if a[i] ~= b[i] then return false end end
  return true
end

local function row_runs(t, r) return runs(function(i) return t[r][i] == 1 end) end
local function col_runs(t, c) return runs(function(i) return t[i][c] == 1 end) end

function _init()
  sol, mark = {}, {}
  -- Keep drawing puzzles until one has something in every row and column: an
  -- empty line is a legal nonogram and a dull one to be handed.
  local tries = 0
  repeat
    tries = tries + 1
    local ok = true
    for r = 1, N do
      sol[r] = {}
      for c = 1, N do sol[r][c] = rnd(1) < 0.55 and 1 or 0 end
    end
    for i = 1, N do
      local rsum, csum = 0, 0
      for j = 1, N do rsum = rsum + sol[i][j]; csum = csum + sol[j][i] end
      if rsum == 0 or csum == 0 then ok = false end
    end
  until ok or tries > 20

  for r = 1, N do
    mark[r] = {}
    for c = 1, N do mark[r][c] = 0 end   -- 0 blank · 1 filled · 2 ruled out
  end

  rowclue, colclue = {}, {}
  for i = 1, N do
    rowclue[i] = row_runs(sol, i)
    colclue[i] = col_runs(sol, i)
  end

  cx, cy, won, moved = 1, 1, false, 0
  score(0)
end

-- A line is done when what the player has filled reads as the clue does. That,
-- not "matches the hidden picture", is the real win condition: a nonogram is
-- solved by its numbers.
local function row_done(r) return same(row_runs(mark, r), rowclue[r]) end
local function col_done(c) return same(col_runs(mark, c), colclue[c]) end

local function check_won()
  for i = 1, N do
    if not row_done(i) or not col_done(i) then return false end
  end
  return true
end

function _update()
  if won then
    if btnp(4) then _init() end
    return
  end

  if btnp(0) then cx = cx - 1 end
  if btnp(1) then cx = cx + 1 end
  if btnp(2) then cy = cy - 1 end
  if btnp(3) then cy = cy + 1 end
  cx = mid(1, cx, N)
  cy = mid(1, cy, N)

  if btnp(4) then
    mark[cy][cx] = mark[cy][cx] == 1 and 0 or 1
    moved = moved + 1
  end
  if btnp(5) then
    mark[cy][cx] = mark[cy][cx] == 2 and 0 or 2
    moved = moved + 1
  end

  if check_won() then
    won = true
    -- Fewer moves is better, so the score counts down from a par rather than up.
    score(mid(0, 400 - moved * 2, 400))
  end
end

local function draw_clues()
  for r = 1, N do
    local cl = rowclue[r]
    local done = row_done(r)
    local y = GY + (r - 1) * CELL + 3
    for k = #cl, 1, -1 do
      -- Right-aligned against the grid, last clue nearest the squares.
      local x = GX - 6 * (#cl - k + 1)
      print(cl[k], x, y, done and 1 or 7)
    end
  end
  for c = 1, N do
    local cl = colclue[c]
    local done = col_done(c)
    local x = GX + (c - 1) * CELL + 3
    for k = #cl, 1, -1 do
      local y = GY - 7 * (#cl - k + 1)
      print(cl[k], x, y, done and 1 or 7)
    end
  end
end

function _draw()
  cls(0)
  draw_clues()

  for r = 1, N do
    for c = 1, N do
      local x = GX + (c - 1) * CELL
      local y = GY + (r - 1) * CELL
      local m = mark[r][c]
      if m == 1 then
        rect(x + 1, y + 1, CELL - 1, CELL - 1, 7)
      elseif m == 2 then
        -- A small cross, for squares ruled out on purpose.
        line(x + 3, y + 3, x + CELL - 3, y + CELL - 3, 2)
        line(x + CELL - 3, y + 3, x + 3, y + CELL - 3, 2)
      end
      rectb(x, y, CELL + 1, CELL + 1, 1)
    end
  end

  -- Every fifth line heavier, the way a printed nonogram is ruled.
  for i = 0, N, 4 do
    line(GX + i * CELL, GY, GX + i * CELL, GY + N * CELL, 6)
    line(GX, GY + i * CELL, GX + N * CELL, GY + i * CELL, 6)
  end

  if not won then
    local x = GX + (cx - 1) * CELL
    local y = GY + (cy - 1) * CELL
    rectb(x - 1, y - 1, CELL + 3, CELL + 3, 4)
  end

  if won then
    rect(24, 54, 80, 22, 0)
    rectb(24, 54, 80, 22, 5)
    print("THE SIGN SHOWS", 36, 59, 7)
    print("O FOR ANOTHER", 38, 67, 3)
  else
    print("O FILL   X RULE OUT", 20, 115, 1)
  end
end

function _cover()
  cls(0)
  -- A solved little picture: the numbers describe it, so the cover shows both.
  local grid = {
    "..####..",
    ".#....#.",
    "#.#..#.#",
    "#......#",
    "#.#..#.#",
    "#..##..#",
    ".#....#.",
    "..####..",
  }
  for r = 1, 8 do
    for c = 1, 8 do
      local x, y = 28 + (c - 1) * 10, 8 + (r - 1) * 10
      if grid[r]:sub(c, c) == "#" then
        rect(x, y, 9, 9, 7)
      else
        rectb(x, y, 10, 10, 1)
      end
    end
  end
  print("4", 20, 11, 6)
  print("1 1", 12, 21, 6)
  print("1 1 1", 4, 31, 6)
  print("1 1", 12, 41, 6)

  rect(0, 96, 128, 32, 0)
  print("THE SIGNS", 10, 104, 4, 3)
end
