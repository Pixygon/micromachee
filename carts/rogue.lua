-- title: Rogue
-- author: pixygon
-- about: down as far as you can get

-- A dungeon crawl in 120x90 pixels. Rooms joined by corridors, monsters that
-- get meaner the deeper you go, and nothing happens until you move — every
-- turn is yours first, then theirs.
--
-- Six pixels a tile, three-by-five glyphs inside them. @ is you, letters are
-- things that want you dead, > goes down, + is a potion.

local COLS, ROWS, TILE = 20, 15, 6
local MX, MY = 4, 2

local map, seen, vis, roomid, rooms
local px, py, hp, maxhp, atk, def, lvl, xp, depth
local mons, items, msg, msgleft, over

local KIND = { "R", "K", "O", "T" }   -- rat, kobold, orc, troll

local function inb(x, y) return x >= 1 and y >= 1 and x <= COLS and y <= ROWS end
local function say(t) msg, msgleft = t, 14 end

local function blank(v)
  local t = {}
  for y = 1, ROWS do
    t[y] = {}
    for x = 1, COLS do t[y][x] = v end
  end
  return t
end

local function monster_at(x, y)
  for i = 1, #mons do
    if mons[i].x == x and mons[i].y == y then return i end
  end
end

-- ── the dungeon ────────────────────────────────────────────────────────────

local function carve_room(r, id)
  for y = r.y, r.y + r.h - 1 do
    for x = r.x, r.x + r.w - 1 do
      map[y][x] = 1
      roomid[y][x] = id
    end
  end
end

local function corridor(ax, ay, bx, by)
  -- L-shaped, horizontal leg first. Corridors get no room id, so they light
  -- only the square you are standing next to.
  local x, y = ax, ay
  while x ~= bx do
    x = x + (bx > x and 1 or -1)
    if inb(x, y) then map[y][x] = 1 end
  end
  while y ~= by do
    y = y + (by > y and 1 or -1)
    if inb(x, y) then map[y][x] = 1 end
  end
end

local function overlaps(a, b)
  return a.x < b.x + b.w + 1 and a.x + a.w + 1 > b.x
     and a.y < b.y + b.h + 1 and a.y + a.h + 1 > b.y
end

local function generate()
  map, roomid, seen = blank(0), blank(0), blank(false)
  rooms, mons, items = {}, {}, {}

  -- A bounded number of attempts, not "keep trying until it fits": a frame has
  -- an instruction budget and an unlucky seed must not spend all of it.
  for _ = 1, 60 do
    if #rooms >= 6 then break end
    local w = 4 + flr(rnd(4))
    local h = 3 + flr(rnd(3))
    local r = { x = 2 + flr(rnd(COLS - w - 2)), y = 2 + flr(rnd(ROWS - h - 2)), w = w, h = h }
    local ok = true
    for i = 1, #rooms do
      if overlaps(r, rooms[i]) then ok = false break end
    end
    if ok then
      rooms[#rooms + 1] = r
      carve_room(r, #rooms)
    end
  end

  for i = 2, #rooms do
    local a, b = rooms[i - 1], rooms[i]
    corridor(flr(a.x + a.w / 2), flr(a.y + a.h / 2), flr(b.x + b.w / 2), flr(b.y + b.h / 2))
  end

  local first = rooms[1]
  px, py = flr(first.x + first.w / 2), flr(first.y + first.h / 2)

  local last = rooms[#rooms]
  items[#items + 1] = { x = flr(last.x + last.w / 2), y = flr(last.y + last.h / 2), kind = "stairs" }

  -- Monsters and potions go anywhere but the room you arrive in.
  local count = mid(3, 2 + depth, 8)
  for _ = 1, count do
    local r = rooms[2 + flr(rnd(#rooms - 1))]
    if r then
      local tier = 1 + flr(rnd(mid(1, 1 + flr(depth / 2), 4)))
      mons[#mons + 1] = {
        x = r.x + flr(rnd(r.w)), y = r.y + flr(rnd(r.h)),
        hp = 3 + tier * 3 + depth,
        atk = 1 + tier + flr(depth / 2),
        def = flr(tier / 2),
        xp = tier * 4 + depth,
        ch = KIND[tier],
      }
    end
  end
  for _ = 1, 1 + flr(rnd(2)) do
    local r = rooms[1 + flr(rnd(#rooms))]
    if r then
      items[#items + 1] = { x = r.x + flr(rnd(r.w)), y = r.y + flr(rnd(r.h)), kind = "potion" }
    end
  end
end

local function light()
  vis = blank(false)
  local rid = roomid[py][px]
  if rid > 0 then
    -- The room's rectangle grown by one, so its WALLS light up with it. Lighting
    -- only the floor leaves a room hanging in the dark with no edges, which
    -- reads as a bug rather than as unlit stone.
    local r = rooms[rid]
    for y = r.y - 1, r.y + r.h do
      for x = r.x - 1, r.x + r.w do
        if inb(x, y) then vis[y][x] = true; seen[y][x] = true end
      end
    end
  end
  for dy = -1, 1 do
    for dx = -1, 1 do
      local x, y = px + dx, py + dy
      if inb(x, y) then vis[y][x] = true; seen[y][x] = true end
    end
  end
end

-- ── turns ──────────────────────────────────────────────────────────────────

-- Depth is most of it, but a deep level-2 character got further than a shallow
-- one, so both count. Called from everywhere either can change.
local function bump_score()
  score(depth * 100 + lvl * 10)
end

local function level_up()
  while xp >= lvl * 10 do
    xp = xp - lvl * 10
    lvl = lvl + 1
    maxhp = maxhp + 4
    hp = maxhp
    atk = atk + 1
    if lvl % 2 == 0 then def = def + 1 end
    bump_score()
    say("YOU REACH LEVEL " .. lvl)
  end
end

local function hit_monster(i)
  local m = mons[i]
  local dmg = mid(1, atk + flr(rnd(3)) - m.def, 99)
  m.hp = m.hp - dmg
  if m.hp <= 0 then
    say("THE " .. m.ch .. " DIES")
    xp = xp + m.xp
    table.remove(mons, i)
    level_up()
  else
    say("YOU HIT THE " .. m.ch .. " FOR " .. dmg)
  end
end

local function monsters_move()
  for i = #mons, 1, -1 do
    local m = mons[i]
    local dx, dy = px - m.x, py - m.y
    local dist = math.abs(dx) + math.abs(dy)
    if dist == 1 then
      local dmg = mid(1, m.atk + flr(rnd(2)) - def, 99)
      hp = hp - dmg
      say("THE " .. m.ch .. " HITS YOU FOR " .. dmg)
      if hp <= 0 then
        hp = 0
        over = true
        lose()
        say("YOU DIE ON DEPTH " .. depth)
        return
      end
    elseif dist <= 7 then
      -- Close on the longer axis first; if that square is taken, try the other.
      local sx = dx ~= 0 and (dx > 0 and 1 or -1) or 0
      local sy = dy ~= 0 and (dy > 0 and 1 or -1) or 0
      local tries
      if math.abs(dx) > math.abs(dy) then
        tries = { {sx, 0}, {0, sy} }
      else
        tries = { {0, sy}, {sx, 0} }
      end
      for k = 1, 2 do
        local nx, ny = m.x + tries[k][1], m.y + tries[k][2]
        if inb(nx, ny) and map[ny][nx] == 1 and not monster_at(nx, ny)
           and not (nx == px and ny == py) then
          m.x, m.y = nx, ny
          break
        end
      end
    end
  end
end

local function pick_up()
  for i = #items, 1, -1 do
    local it = items[i]
    if it.x == px and it.y == py and it.kind == "potion" then
      hp = mid(1, hp + 6, maxhp)
      say("YOU DRINK A POTION")
      table.remove(items, i)
    end
  end
end

local function on_stairs()
  for i = 1, #items do
    if items[i].kind == "stairs" and items[i].x == px and items[i].y == py then return true end
  end
  return false
end

local function descend()
  depth = depth + 1
  bump_score()
  generate()
  light()
  say("DEPTH " .. depth)
end

local function step(dx, dy)
  local nx, ny = px + dx, py + dy
  if not inb(nx, ny) or map[ny][nx] == 0 then return false end
  local i = monster_at(nx, ny)
  if i then
    hit_monster(i)
  else
    px, py = nx, ny
    pick_up()
  end
  return true
end

function _init()
  depth = 1
  maxhp, hp = 16, 16
  atk, def, lvl, xp = 3, 1, 1, 0
  over = false
  msg, msgleft = "", 0
  generate()
  light()
  say("DEPTH 1")
  bump_score()
end

function _update()
  if over then
    if btnp(4) then _init() end
    return
  end

  local acted = false
  if btnp(0) then acted = step(-1, 0) end
  if btnp(1) then acted = step(1, 0) end
  if btnp(2) then acted = step(0, -1) end
  if btnp(3) then acted = step(0, 1) end

  if btnp(4) and on_stairs() then
    descend()
    return
  end

  if acted then
    monsters_move()
    light()
    if msgleft > 0 then msgleft = msgleft - 1 end
  end
end

-- ── drawing ────────────────────────────────────────────────────────────────

local function glyph(ch, tx, ty, c)
  print(ch, MX + (tx - 1) * TILE + 1, MY + (ty - 1) * TILE + 1, c)
end

function _draw()
  cls(0)

  for y = 1, ROWS do
    for x = 1, COLS do
      if seen[y][x] then
        local sx, sy = MX + (x - 1) * TILE, MY + (y - 1) * TILE
        local lit = vis[y][x]
        if map[y][x] == 0 then
          rect(sx, sy, TILE, TILE, lit and 6 or 1)
        elseif lit then
          pset(sx + 2, sy + 2, 1)     -- a lit floor, just enough to read as one
        end
      end
    end
  end

  for i = 1, #items do
    local it = items[i]
    if vis[it.y][it.x] then
      glyph(it.kind == "stairs" and ">" or "+", it.x, it.y, it.kind == "stairs" and 4 or 5)
    end
  end
  for i = 1, #mons do
    local m = mons[i]
    if vis[m.y][m.x] then glyph(m.ch, m.x, m.y, 2) end
  end
  glyph("@", px, py, 7)

  -- ── the panel ───────────────────────────────────────────────────────────
  rect(0, 92, 128, 36, 0)
  line(0, 92, 127, 92, 1)

  print("HP", 4, 96, 7)
  rectb(13, 95, 42, 7, 1)
  local w = flr(40 * hp / maxhp)
  rect(14, 96, w, 5, hp * 3 <= maxhp and 2 or (hp * 2 <= maxhp and 3 or 5))
  print(hp .. "/" .. maxhp, 59, 96, 7)

  print("ATK " .. atk .. "  DEF " .. def .. "  LV " .. lvl, 4, 105, 6)
  print("DEPTH " .. depth .. "  XP " .. xp .. "/" .. (lvl * 10), 4, 113, 3)

  if over then
    rect(14, 46, 100, 26, 0)
    rectb(14, 46, 100, 26, 2)
    print("YOU DIE ON DEPTH " .. depth, 64 - (17 + #tostring(depth)) * 2, 52, 7)
    print("PRESS O", 50, 62, 3)
  elseif on_stairs() then
    print("O TO GO DOWN", 4, 121, 4)
  elseif msgleft > 0 then
    print(msg, 4, 121, 1)
  end
end

function _cover()
  cls(0)
  -- A room, remembered in dim and lit where you are standing.
  for x = 2, 13 do
    rect(x * 9, 18, 9, 9, 1)
    rect(x * 9, 81, 9, 9, 1)
  end
  for y = 2, 9 do
    rect(18, y * 9, 9, 9, 1)
    rect(117, y * 9, 9, 9, 1)
  end
  for x = 3, 12 do
    for y = 3, 8 do
      pset(x * 9 + 4, y * 9 + 4, 1)
    end
  end

  print("@", 60, 46, 7, 2)
  print("R", 33, 37, 2, 2)
  print("K", 93, 64, 2, 2)
  print(">", 99, 28, 4, 2)
  print("+", 33, 70, 5, 2)

  rect(0, 94, 128, 34, 0)
  print("ROGUE", 34, 102, 2, 3)
end
