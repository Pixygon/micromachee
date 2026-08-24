-- title: Veilwalkers
-- author: pixygon
-- about: the last lineage of Caul. turn off the Veil
-- mega: no

-- The first pearl, at 128x128. Caul is the genesis-island under the Veil — the
-- magic — and its people are the Veilwalkers. You lead the last lineage of four,
-- each born under one of the Nine Signs, out of the settlement, across the
-- wilds, to the Pillar of Light. Reaching it and turning the Veil off is the
-- first apocalypse: Caul ends and Amebrak is born. That is the whole arc, and
-- it is a real ending rather than a score.
--
-- Everything shares one 32x24 tile map. The overworld reads it for collision
-- and draws a camera window of it; the town is the same map with houses for
-- walls and people standing on the path; encounters fire on the grass. Three
-- states — WORLD, TALK, BATTLE — and a couple of end cards. No second map format
-- and no room table: one grid is the world.
--
-- The four signs are the party and the party is four roles, straight from the
-- Codex's own descriptions of the signs:
--   WHALE     the foundation everything rests on   — most HP, shields the line
--   SERPENT   coiling, cunning, agile              — fast, strikes twice
--   FIREKEEPER protect the dying light, ruin all   — the Veil-fire, hits hard
--   SPARROW   the hope that guides to the temple   — mends the others

local TILE = 8
local MAPW, MAPH = 32, 24
local VIEWW, VIEWH = 16, 13         -- tiles shown; the rest is HUD

-- The island. # tree/wall, ~ water, . grass (encounters), = path (safe),
-- H shrine (heal), P pillar, and lowercase letters are people to talk to.
local MAP = {
  "################################",
  "#===========#........~~~~~~~~~~~#",
  "#=a=b=====c=#..........~~~~~~~~~#",
  "#=========H=#####.###.....~~~~~~#",
  "#===========#...#.#.#........~~~#",
  "#=====d=====gg..............~~~~#",
  "#===========#...............#####",
  "#####==######......#####........#",
  "#....==........###..#...#..####.#",
  "#....==..####..#.#..#.#.#..#..#.#",
  "#....==..#..#..#.#....#....#..#.#",
  "#....==.....#..#.###.####..####.#",
  "#....==########..................",
  "#....==.......................e.#",
  "#....========............########",
  "#...........=====.......#.......#",
  "#..~~~~........=========.....B...#",
  "#.~~~~~~~........#####.==........#",
  "#.~~~~~~~..........#...==....P...#",
  "#..~~~~~..........#.#..==........#",
  "#.................#.#..==........#",
  "#.....f...........#....==........#",
  "#=====================.==========#",
  "################################",
}

-- Who stands on the lettered tiles, and what they say. Lore first, because a
-- town that only points at the dungeon is a menu with houses.
local FOLK = {
  a = { "ELDER MORN", "the veil is the light", "we are born inside it", "and we give it back" },
  b = { "KEEPER", "nine signs turn above caul", "you four were born under", "whale serpent flame sparrow" },
  c = { "CHILD", "is it true the pillar", "eats the whole sky?", "grandmother walked in once" },
  d = { "SMITH", "your blades are old.", "older than the island.", "they were always leaving." },
  e = { "HERMIT", "past the wilds a ward stands", "it wears a sign that is not", "yours. it will not simply move" },
  f = { "FISHER", "the water does not end.", "nothing here does.", "it only becomes the next thing" },
}

-- ── party: the four signs ────────────────────────────────────────────────────

local function hero(name, sign, hp, mp, atk, def, spd, skill, cost, kind, col)
  return {
    name = name, sign = sign, hp = hp, maxhp = hp, mp = mp, maxmp = mp,
    atk = atk, def = def, spd = spd, skill = skill, cost = cost,
    kind = kind, col = col, alive = true, guard = false, xp = 0, lvl = 1,
  }
end

local party
local function new_party()
  party = {
    hero("BRUK", "WHALE", 46, 6, 8, 7, 3, "TIDE", 3, "shield", 6),
    hero("SIB", "SERPENT", 30, 8, 8, 3, 9, "COIL", 3, "twice", 5),
    hero("VAEL", "FLAME", 26, 12, 6, 2, 5, "FLAME", 4, "burn", 2),
    hero("WREN", "SPARROW", 24, 12, 5, 3, 7, "GRACE", 4, "heal", 4),
  }
end

-- ── enemies ──────────────────────────────────────────────────────────────────

-- name, hp, atk, def, spd, colour, xp, and whether flame burns it worse
local FOES = {
  { "VEIL WISP", 14, 6, 1, 6, 6, 4, true },
  { "HUSK", 22, 7, 4, 3, 1, 6, true },
  { "DRIFTER", 18, 8, 3, 5, 3, 5, false },
}
local WARD = { "THE WARD", 120, 12, 6, 6, 4, 0, false }

-- ── state ────────────────────────────────────────────────────────────────────

local px, py, step, facing, tick
local state, msg, msgi, msgwho
local wardbeaten, veiloff

-- battle
local foes, order, turn, sel, cmd, target, log, logt, bmenu, anim, wardfight, result

local function tile(x, y)
  if x < 0 or y < 0 or x >= MAPW or y >= MAPH then return "#" end
  return MAP[y + 1]:sub(x + 1, x + 1)
end

local function walkable(x, y)
  local t = tile(x, y)
  return t == "=" or t == "." or t == "H" or t == "g"
      or t == "P" or t == "B"
end

local function folk_at(x, y)
  local t = tile(x, y)
  return FOLK[t] and t or nil
end

function _init()
  new_party()
  px, py = 1, 1
  step, facing, tick = 0, 3, 0
  state, msg = "world", nil
  wardbeaten, veiloff = false, false
  score(0)
end

-- ── the overworld ────────────────────────────────────────────────────────────

local function try_move(dx, dy)
  facing = dx < 0 and 0 or dx > 0 and 1 or dy < 0 and 2 or 3
  local nx, ny = px + dx, py + dy
  -- Talk by walking into someone.
  local who = folk_at(nx, ny)
  if who then
    msg, msgi, msgwho = FOLK[who], 1, who
    state = "talk"
    sfx(0)
    return
  end
  if not walkable(nx, ny) then return end
  px, py = nx, ny

  -- The ward blocks the last path to the pillar until it is beaten.
  if tile(px, py) == "B" and not wardbeaten then
    start_battle(true)
    return
  end
  if tile(px, py) == "H" then heal_party() sfx(6) end
  if tile(px, py) == "P" then
    if wardbeaten then
      veiloff = true
      state = "win"
      win()
      sfx(6)
    else
      msg, msgi, msgwho = { "THE PILLAR", "it will not open while", "the ward still stands" }, 1, nil
      state = "talk"
    end
    return
  end

  -- Grass is where the island is least settled, so that is where things find
  -- you. Not on the very first steps out of town.
  if tile(px, py) == "." and rnd(1) < 0.10 then
    start_battle(false)
  end
end

function heal_party()
  for i = 1, #party do
    local h = party[i]
    h.hp, h.mp, h.alive = h.maxhp, h.maxmp, true
  end
end

-- ── battle ───────────────────────────────────────────────────────────────────

function start_battle(isward)
  wardfight = isward
  foes = {}
  if isward then
    local w = WARD
    foes[1] = { name = w[1], hp = w[2], maxhp = w[2], atk = w[3], def = w[4],
                spd = w[5], col = w[6], xp = w[7], burns = w[8], alive = true }
  else
    local n = 1 + flr(rnd(3))
    for i = 1, n do
      local f = FOES[1 + flr(rnd(#FOES))]
      foes[i] = { name = f[1], hp = f[2], maxhp = f[2], atk = f[3], def = f[4],
                  spd = f[5], col = f[6], xp = f[7], burns = f[8], alive = true }
    end
  end
  build_order()
  turn, sel, cmd, target = 1, 1, 1, 1
  bmenu, anim, result = true, 0, nil
  log, logt = "", 0
  state = "battle"
  sfx(2)
end

function build_order()
  -- Everyone alive, fastest first, re-sorted each round. Heroes are 1..4 and
  -- foes are 101.. so one number says which side an actor is on.
  order = {}
  for i = 1, #party do if party[i].alive then order[#order + 1] = i end end
  for i = 1, #foes do if foes[i].alive then order[#order + 1] = 100 + i end end
  for i = 2, #order do
    local a = order[i]
    local sa = (a > 100 and foes[a - 100].spd or party[a].spd)
    local j = i - 1
    while j >= 1 do
      local b = order[j]
      local sb = (b > 100 and foes[b - 100].spd or party[b].spd)
      if sb >= sa then break end
      order[j + 1] = order[j]
      j = j - 1
    end
    order[j + 1] = a
  end
  turn = 1
end

local function actor(id)
  if id > 100 then return foes[id - 100] else return party[id] end
end

local function foes_alive()
  local n = 0
  for i = 1, #foes do if foes[i].alive then n = n + 1 end end
  return n
end

local function party_alive()
  local n = 0
  for i = 1, #party do if party[i].alive then n = n + 1 end end
  return n
end

local function first_live_foe()
  for i = 1, #foes do if foes[i].alive then return i end end
  return 1
end

local function say(t) log, logt = t, 40 end

local function hurt(defender, amount)
  amount = flr(amount)
  if amount < 1 then amount = 1 end
  defender.hp = defender.hp - amount
  if defender.hp <= 0 then
    defender.hp, defender.alive = 0, false
  end
  return amount
end

local function damage(atk, def, guard)
  local base = atk - flr(def / 2)
  base = base + flr(rnd(3)) - 1
  if guard then base = flr(base / 2) end
  return base
end

-- One hero's chosen action, then the turn advances. Enemies act on their own.
local function do_hero(h, action)
  h.guard = false
  if action == "strike" then
    local f = foes[target]
    if not f.alive then target = first_live_foe() f = foes[target] end
    local d = hurt(f, damage(h.atk, f.def, false))
    say(h.name .. " HITS " .. f.name .. " " .. d)
    sfx(1)
  elseif action == "guard" then
    h.guard = true
    say(h.name .. " GUARDS")
    sfx(0)
  elseif action == "skill" then
    if h.mp < h.cost then say("NO SIGN LEFT") return false end
    h.mp = h.mp - h.cost
    if h.kind == "heal" then
      -- the most hurt ally, or a fallen one raised at half
      local who, worst = nil, 1e9
      for i = 1, #party do
        local a = party[i]
        if not a.alive then who = a break end
        if a.hp < a.maxhp and a.hp - a.maxhp < worst then worst = a.hp - a.maxhp who = a end
      end
      who = who or h
      local amt = 14 + h.atk
      if not who.alive then who.alive = true amt = flr(who.maxhp / 2) end
      who.hp = mid(0, who.hp + amt, who.maxhp)
      say(h.name .. " MENDS " .. who.name)
      sfx(6)
    elseif h.kind == "shield" then
      for i = 1, #party do party[i].guard = true end
      say(h.name .. " SHIELDS THE LINE")
      sfx(6)
    elseif h.kind == "twice" then
      local f = foes[target]
      if not f.alive then target = first_live_foe() f = foes[target] end
      local d1 = hurt(f, damage(h.atk, f.def, false))
      local d2 = f.alive and hurt(f, damage(h.atk, f.def, false)) or 0
      say(h.name .. " COILS " .. (d1 + d2))
      sfx(1)
    elseif h.kind == "burn" then
      -- the Veil-fire: every foe, worse on what the Veil made
      for i = 1, #foes do
        local f = foes[i]
        if f.alive then
          local d = damage(h.atk + 6, f.def, false)
          if f.burns then d = flr(d * 1.6) end
          hurt(f, d)
        end
      end
      say(h.name .. " BURNS THEM ALL")
      sfx(2)
    end
  end
  return true
end

local function enemy_turn(f)
  -- Mostly the frailest living hero; sometimes, if it is the ward, everyone.
  if wardfight and rnd(1) < 0.3 then
    say(f.name .. " SWEEPS ALL")
    for i = 1, #party do
      local h = party[i]
      if h.alive then hurt(h, damage(f.atk - 2, h.def, h.guard)) end
    end
    sfx(5)
    return
  end
  local who, low = nil, 1e9
  for i = 1, #party do
    local h = party[i]
    if h.alive and h.hp < low then low = h.hp who = h end
  end
  if not who then return end
  local d = hurt(who, damage(f.atk, who.def, who.guard))
  say(f.name .. " HITS " .. who.name .. " " .. d)
  sfx(5)
end

local function next_turn()
  turn = turn + 1
  if turn > #order then build_order() end
  -- skip the dead
  local guard = 0
  while turn <= #order and not actor(order[turn]).alive do
    turn = turn + 1
    guard = guard + 1
    if turn > #order then build_order() end
    if guard > 40 then break end
  end
end

local function win_battle()
  local total = 0
  for i = 1, #foes do total = total + foes[i].xp end
  for i = 1, #party do
    local h = party[i]
    if h.alive then
      h.xp = h.xp + total
      -- a level every 20, capped so numbers stay legible
      while h.xp >= h.lvl * 20 and h.lvl < 20 do
        h.xp = h.xp - h.lvl * 20
        h.lvl = h.lvl + 1
        h.maxhp = h.maxhp + 4
        h.atk = h.atk + 1
        if h.lvl % 2 == 0 then h.maxmp = h.maxmp + 2 end
        h.hp = h.maxhp
        h.mp = h.maxmp
      end
    end
  end
  score(party[1].lvl + party[2].lvl + party[3].lvl + party[4].lvl)
  if wardfight then wardbeaten = true end
  result = "won"
end

local CMDS = { "STRIKE", "SIGN", "GUARD" }

function _update()
  tick = tick + 1

  if state == "world" then
    if step > 0 then step = step - 1 end
    local dx, dy = 0, 0
    if btn(0) then dx = -1 elseif btn(1) then dx = 1
    elseif btn(2) then dy = -1 elseif btn(3) then dy = 1 end
    if (dx ~= 0 or dy ~= 0) and step == 0 then
      try_move(dx, dy)
      step = 6
    end

  elseif state == "talk" then
    if btnp(4) or btnp(5) then
      msgi = msgi + 1
      if msgi > #msg then state = "world" else sfx(0) end
    end

  elseif state == "battle" then
    update_battle()

  elseif state == "win" or state == "over" then
    if btnp(4) then _init() end
  end
end

function update_battle()
  if logt > 0 then logt = logt - 1 end

  -- resolve end of battle after the last message has been read a moment
  if result and logt <= 0 then
    if result == "won" then
      if veiloff then return end
      state = "world"
    else
      state = "over"
      lose()
    end
    result = nil
    return
  end
  if result then return end

  if anim > 0 then
    anim = anim - 1
    if anim == 0 then
      -- check outcomes after an action resolves
      if foes_alive() == 0 then win_battle() sfx(6) return end
      if party_alive() == 0 then result = "lost" say("THE LINEAGE FALLS") return end
      next_turn()
    end
    return
  end

  local id = order[turn]
  if not id then build_order() return end
  local one = actor(id)
  if not one.alive then next_turn() return end

  if id > 100 then
    -- enemy acts, with a short beat so you can read it
    enemy_turn(one)
    anim = 22
    return
  end

  -- a hero's menu
  if btnp(2) then sel = (sel - 2) % 3 + 1 sfx(0) end
  if btnp(3) then sel = sel % 3 + 1 sfx(0) end
  if btnp(1) and CMDS[sel] == "STRIKE" then
    target = target % #foes + 1
    while not foes[target].alive do target = target % #foes + 1 end
    sfx(0)
  end
  if btnp(4) then
    local h = one
    if CMDS[sel] == "STRIKE" then
      if do_hero(h, "strike") then anim = 22 end
    elseif CMDS[sel] == "GUARD" then
      do_hero(h, "guard") anim = 14
    elseif CMDS[sel] == "SIGN" then
      if do_hero(h, "skill") then anim = 22 else sfx(5) end
    end
  end
end

-- ══ drawing ══════════════════════════════════════════════════════════════════

local function draw_tile(t, sx, sy)
  if t == "#" then
    rect(sx, sy, 8, 8, 5) rect(sx + 1, sy, 6, 5, 5)
    rect(sx + 3, sy + 5, 2, 3, 3)                       -- a tree
  elseif t == "~" then
    rect(sx, sy, 8, 8, 6)
    if (sx + sy + flr(tick / 8)) % 16 < 8 then pset(sx + 2, sy + 3, 7) end
  elseif t == "." then
    rect(sx, sy, 8, 8, 1) pset(sx + 2, sy + 5, 5) pset(sx + 5, sy + 2, 5)
  elseif t == "H" then
    rect(sx, sy, 8, 8, 1) rect(sx + 2, sy + 1, 4, 6, 7) rect(sx + 3, sy + 2, 2, 2, 4)
  elseif t == "P" then
    rect(sx, sy, 8, 8, 1) rect(sx + 3, sy - 2, 2, 12, 4) pset(sx + 3, sy, 7)
  elseif t == "B" then
    rect(sx, sy, 8, 8, 1)
    if not wardbeaten then rect(sx + 1, sy + 1, 6, 6, 2) pset(sx + 3, sy + 3, 4) end
  else
    -- path, gate, and anyone standing on it
    rect(sx, sy, 8, 8, 1)
    if t ~= "=" and t ~= "g" then rect(sx, sy, 8, 8, 0) end
  end
end

local function draw_person(sx, sy, c)
  rect(sx + 2, sy + 1, 4, 3, c)      -- head
  rect(sx + 2, sy + 4, 4, 3, 7)      -- robe
  pset(sx + 3, sy + 2, 0)
end

local function draw_world()
  cls(1)
  local camx = mid(0, px - VIEWW / 2, MAPW - VIEWW)
  local camy = mid(0, py - VIEWH / 2, MAPH - VIEWH)
  camx, camy = flr(camx), flr(camy)

  for ry = 0, VIEWH - 1 do
    for rx = 0, VIEWW - 1 do
      local mx, my = camx + rx, camy + ry
      local sx, sy = rx * TILE, ry * TILE + 12
      local t = tile(mx, my)
      draw_tile(t, sx, sy)
      local who = FOLK[t] and t
      if who then draw_person(sx, sy, 3) end
    end
  end

  -- the party lead, always centred-ish
  local hsx = (px - camx) * TILE
  local hsy = (py - camy) * TILE + 12
  draw_person(hsx, hsy, 4)
  -- a facing pip
  local fx = { [0] = -1, [1] = 8, [2] = 3, [3] = 3 }
  local fy = { [0] = 3, [1] = 3, [2] = -1, [3] = 8 }
  pset(hsx + fx[facing], hsy + fy[facing], 7)

  rect(0, 0, 128, 12, 0)
  line(0, 11, 127, 11, 5)
  print("CAUL", 2, 3, 7)
  if wardbeaten then print("THE WARD IS DOWN", 44, 3, 4)
  else print("FIND THE PILLAR", 46, 3, 6) end
end

local function draw_box(x, y, w, h, edge)
  rect(x, y, w, h, 0)
  rectb(x, y, w, h, edge or 5)
end

local function draw_talk()
  draw_world()
  draw_box(4, 82, 120, 42, 6)
  -- A named speaker gets their name in the header; the body lines reveal one at
  -- a time as O is pressed, oldest at the top.
  local yy = 86
  if msgwho then
    print(msg[1], 8, yy, 4)
    yy = yy + 10
  end
  local first = msgwho and 2 or 1
  local last = first + msgi - 1
  for i = first, mid(first, last, #msg) do
    print(msg[i], 8, yy, 7)
    yy = yy + 8
  end
  print("O", 116, 117, 3)
end

local function bar(x, y, w, cur, max, c)
  rect(x, y, w, 3, 1)
  if max > 0 then rect(x, y, flr(w * mid(0, cur, max) / max), 3, c) end
end

local function draw_battle()
  cls(0)
  -- foes across the top
  local n = #foes
  for i = 1, n do
    local f = foes[i]
    local fx = flr((i - 0.5) * 128 / n)
    local fy = 30
    if f.alive then
      if wardfight then
        rect(fx - 12, fy - 10, 24, 22, f.col)
        rect(fx - 6, fy - 4, 4, 4, 4) rect(fx + 2, fy - 4, 4, 4, 4)
        rect(fx - 8, fy + 14, 16, 3, 2)
      else
        rect(fx - 6, fy - 6, 12, 12, f.col)
        pset(fx - 3, fy - 2, 0) pset(fx + 3, fy - 2, 0)
      end
      -- a marker over the strike target when a hero is choosing
      if order[turn] and order[turn] <= 100 and CMDS[sel] == "STRIKE" and target == i then
        rect(fx - 2, fy - 14, 4, 3, 4)
      end
      bar(fx - 12, fy + 18, 24, f.hp, f.maxhp, 2)
    else
      print("X", fx - 2, fy - 2, 5)
    end
  end

  -- the log
  if logt > 0 or result then
    draw_box(4, 52, 120, 12, 6)
    print(log, 8, 55, 7)
  end

  -- the party, four rows at the bottom
  local base = 70
  for i = 1, #party do
    local h = party[i]
    local y = base + (i - 1) * 14
    local acting = order[turn] and order[turn] == i and not result and anim == 0
    if acting then rect(0, y - 1, 128, 13, h.alive and 1 or 0) end
    local c = h.alive and h.col or 5
    print(h.name, 2, y, c)
    if not h.alive then print("DOWN", 2, y + 6, 5)
    else
      bar(30, y + 1, 34, h.hp, h.maxhp, 2)
      bar(30, y + 6, 34, h.mp, h.maxmp, 6)
      print(h.hp .. "", 66, y, 7)
    end
    if acting then draw_menu(h, 88, y) end
  end
end

function draw_menu(h, x, y)
  for i = 1, 3 do
    local c = (i == sel) and 4 or 1
    if CMDS[i] == "SIGN" then
      print((i == sel and ">" or " ") .. h.skill, x, y + (i - 1) * 4 - 4, h.mp >= h.cost and c or 5)
    else
      print((i == sel and ">" or " ") .. CMDS[i], x, y + (i - 1) * 4 - 4, c)
    end
  end
end

function draw_win()
  cls(0)
  -- the Veil goes dark: the screen empties as the pillar rises
  local t = tick % 200
  for i = 0, 40 do
    local a = (i * 97) % 128
    local b = (i * 53) % 90 + 12
    if (i * 7 + flr(tick / 3)) % 40 > (tick / 3) % 40 then pset(a, b, 1) end
  end
  rect(61, 20, 6, 100, 4)
  rect(63, 10, 2, 110, 7)
  draw_box(10, 44, 108, 40, 4)
  print("THE VEIL GOES DARK", 22, 50, 4)
  print("CAUL ENDS.", 44, 60, 7)
  print("AMEBRAK IS BORN.", 30, 68, 6)
  print("PRESS O", 50, 76, 3)
end

function _draw()
  if state == "world" then draw_world()
  elseif state == "talk" then draw_talk()
  elseif state == "battle" then draw_battle()
  elseif state == "win" then draw_win()
  elseif state == "over" then
    cls(0)
    draw_box(14, 50, 100, 28, 2)
    print("THE LINEAGE FALLS", 24, 58, 2)
    print("PRESS O", 50, 68, 3)
  end
end

function _cover()
  -- Drawn on purpose rather than a screenshot: the pillar, the shore, and the
  -- four walkers in their sign colours, which is what the game is about.
  cls(1)
  rect(0, 96, 128, 32, 6)
  rect(60, 8, 8, 100, 4)
  rect(63, 0, 2, 112, 7)
  for i = 0, 3 do draw_person(30 + i * 18, 84, ({ 6, 5, 2, 4 })[i + 1]) end
  rect(0, 102, 128, 26, 0)
  print("VEILWALKERS", (128 - 11 * 4 * 2) / 2, 110, 6, 2)
end
