-- title: Farm of Arra
-- author: pixygon
-- about: a plate that carries a whole world. grow it
-- mega: no

-- The one game here that uses the clock on the wall rather than the frame
-- counter. `now()` is real seconds since 1970 and `save()` outlives the widget,
-- so a plot planted before lunch is ripe after it — the console being closed is
-- exactly the same to a growing thing as the console being open.
--
-- Nothing is stored as a countdown. Each plot remembers only WHEN it was
-- planted, and ripeness is `now() - planted >= grow`. A countdown would have to
-- be ticked, and nothing ticks while the bar is shut.

local COLS, ROWS = 4, 3
local CELL = 26
local OX, OY = 12, 22

-- name, seconds to grow, seed cost, sale price, ripe colour
local CROPS = {
  { "MOSS",     60, 3,  7, 4 },
  { "GRAIN",   300, 8, 22, 3 },
  { "BLOOM",  1800, 20, 70, 2 },
}

local planted, kind, cx, cy, coins, pick, note, noteleft

local function slot(x, y) return y * COLS + x end

local function save_plot(i)
  save("p" .. i, planted[i])
  save("k" .. i, kind[i])
end

local function say(t) note, noteleft = t, 90 end

function _init()
  planted, kind = {}, {}
  for i = 0, COLS * ROWS - 1 do
    planted[i] = load("p" .. i) or 0
    kind[i] = load("k" .. i) or 1
  end
  coins = load("coins") or 12
  cx, cy, pick = 0, 0, 1
  note, noteleft = "", 0
  score(coins)
end

-- 0 empty, 1 sown, 2 growing, 3 ripe
local function stage(i)
  if planted[i] == 0 then return 0 end
  local age = now() - planted[i]
  local grow = CROPS[kind[i]][2]
  if age >= grow then return 3 end
  if age >= grow / 2 then return 2 end
  return 1
end

local function left(i)
  local secs = CROPS[kind[i]][2] - (now() - planted[i])
  if secs < 0 then secs = 0 end
  return flr(secs)
end

function _update()
  if btnp(0) then cx = cx - 1 end
  if btnp(1) then cx = cx + 1 end
  if btnp(2) then cy = cy - 1 end
  if btnp(3) then cy = cy + 1 end
  cx = mid(0, cx, COLS - 1)
  cy = mid(0, cy, ROWS - 1)

  if btnp(5) then
    pick = pick % #CROPS + 1
  end

  if btnp(4) then
    local i = slot(cx, cy)
    local st = stage(i)
    if st == 3 then
      coins = coins + CROPS[kind[i]][4]
      planted[i] = 0
      save_plot(i)
      save("coins", coins)
      score(coins)
      sfx(3)
      say("SOLD FOR " .. CROPS[kind[i]][4])
    elseif st == 0 then
      local cost = CROPS[pick][3]
      if coins >= cost then
        coins = coins - cost
        planted[i] = flr(now())
        kind[i] = pick
        save_plot(i)
        save("coins", coins)
        score(coins)
        sfx(4)
        say("PLANTED " .. CROPS[pick][1])
      else
        sfx(1)
        say("NOT ENOUGH COINS")
      end
    else
      say(CROPS[kind[i]][1] .. " IN " .. left(i) .. "S")
    end
  end

  if noteleft > 0 then noteleft = noteleft - 1 end
end

local function draw_plot(i, x, y)
  local st = stage(i)
  rect(x, y, CELL - 2, CELL - 2, 1)
  rectb(x, y, CELL - 1, CELL - 1, 0)

  if st == 1 then
    -- a shoot
    rect(x + 11, y + 15, 2, 6, 5)
    pset(x + 10, y + 14, 5)
    pset(x + 13, y + 14, 5)
  elseif st == 2 then
    rect(x + 11, y + 10, 2, 11, 5)
    rect(x + 7, y + 12, 4, 2, 5)
    rect(x + 13, y + 15, 4, 2, 5)
  elseif st == 3 then
    local c = CROPS[kind[i]][5]
    rect(x + 11, y + 13, 2, 8, 5)
    circ(x + 12, y + 9, 5, c)
    pset(x + 10, y + 7, 7)
  end
end

function _draw()
  cls(0)

  for y = 0, ROWS - 1 do
    for x = 0, COLS - 1 do
      draw_plot(slot(x, y), OX + x * CELL, OY + y * CELL)
    end
  end

  -- the cursor
  rectb(OX + cx * CELL - 1, OY + cy * CELL - 1, CELL + 1, CELL + 1, 7)

  -- ── the panel ───────────────────────────────────────────────────────────
  rect(0, 0, 128, 20, 0)
  line(0, 20, 127, 20, 1)
  print("COINS " .. coins, 2, 3, 4)

  local c = CROPS[pick]
  print("X:" .. c[1], 2, 11, 6)
  print(c[3] .. "C", 74, 11, 1)
  print("->" .. c[4] .. "C", 92, 11, 5)

  rect(0, 100, 128, 28, 0)
  line(0, 100, 127, 100, 1)

  local i = slot(cx, cy)
  local st = stage(i)
  if noteleft > 0 then
    print(note, 2, 104, 7)
  elseif st == 0 then
    print("O TO PLANT", 2, 104, 3)
  elseif st == 3 then
    print("O TO SELL " .. CROPS[kind[i]][1], 2, 104, 5)
  else
    print(CROPS[kind[i]][1] .. " READY IN " .. left(i) .. "S", 2, 104, 1)
  end
  print("IT GROWS WHILE YOU ARE AWAY", 2, 114, 1)
end

function _cover()
  cls(0)
  for y = 0, 2 do
    for x = 0, 3 do
      local px, py = 12 + x * 26, 14 + y * 26
      rect(px, py, 24, 24, 1)
      rect(px + 11, py + 13, 2, 8, 5)
      circ(px + 12, py + 9, 5, (x + y) % 2 == 0 and 4 or 2)
    end
  end
  rect(0, 96, 128, 32, 0)
  print("FARM OF ARRA", 16, 106, 5, 2)
end
