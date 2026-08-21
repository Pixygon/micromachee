-- title: Recycler
-- author: pixygon
-- about: collect the discarded. do not consume yourself

-- The board is 16x15 cells of 8 pixels, with the top 8 pixels kept for the
-- score. Everything below works in cells and only multiplies up in _draw, so
-- there is exactly one place where a coordinate becomes a pixel.

local CELL = 8
local COLS = 16
local ROWS = 15
local TOP  = 8

local snake, dir, turn, food, alive, tick, speed, points

-- Put food on a cell the snake is not standing on. Collecting the free cells
-- first (rather than guessing until one is free) means this still returns when
-- the snake has grown to cover most of the board.
local function place_food()
  local taken = {}
  for i = 1, #snake do
    taken[snake[i].y * COLS + snake[i].x] = true
  end
  local free = {}
  for k = 0, COLS * ROWS - 1 do
    if not taken[k] then free[#free + 1] = k end
  end
  if #free == 0 then
    food = nil
    return
  end
  local k = free[flr(rnd(#free)) + 1]
  food = { x = k % COLS, y = flr(k / COLS) }
end

function _init()
  snake  = { {x=8,y=7}, {x=7,y=7}, {x=6,y=7} }
  dir    = { x=1, y=0 }
  turn   = dir
  alive  = true
  tick   = 0
  speed  = 6
  points = 0
  score(0)
  place_food()
end

function _update()
  if not alive then
    if btnp(4) then _init() end
    return
  end

  -- A turn is queued rather than applied at once. Two taps inside a single
  -- step would otherwise let the snake reverse straight into its own neck.
  if btn(0) and dir.x == 0 then turn = { x=-1, y= 0 } end
  if btn(1) and dir.x == 0 then turn = { x= 1, y= 0 } end
  if btn(2) and dir.y == 0 then turn = { x= 0, y=-1 } end
  if btn(3) and dir.y == 0 then turn = { x= 0, y= 1 } end

  tick = tick + 1
  if tick < speed then return end
  tick = 0
  dir = turn

  local head = snake[1]
  local nx, ny = head.x + dir.x, head.y + dir.y

  if nx < 0 or ny < 0 or nx >= COLS or ny >= ROWS then
    alive = false
    lose()
    return
  end
  -- The last segment is skipped: it moves out of the way this same step, so
  -- following your own tail is legal and feels right.
  for i = 1, #snake - 1 do
    if snake[i].x == nx and snake[i].y == ny then
      alive = false
      lose()
      return
    end
  end

  table.insert(snake, 1, { x=nx, y=ny })
  if food and nx == food.x and ny == food.y then
    points = points + 1
    score(points)
    if points % 5 == 0 and speed > 2 then speed = speed - 1 end
    place_food()
  else
    table.remove(snake)
  end
end

function _draw()
  cls(0)
  print("TAKEN " .. points, 2, 1, 7)
  line(0, TOP - 1, 127, TOP - 1, 1)

  if food then
    rect(food.x * CELL + 2, TOP + food.y * CELL + 2, 4, 4, 2)
  end

  for i = 1, #snake do
    local s = snake[i]
    rect(s.x * CELL + 1, TOP + s.y * CELL + 1, CELL - 2, CELL - 2, i == 1 and 4 or 5)
  end

  if not alive then
    rect(24, 52, 80, 24, 0)
    rectb(24, 52, 80, 24, 2)
    print("IT TAKES YOU", 40, 58, 7)
    print("PRESS O", 50, 66, 3)
  end
end

-- The shelf picture. Drawn with the same eight colours and the same screen the
-- game uses, so it follows the colour mode like everything else does.
function _cover()
  cls(0)
  for i = 0, 127, 12 do
    line(0, i, 127, i, 1)
    line(i, 0, i, 127, 1)
  end

  local body = {
    {1,2},{2,2},{3,2},{4,2},{5,2},
    {5,3},{5,4},
    {4,4},{3,4},
    {3,5},{3,6},
    {4,6},{5,6},{6,6},{7,6},
  }
  for i = 1, #body do
    rect(body[i][1] * 12 + 2, body[i][2] * 12 + 2, 10, 10, 5)
  end
  local h = body[#body]
  rect(h[1] * 12 + 2, h[2] * 12 + 2, 10, 10, 4)
  pset(h[1] * 12 + 8, h[2] * 12 + 5, 0)

  circ(8 * 12 + 6, 2 * 12 + 6, 5, 2)

  rect(0, 98, 128, 30, 0)
  line(0, 98, 127, 98, 5)
  print("RECYCLER", 16, 106, 5, 3)
end
