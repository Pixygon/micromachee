-- title: Veilwalkers
-- author: pixygon
-- about: gather the four aspects. turn off the Veil
-- mega: no
-- price: 500

-- The first pearl, as a campaign. Caul is the genesis-island under the Veil and
-- its people are the Veilwalkers; you lead the last lineage of four, each born
-- under one of the Nine Signs. To reach the Pillar of Light and turn the Veil
-- off — the first apocalypse, where Caul ends and Amebrak is born — you must
-- first climb four towers and take from each the aspect of a sign the four of
-- you were not born under. Only then does the final gate open, and the Tower
-- itself is what waits behind it.
--
-- This is a bundled campaign cart, above the 24K shelf cap on purpose: an
-- overworld, three towns with shops, procedurally generated caves and towers,
-- turn-based battle, equippable gear, portraits and menus, and progress that
-- saves. It is built out of a few reused ideas rather than many one-off ones:
--   * every place is a grid of tile characters — authored maps and generated
--     dungeons are the same structure, so movement, collision, drawing and
--     encounters are written once
--   * one dungeon generator makes both caves and tower floors, parameterised
--   * the four party roles are four of the Nine Signs, straight from the Codex
--   * save/load packs the whole run into one string

local TILE = 8
local VW, VH = 30, 18               -- tiles shown; a 16px HUD strip on top
local FPS = 30

-- ── tiles ────────────────────────────────────────────────────────────────────
-- Walls block; floors walk; some floors roll for an encounter. Special tiles do
-- something when you step on them, resolved in step_special().
local BLOCK = { ["#"] = true, ["~"] = true, ["T"] = true }
local ENCTILE = { ["."] = true, [","] = true }   -- grass, cave floor

-- ── data: gear ───────────────────────────────────────────────────────────────
-- id -> name, slot (1 weapon, 2 armour), bonus, price. Found in caves and sold
-- in shops; a hero's two slots point at ids, 0 for empty.
local GEAR = {
  { "RUST EDGE", 1, 2, 12 },
  { "VEIL BLADE", 1, 5, 45 },
  { "TIDE SPEAR", 1, 9, 130 },
  { "STAR IRON", 1, 15, 340 },
  { "CLOTH WRAP", 2, 2, 12 },
  { "SCALE COAT", 2, 5, 45 },
  { "WARD MAIL", 2, 9, 130 },
  { "LIGHTPLATE", 2, 15, 340 },
}

-- ── data: the four aspects, one per tower ────────────────────────────────────
-- Each is a sign the party was NOT born under, and each is a party-wide passive
-- and a key the final gate reads. Earned as a bitmask.
local ASPECTS = {
  { "GOLEM", "stone", "+def all" },
  { "BEAST", "fury", "+atk all" },
  { "SUN", "warmth", "+life all" },
  { "MOON", "veil", "+sign all" },
}

-- ── data: enemies ────────────────────────────────────────────────────────────
-- name, hp, atk, def, spd, colour, xp, gold, flame-weak
local FOES = {
  wisp   = { "VEIL WISP", 16, 6, 1, 6, 6, 4, 3, true },
  husk   = { "HUSK", 26, 8, 4, 3, 1, 7, 5, true },
  drift  = { "DRIFTER", 22, 9, 3, 5, 3, 6, 4, false },
  maw    = { "STONE MAW", 40, 11, 7, 2, 5, 12, 10, false, "atkdn" },
  shade  = { "SHADE", 30, 13, 3, 7, 2, 14, 9, true, "poison" },
}
-- tower bosses: one per tower, in tower order; grant ASPECTS[i]
local WARDS = {
  { "GOLEM WARD", 110, 13, 9, 3, 5, 60, 60, false, "defdn" },
  { "BEAST WARD", 130, 18, 5, 8, 3, 80, 80, false, "atkdn" },
  { "SUN WARD", 150, 15, 7, 6, 4, 100, 100, true, "burn" },
  { "MOON WARD", 175, 17, 8, 7, 6, 130, 130, true, "slow" },
}
local TOWER = { "THE TOWER", 240, 22, 10, 8, 4, 0, 0, false, "poison" }

-- ── the overworld ────────────────────────────────────────────────────────────
-- Letters/digits are portals and features (see PORTAL/step_special). Caul is at
-- the top-left; the towns and towers spread across the wilds; the final gate Z
-- sits before the Pillar and opens only with all four aspects.
local OVER = {
  "############################################",
  "#===A===#....,,,,....########....~~~~~~~~~~~#",
  "#=======#..,,,,,,,,....#.....1..~~~~~~~~~~~~#",
  "#===H===#....,,,,....#....#....#..~~~~~~~~~~#",
  "#=======########.........#....#....~~~~~~~~~#",
  "#=====x==....#.......###.......#......~~~~~~#",
  "#=======.....#..,,,,..#....###........,,,,,,#",
  "########.....#..,,,,..#......#....,...,,,,,,#",
  "#....,,,,,,..#........#......#....,,,,,,,,,,,#",
  "#..,,,,,,,,,,........,,,,....#....,,,2,,,,,,,#",
  "#....,,,,,,..######.,,,,,,,..#....,,,,,,,,,,,#",
  "#............#....#..,,,,....######.....#####",
  "#.....##.....#....#.........,,,,........#...#",
  "#..,,,,,,....#....#..,,,,,,,,,,,,....#...#.C.#",
  "#,,,,,,,,,,..#....########.,,,,......#...#===#",
  "#..,,,,,,....#............#....#....y#...#===#",
  "#....,,......#....3....#..#....#.....#...#####",
  "#....##......#........#...#....#.,,,,,,......#",
  "#............#.####...#...####...,,,,,,..###.#",
  "#..,,,,,,,,,,....#....#......#...,,,,,,....4.#",
  "#,,,,,,,,,,,,....#........#..#.......#.......#",
  "#..,,,,,,,,,.....########.#..######..#..ZP..#",
  "#............................#...........####",
  "############################################",
}

-- ── towns: small authored interiors ──────────────────────────────────────────
-- S shop, I inn (heal), s save shrine, o the way out, letters are folk.
local CAUL = {
  "##########+#########",
  "#=================H#",
  "#==a===========b===#",
  "#=====s============#",
  "#==================#",
  "#=========c========#",
  "#==================#",
  "####################",
}
local PORT = {
  "##########+#########",
  "#===S=========I====#",
  "#=====d============#",
  "#==============e===#",
  "#=====s============#",
  "#=========f========#",
  "#==================#",
  "####################",
}
local HOLD = {
  "##########+#########",
  "#==S====I=========#",
  "#=========g========#",
  "#===s==============#",
  "#=======h==========#",
  "#==================#",
  "#==================#",
  "####################",
}

local FOLK = {
  a = { "ELDER MORN", "the veil is the light.", "we are born inside it,", "and we give it back." },
  b = { "KEEPER", "four towers stand in the", "wilds. each holds an aspect", "of a sign not yours." },
  c = { "CHILD", "past the last gate", "is the pillar. it eats", "the whole sky, they say." },
  d = { "TRADER", "gear wears out like", "everything on caul.", "buy what the deep gives up." },
  e = { "SAILOR", "the water does not end.", "nothing here does.", "it becomes the next thing." },
  f = { "WIDOW", "my line walked the towers", "and did not come back.", "yours might. carry them." },
  g = { "WARDEN", "the moon tower is cruel.", "come stone-warded first,", "or do not come at all." },
  h = { "SEER", "when all four aspects burn", "in you, the last gate", "will know, and open." },
}

-- ── party: four of the Nine Signs ────────────────────────────────────────────
local function hero(name, sign, hp, mp, atk, def, spd, skill, cost, kind, col)
  return { name = name, sign = sign, hp = hp, maxhp = hp, mp = mp, maxmp = mp,
    atk = atk, def = def, spd = spd, skill = skill, cost = cost, kind = kind,
    col = col, alive = true, guard = false, xp = 0, lvl = 1, wpn = 0, arm = 0,
    job = 0, st = {} }
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

-- effective stats after gear and aspects
local aspbits
local function has_aspect(i) return aspbits % (2 ^ i) >= 2 ^ (i - 1) end
local function st_atk(c) return (stat(c, "atkup") and 3 or 0) - (stat(c, "atkdn") and 3 or 0) end
local function st_def(c) return (stat(c, "defup") and 5 or 0) - (stat(c, "defdn") and 3 or 0) end
local function st_spd(c) return (stat(c, "haste") and 4 or 0) - (stat(c, "slow") and 3 or 0) end

local function eatk(h)
  local b = h.atk + (h.wpn > 0 and GEAR[h.wpn][3] or 0) + job_of(h)[2] + st_atk(h)
  if has_aspect(2) then b = b + 3 end                 -- BEAST
  return b
end
local function edef(h)
  local b = h.def + (h.arm > 0 and GEAR[h.arm][3] or 0) + job_of(h)[3] + st_def(h)
  if has_aspect(1) then b = b + 3 end                 -- GOLEM
  return b
end
local function espd(h) return h.spd + job_of(h)[4] + st_spd(h) end
-- foes carry status too
local function fatk(f) return f.atk + st_atk(f) end
local function fdef(f) return f.def + st_def(f) end
local function fspd(f) return f.spd + st_spd(f) end

-- Each class (the hero's sign) has a small skill tree, unlocked by level. A
-- skill is {name, mp cost, unlock level, effect kind, power}. The battle SIGN
-- menu lists the ones a hero has grown into.
local SKILLS = {
  WHALE = {
    { "TIDE", 3, 1, "shield", 0 }, { "CRASH", 5, 4, "hit", 1.9 },
    { "BULWARK", 4, 8, "selfdef", 0 },
  },
  SERPENT = {
    { "COIL", 3, 1, "twice", 1.0 }, { "VENOM", 4, 4, "poison", 1.0 },
    { "FLICKER", 3, 8, "haste", 0 },
  },
  FLAME = {
    { "FLAME", 4, 1, "burnall", 1.0 }, { "SCORCH", 3, 4, "burn", 1.4 },
    { "PYRE", 8, 8, "hit", 2.7 },
  },
  SPARROW = {
    { "GRACE", 4, 1, "heal", 0 }, { "MEND", 3, 4, "regen", 0 },
    { "DAWN", 8, 8, "revive", 0 },
  },
}

-- A second job, assigned in the menu: stat changes and one more skill. NONE is
-- the default. {name, +atk, +def, +spd, +mp, skill-or-nil}.
local JOBS = {
  { "NONE", 0, 0, 0, 0 },
  { "WARRIOR", 2, 0, 0, 0, { "CLEAVE", 4, 1, "hitall", 0.8 } },
  { "SENTINEL", 0, 3, 0, 0, { "RALLY", 3, 1, "shield", 0 } },
  { "MYSTIC", 0, 0, 0, 5, { "DRAIN", 4, 1, "drain", 1.1 } },
  { "SEER", 0, 0, 2, 0, { "HASTEN", 5, 1, "hasteall", 0 } },
}

-- Status effects live in a combatant's `st` table as name -> turns left. Damage
-- and heal over time land at the start of that combatant's turn; the stat ones
-- are read by the effective-stat helpers below.
local DOT = { burn = 3, poison = 5 }
function stat(c, k) return c.st and c.st[k] end
function job_of(h) return JOBS[(h.job or 0) + 1] end

local function emaxhp(h) return h.maxhp + (has_aspect(3) and 10 or 0) end
local function emaxmp(h) return h.maxmp + (has_aspect(4) and 5 or 0) + job_of(h)[5] end

-- ── run state ────────────────────────────────────────────────────────────────
local state, tick
local map, mapname, portals, camx, camy
local px, py, step, facing
local gold, inv                     -- inv[id] = count
local msg, msgi, msgwho
local shopsel, shopmode, menutab, menusel, menupick, menuitem, menuchar
local dungeon, dfloor, dtower, dreturn
local returnmap, returnx, returny   -- where a town/dungeon exit drops you
local wardsdown                     -- wardsdown[i] = true
local rng

-- battle
local foes, order, turn, sel, target, log, logt, anim, wardfight, result, btlkind

-- ── tiny rng, seedable for reproducible dungeons within a run ────────────────
local function rand() rng = (rng * 1103515245 + 12345) % 2147483648 return rng end
local function rrnd(n) return rand() % n end

-- ── grid helpers ─────────────────────────────────────────────────────────────
local function gw() return #map[1] end
local function gh() return #map end
local function at(x, y)
  if x < 0 or y < 0 or x >= gw() or y >= gh() then return "#" end
  return map[y + 1]:sub(x + 1, x + 1)
end
local function setat(x, y, ch)
  local row = map[y + 1]
  map[y + 1] = row:sub(1, x) .. ch .. row:sub(x + 2)
end
local function walkable(x, y) return not BLOCK[at(x, y)] end

-- ── portals: which special tiles lead where ──────────────────────────────────
-- Built per map. Overworld portals go to towns/dungeons; a town's '+' is the
-- door back out. Dungeons use '<' '>' and 'o' handled in step_special.
local function build_portals()
  portals = {}
  if mapname == "over" then
    portals = {
      A = { town = "caul" }, B = { town = "port" }, C = { town = "hold" },
      ["1"] = { tower = 1 }, ["2"] = { tower = 2 }, ["3"] = { tower = 3 }, ["4"] = { tower = 4 },
      x = { cave = 1 }, y = { cave = 2 },
    }
  end
end

-- ══ maps: entering places ════════════════════════════════════════════════════

local function copy_map(src)
  local m = {}
  for i = 1, #src do m[i] = src[i] end
  return m
end

local function find_tile(ch)
  for y = 0, gh() - 1 do for x = 0, gw() - 1 do
    if at(x, y) == ch then return x, y end
  end end
end

function enter_over(spawn_at)
  map, mapname = copy_map(OVER), "over"
  build_portals()
  if spawn_at then px, py = spawn_at[1], spawn_at[2]
  else px, py = find_tile("A") end
  -- open the final gate once all four aspects are held
  if aspbits >= 15 then
    local zx, zy = find_tile("Z")
    if zx then setat(zx, zy, "=") end
  end
  state = "world"
end

local TOWNMAP = { caul = CAUL, port = PORT, hold = HOLD }
function enter_town(name)
  returnmap, returnx, returny = "over", px, py
  map, mapname = copy_map(TOWNMAP[name]), name
  build_portals()
  local dx, dy = find_tile("+")
  px, py = dx, dy + 1
  save_game()
  state = "world"
end

-- ── one dungeon generator, for caves and tower floors ────────────────────────
-- Rooms carved from solid rock and joined by corridors, like the raycaster's
-- tower but top-down. Returns a fresh grid plus where the stairs and any chest
-- landed. `up` is the way deeper, `down`/`o` the way back.
function gen_dungeon(w, h, floorch, want_up, want_chest, chestitem)
  local g = {}
  for y = 1, h do g[y] = ("#"):rep(w) end
  local M = { }              -- swap map in so setat works, then read back
  local savem, savename = map, mapname
  map = g
  local rooms = {}
  local n = 4 + rrnd(3)
  for _ = 1, n do
    local rw, rh = 3 + rrnd(4), 3 + rrnd(3)
    local rx, ry = 1 + rrnd(w - rw - 2), 1 + rrnd(h - rh - 2)
    for yy = ry, ry + rh - 1 do for xx = rx, rx + rw - 1 do setat(xx, yy, floorch) end end
    rooms[#rooms + 1] = { x = rx + flr(rw / 2), y = ry + flr(rh / 2) }
  end
  for i = 2, #rooms do
    local a, b = rooms[i - 1], rooms[i]
    local x = a.x
    while x ~= b.x do setat(x, a.y, floorch) x = x + (b.x > a.x and 1 or -1) end
    local y = a.y
    while y ~= b.y do setat(b.x, y, floorch) y = y + (b.y > a.y and 1 or -1) end
  end
  local first, last = rooms[1], rooms[#rooms]
  setat(first.x, first.y, "o")                     -- exit, where you came in
  if want_up then setat(last.x, last.y, "<") else setat(last.x, last.y, ">") end
  local ex, ey = first.x, first.y
  local ux, uy = last.x, last.y
  if want_chest and #rooms > 2 then
    local r = rooms[2 + rrnd(#rooms - 2)]
    setat(r.x, r.y, "$")
  end
  local grid = map
  map, mapname = savem, savename
  return grid, ex, ey, ux, uy
end

function enter_cave(n)
  returnmap, returnx, returny = "over", px, py
  rng = (n * 7919 + tick) % 2147483648 + 1
  local g, ex, ey = gen_dungeon(26, 20, ",", false, true, nil)
  map, mapname = g, "cave"
  dungeon = { kind = "cave", n = n }
  build_portals()
  px, py = ex + 1, ey
  if BLOCK[at(px, py)] then px, py = ex, ey end
  state = "world"
end

function enter_tower(n, floor)
  dtower, dfloor = n, floor or 1
  if floor == nil then returnmap, returnx, returny = "over", px, py end
  rng = (n * 104729 + dfloor * 6151) % 2147483648 + 1
  local top = (dfloor >= 3)                          -- three floors; boss on top
  local g, ex, ey, ux, uy = gen_dungeon(24, 18, ",", not top, dfloor == 2, nil)
  map, mapname = g, "tower"
  dungeon = { kind = "tower", n = n }
  build_portals()
  px, py = ex + 1, ey
  if BLOCK[at(px, py)] then px, py = ex, ey end
  -- the boss sits on the top floor's up-stair spot
  if top then
    local sx, sy = find_tile("<")
    if not sx then sx, sy = ux, uy end
    setat(sx, sy, "B")
  end
  state = "world"
end

-- ══ stepping on special tiles ═════════════════════════════════════════════════

function step_special()
  local t = at(px, py)
  local p = portals[t]
  if p then
    if p.town then enter_town(p.town) return true end
    if p.tower then
      if wardsdown[p.tower] then
        msgbox(nil, { "this tower is spent.", "its aspect is yours." })
      else enter_tower(p.tower) end
      return true
    end
    if p.cave then enter_cave(p.cave) return true end
  end
  if t == "+" then enter_over({ returnx, returny }) return true end   -- town door out
  if t == "o" then                                                    -- dungeon exit
    enter_over({ returnx, returny }) return true
  end
  if t == "<" then enter_tower(dtower, dfloor + 1) return true end     -- deeper
  if t == ">" then enter_over({ returnx, returny }) return true end   -- cave bottom out
  if t == "S" then shopmode, shopsel, state = "buy", 1, "shop" return true end
  if t == "I" then heal_party() msgbox(nil, { "you rest. the line", "is whole again." }) return true end
  if t == "s" then save_game() msgbox(nil, { "the run is kept.", "walk on." }) return true end
  if t == "H" then heal_party() sfx(6) return true end
  if t == "$" then                                                     -- chest
    setat(px, py, ",")
    local g = 1 + rrnd(4) + (dungeon and dungeon.kind == "tower" and 2 or 1)
    give_gear(g)
    gold = gold + 10 + rrnd(20)
    msgbox(nil, { "a chest: " .. GEAR[g][1], "and some gold." })
    sfx(3)
    return true
  end
  if t == "B" then
    start_battle("ward")
    return true
  end
  if t == "Z" then
    msgbox(nil, { "the last gate holds.", "four aspects will open it." })
    return true
  end
  if t == "P" then
    if aspbits >= 15 then start_battle("final") else
      msgbox(nil, { "the pillar will not open", "until the tower falls." })
    end
    return true
  end
  return false
end

function msgbox(who, lines)
  msg, msgi, msgwho = lines, 1, who
  state = "talk"
  sfx(0)
end

function heal_party()
  for i = 1, #party do
    local h = party[i]
    h.hp, h.mp, h.alive = emaxhp(h), emaxmp(h), true
  end
end

function give_gear(id)
  inv[id] = (inv[id] or 0) + 1
end

-- ── movement ─────────────────────────────────────────────────────────────────
function try_move(dx, dy)
  facing = dx < 0 and 0 or dx > 0 and 1 or dy < 0 and 2 or 3
  local nx, ny = px + dx, py + dy
  local who = FOLK[at(nx, ny)] and at(nx, ny)
  if who then msgbox(who, FOLK[who]) return end
  if not walkable(nx, ny) then return end
  px, py = nx, ny
  if step_special() then return end
  -- encounters in grass and cave/tower floors
  if ENCTILE[at(px, py)] and rnd(1) < enc_rate() then start_battle("wild") end
end

function enc_rate()
  if mapname == "over" then return 0.07 end
  return 0.12
end

-- ══ battle ════════════════════════════════════════════════════════════════════

function roster_for()
  -- which wild foes appear, by where you are and how far you have come
  if mapname == "tower" then
    local pool = { "husk", "drift", "maw", "shade" }
    return pool
  elseif mapname == "cave" then
    return { "wisp", "husk", "maw" }
  end
  local base = { "wisp", "drift", "husk" }
  if aspbits >= 3 then base[#base + 1] = "shade" end
  return base
end

function start_battle(kind)
  btlkind = kind
  wardfight = (kind == "ward")
  for i = 1, #party do party[i].st = {} end
  foes = {}
  if kind == "ward" then
    local w = WARDS[dtower]
    foes[1] = mkfoe(w)
  elseif kind == "final" then
    foes[1] = mkfoe(TOWER)
  else
    local pool = roster_for()
    local n = 1 + rrndbattle(3)
    for i = 1, n do foes[i] = mkfoe(FOES[pool[1 + rrndbattle(#pool)]]) end
  end
  build_order()
  turn, sel, target, anim, result = 1, 1, 1, 0, nil
  picking, turnticked = nil, false
  log, logt = "", 0
  state = "battle"
  sfx(2)
end

function rrndbattle(n) return flr(rnd(n)) end

function mkfoe(t)
  return { name = t[1], hp = t[2], maxhp = t[2], atk = t[3], def = t[4],
    spd = t[5], col = t[6], xp = t[7], gold = t[8], burns = t[9],
    inflict = t[10], alive = true, st = {} }
end

function build_order()
  order = {}
  for i = 1, #party do if party[i].alive then order[#order + 1] = i end end
  for i = 1, #foes do if foes[i].alive then order[#order + 1] = 100 + i end end
  for i = 2, #order do
    local a = order[i]
    local sa = a > 100 and fspd(foes[a - 100]) or espd(party[a])
    local j = i - 1
    while j >= 1 do
      local b = order[j]
      local sb = b > 100 and fspd(foes[b - 100]) or espd(party[b])
      if sb >= sa then break end
      order[j + 1] = order[j] j = j - 1
    end
    order[j + 1] = a
  end
  turn = 1
end

function actorof(id) if id > 100 then return foes[id - 100] else return party[id] end end
function foes_alive() local n = 0 for i = 1, #foes do if foes[i].alive then n = n + 1 end end return n end
function party_alive() local n = 0 for i = 1, #party do if party[i].alive then n = n + 1 end end return n end
function first_foe() for i = 1, #foes do if foes[i].alive then return i end end return 1 end
function saylog(t) log, logt = t, 40 end

-- apply a status, keeping the longer of any existing duration
function give(c, name, turns)
  c.st = c.st or {}
  c.st[name] = math.max(c.st[name] or 0, turns)
end

-- one combatant's over-time effects at the start of its turn; returns whether
-- it is stunned this turn. Everything decays by one.
function tick_status(c)
  local s = c.st
  if not s then return false end
  local dmg = 0
  for k, per in pairs(DOT) do if s[k] then dmg = dmg + per end end
  if dmg > 0 and c.alive then
    hurt(c, dmg) saylog(c.name .. " SUFFERS " .. dmg) sfx(5)
  end
  if s.regen and c.alive then
    local cap = c.maxhp
    if c.job ~= nil then cap = emaxhp(c) end
    c.hp = mid(0, c.hp + 8, cap)
  end
  local stunned = s.stun ~= nil
  for k, v in pairs(s) do s[k] = v - 1 if s[k] <= 0 then s[k] = nil end end
  return stunned and c.alive
end

function damage(a, d, guard)
  local base = a - flr(d / 2) + flr(rnd(3)) - 1
  if guard then base = flr(base / 2) end
  return base
end
function hurt(x, amt)
  amt = flr(amt) if amt < 1 then amt = 1 end
  x.hp = x.hp - amt
  if x.hp <= 0 then x.hp, x.alive = 0, false end
  -- feedback the battle reads every frame: a white flash and a rising number
  x.flash, x.dmg, x.dmgt, x.heal = 6, amt, 26, false
  return amt
end

-- a heal or restore, shown the same way but in green
function mend_show(x, amt)
  if amt and amt > 0 then x.dmg, x.dmgt, x.heal = amt, 26, true end
end

function do_hero(h, action)
  h.guard = false
  if action == "strike" then
    local f = foes[target]
    if not f.alive then target = first_foe() f = foes[target] end
    saylog(h.name .. " HITS " .. f.name .. " " .. hurt(f, damage(eatk(h), fdef(f), false)))
    sfx(1)
  elseif action == "guard" then
    h.guard = true saylog(h.name .. " GUARDS") sfx(0)
  end
  return true
end

-- the skills a hero can use now: class skills grown into, plus the job's one
function skills_for(h)
  local l = {}
  for _, sk in ipairs(SKILLS[h.sign]) do if h.lvl >= sk[3] then l[#l + 1] = sk end end
  local j = job_of(h)
  if j[6] then l[#l + 1] = j[6] end
  return l
end

function cur_foe()
  local f = foes[target]
  if not f or not f.alive then target = first_foe() f = foes[target] end
  return f
end

function most_hurt(include_down)
  local who, worst = nil, 1e9
  for i = 1, #party do local a = party[i]
    if include_down and not a.alive then return a end
    if a.alive and a.hp - emaxhp(a) < worst then worst = a.hp - emaxhp(a) who = a end
  end
  return who
end

-- sk = {name, cost, unlock, kind, power}. Returns false if it could not fire.
function apply_skill(h, sk)
  if h.mp < sk[2] then saylog("NO SIGN LEFT") return false end
  h.mp = h.mp - sk[2]
  local kind, pow = sk[4], sk[5]
  if kind == "hit" then
    local f = cur_foe()
    saylog(h.name .. " " .. sk[1] .. " " .. hurt(f, damage(flr(eatk(h) * pow), fdef(f), false)))
    sfx(1)
  elseif kind == "twice" then
    local f = cur_foe()
    local d1 = hurt(f, damage(eatk(h), fdef(f), false))
    local d2 = f.alive and hurt(f, damage(eatk(h), fdef(f), false)) or 0
    saylog(h.name .. " COILS " .. (d1 + d2)) sfx(1)
  elseif kind == "hitall" then
    for i = 1, #foes do local f = foes[i]
      if f.alive then hurt(f, damage(flr(eatk(h) * pow), fdef(f), false)) end
    end
    saylog(h.name .. " " .. sk[1] .. "S ALL") sfx(1)
  elseif kind == "burn" then
    local f = cur_foe()
    hurt(f, damage(flr(eatk(h) * pow), fdef(f), false)) give(f, "burn", 3)
    saylog(h.name .. " SCORCHES " .. f.name) sfx(2)
  elseif kind == "burnall" then
    for i = 1, #foes do local f = foes[i]
      if f.alive then
        local d = damage(eatk(h) + 4, fdef(f), false)
        if f.burns then d = flr(d * 1.6) end
        hurt(f, d) give(f, "burn", 3)
      end
    end
    saylog(h.name .. " BURNS THEM ALL") sfx(2)
  elseif kind == "poison" then
    local f = cur_foe()
    hurt(f, damage(eatk(h), fdef(f), false)) give(f, "poison", 4)
    saylog(h.name .. " POISONS " .. f.name) sfx(1)
  elseif kind == "heal" then
    local who = most_hurt(true) or h
    local amt = 16 + eatk(h)
    if not who.alive then who.alive = true amt = flr(emaxhp(who) / 2) end
    local before = who.hp
    who.hp = mid(0, who.hp + amt, emaxhp(who))
    mend_show(who, who.hp - before)
    saylog(h.name .. " MENDS " .. who.name) sfx(6)
  elseif kind == "regen" then
    local who = most_hurt(false) or h
    give(who, "regen", 4)
    saylog(h.name .. " BLESSES " .. who.name) sfx(6)
  elseif kind == "revive" then
    for i = 1, #party do local a = party[i]
      if not a.alive then a.alive = true a.hp = flr(emaxhp(a) / 2) end
      a.st = {}
    end
    saylog(h.name .. " CALLS THE DAWN") sfx(6)
  elseif kind == "shield" then
    for i = 1, #party do give(party[i], "defup", 3) end
    saylog(h.name .. " SHIELDS THE LINE") sfx(6)
  elseif kind == "selfdef" then
    give(h, "defup", 4) give(h, "regen", 3)
    saylog(h.name .. " STANDS FAST") sfx(6)
  elseif kind == "haste" then
    give(h, "haste", 3) saylog(h.name .. " QUICKENS") sfx(0)
  elseif kind == "hasteall" then
    for i = 1, #party do give(party[i], "haste", 2) end
    saylog(h.name .. " HASTENS ALL") sfx(0)
  elseif kind == "drain" then
    local f = cur_foe()
    local d = hurt(f, damage(flr(eatk(h) * pow), fdef(f), false))
    h.hp = mid(0, h.hp + flr(d / 2), emaxhp(h))
    saylog(h.name .. " DRAINS " .. d) sfx(1)
  end
  return true
end

function enemy_turn(f)
  if (wardfight or btlkind == "final") and rnd(1) < 0.3 then
    saylog(f.name .. " SWEEPS ALL")
    for i = 1, #party do local h = party[i]
      if h.alive then hurt(h, damage(fatk(f) - 2, edef(h), h.guard)) end
    end
    sfx(5) return
  end
  local who, low = nil, 1e9
  for i = 1, #party do local h = party[i]
    if h.alive and h.hp < low then low = h.hp who = h end
  end
  if not who then return end
  local d = hurt(who, damage(fatk(f), edef(who), who.guard))
  saylog(f.name .. " HITS " .. who.name .. " " .. d)
  -- a shade poisons, a maw weakens; the wards carry their own bane
  if f.inflict and who.alive and rnd(1) < 0.5 then give(who, f.inflict, 3) end
  sfx(5)
end

function next_turn()
  turnticked = false
  turn = turn + 1
  if turn > #order then build_order() end
  local g = 0
  while turn <= #order and not actorof(order[turn]).alive do
    turn = turn + 1 g = g + 1
    if turn > #order then build_order() end
    if g > 40 then break end
  end
end

function win_battle()
  local xp, g = 0, 0
  for i = 1, #foes do xp = xp + foes[i].xp g = g + foes[i].gold end
  gold = gold + g
  for i = 1, #party do local h = party[i]
    if h.alive then
      h.xp = h.xp + xp
      while h.xp >= h.lvl * 22 and h.lvl < 30 do
        h.xp = h.xp - h.lvl * 22
        h.lvl = h.lvl + 1
        h.maxhp = h.maxhp + 4 h.atk = h.atk + 1
        if h.lvl % 2 == 0 then h.maxmp = h.maxmp + 2 h.def = h.def + 1 end
        h.hp, h.mp = emaxhp(h), emaxmp(h)
      end
    end
  end
  -- a ward grants its aspect
  if wardfight then
    wardsdown[dtower] = true
    aspbits = aspbits + (has_aspect(dtower) and 0 or 2 ^ (dtower - 1))
    result = "aspect"
  end
  score(count_aspects())
  result = result or "won"
end

function count_aspects()
  local n = 0 for i = 1, 4 do if has_aspect(i) then n = n + 1 end end return n
end

local CMDS = { "STRIKE", "SKILL", "GUARD" }
local picking, skillsel, turnticked

-- fade the per-combatant hit flashes and floating numbers, every frame
function tick_feedback()
  local function fade(c)
    if c.flash and c.flash > 0 then c.flash = c.flash - 1 end
    if c.dmgt and c.dmgt > 0 then c.dmgt = c.dmgt - 1 end
  end
  for i = 1, #party do fade(party[i]) end
  for i = 1, #foes do fade(foes[i]) end
end

function update_battle()
  if logt > 0 then logt = logt - 1 end
  tick_feedback()

  if result and logt <= 0 then
    if result == "won" or result == "aspect" then
      -- back to where the fight started
      if dungeon and at(px, py) == "B" then setat(px, py, ",") end
      state = "world"
      save_game()
    elseif result == "final" then
      state = "win" win() sfx(6)
    else
      state = "over" lose()
    end
    result = nil return
  end
  if result then return end

  if anim > 0 then
    anim = anim - 1
    if anim == 0 then
      if foes_alive() == 0 then
        win_battle()
        if btlkind == "final" then result = "final" end
        sfx(6) return
      end
      if party_alive() == 0 then result = "lost" saylog("THE LINEAGE FALLS") return end
      next_turn()
    end
    return
  end

  local id = order[turn]
  if not id then build_order() return end
  local one = actorof(id)
  if not one.alive then next_turn() return end

  -- statuses tick once, when this actor's turn begins
  if not turnticked then
    turnticked = true
    local stunned = tick_status(one)
    if not one.alive then anim = 16 return end
    if stunned then saylog(one.name .. " IS STUNNED") anim = 16 return end
  end

  if id > 100 then enemy_turn(one) anim = 22 return end

  -- the skill submenu
  if picking then
    local n = #picking
    if btnp(2) then skillsel = (skillsel - 2) % n + 1 sfx(0) end
    if btnp(3) then skillsel = skillsel % n + 1 sfx(0) end
    if btnp(5) then picking = nil sfx(0) end
    if btnp(4) then
      local sk = picking[skillsel]
      if one.mp >= sk[2] then
        if apply_skill(one, sk) then picking = nil anim = 22 end
      else sfx(5) end
    end
    return
  end

  if btnp(2) then sel = (sel - 2) % 3 + 1 sfx(0) end
  if btnp(3) then sel = sel % 3 + 1 sfx(0) end
  if btnp(1) and CMDS[sel] == "STRIKE" then
    repeat target = target % #foes + 1 until foes[target].alive
    sfx(0)
  end
  if btnp(4) then
    if CMDS[sel] == "STRIKE" then if do_hero(one, "strike") then anim = 22 end
    elseif CMDS[sel] == "GUARD" then do_hero(one, "guard") anim = 14
    elseif CMDS[sel] == "SKILL" then
      local sk = skills_for(one)
      if #sk > 0 then picking, skillsel = sk, 1 sfx(0) else sfx(5) end
    end
  end
end

-- ══ shop ══════════════════════════════════════════════════════════════════════

function update_shop()
  local list = shopmode == "buy" and GEAR or inv_list()
  local nrows = shopmode == "buy" and #GEAR or #list
  if btnp(2) then shopsel = (shopsel - 2) % math.max(1, nrows) + 1 sfx(0) end
  if btnp(3) then shopsel = shopsel % math.max(1, nrows) + 1 sfx(0) end
  if btnp(5) then shopmode = shopmode == "buy" and "sell" or "buy" shopsel = 1 sfx(0) end
  if btnp(4) then
    if shopmode == "buy" then
      local it = GEAR[shopsel]
      if gold >= it[4] then gold = gold - it[4] give_gear(shopsel) sfx(3)
      else sfx(5) end
    else
      local pick = list[shopsel]
      if pick then
        inv[pick] = inv[pick] - 1
        if inv[pick] <= 0 then inv[pick] = nil end
        gold = gold + flr(GEAR[pick][4] / 2)
        sfx(3)
        shopsel = 1
      end
    end
  end
  if btnp(1) then state = "world" end     -- right leaves the shop
end

function inv_list()
  local l = {}
  for id = 1, #GEAR do if (inv[id] or 0) > 0 then l[#l + 1] = id end end
  return l
end

-- ══ the party / gear menu ═════════════════════════════════════════════════════
-- Tabs: PARTY (portraits + stats), GEAR (equip per hero), ASPECTS (what is
-- earned). X opens and closes it; up/down moves; O acts.
function update_menu()
  -- In the item picker, X backs out and everything else stays put.
  if menupick then
    local h = party[ceil2(menusel)]
    local slot = (menusel - 1) % 2 + 1
    local list = gear_for_slot(slot)
    local n = #list + 1                       -- +1 for REMOVE at the top
    if btnp(2) then menuitem = (menuitem - 2) % n + 1 sfx(0) end
    if btnp(3) then menuitem = menuitem % n + 1 sfx(0) end
    if btnp(5) then menupick = nil sfx(0) end
    if btnp(4) then
      local id = menuitem == 1 and 0 or list[menuitem - 1]
      if slot == 1 then h.wpn = id else h.arm = id end
      sfx(3) menupick = nil
    end
    return
  end

  -- a hero's own page: X returns to the list, up/down flips between heroes
  if menuchar then
    if btnp(5) then menuchar = nil sfx(0) return end
    if btnp(2) then menuchar = (menuchar - 2) % 4 + 1 sfx(0) end
    if btnp(3) then menuchar = menuchar % 4 + 1 sfx(0) end
    return
  end

  if btnp(5) then state = "world" save_game() return end
  if btnp(1) then menutab = menutab % 4 + 1 menusel = 1 menuchar = nil sfx(0) return end
  if btnp(0) then menutab = (menutab - 2) % 4 + 1 menusel = 1 menuchar = nil sfx(0) return end

  if menutab == 2 then
    -- eight rows: each hero's weapon then armour slot
    if btnp(2) then menusel = (menusel - 2) % 8 + 1 sfx(0) end
    if btnp(3) then menusel = menusel % 8 + 1 sfx(0) end
    if btnp(4) then menupick = true menuitem = 1 sfx(0) end
  elseif menutab == 3 then
    -- jobs: pick a hero, O cycles their job
    if btnp(2) then menusel = (menusel - 2) % 4 + 1 sfx(0) end
    if btnp(3) then menusel = menusel % 4 + 1 sfx(0) end
    if btnp(4) then
      local h = party[menusel]
      h.job = (h.job + 1) % #JOBS
      sfx(3)
    end
  else
    if btnp(2) then menusel = (menusel - 2) % 4 + 1 sfx(0) end
    if btnp(3) then menusel = menusel % 4 + 1 sfx(0) end
    -- on the PARTY tab, O opens the selected hero's full page
    if menutab == 1 and btnp(4) then menuchar = menusel sfx(3) end
  end
end

function ceil2(n) return flr((n + 1) / 2) end

function gear_for_slot(slot)
  local l = {}
  for id = 1, #GEAR do
    if GEAR[id][2] == slot and (inv[id] or 0) > 0 then l[#l + 1] = id end
  end
  return l
end

-- ══ save / load ═══════════════════════════════════════════════════════════════
-- The whole run in one string: party stats and gear, gold, inventory, aspects,
-- towers cleared, and where you stood on the overworld.
function save_game()
  local p = {}
  for i = 1, #party do local h = party[i]
    p[#p + 1] = table.concat({ h.hp, h.maxhp, h.mp, h.maxmp, h.atk, h.def, h.spd,
      h.lvl, h.xp, h.wpn, h.arm, h.alive and 1 or 0, h.job or 0 }, ",")
  end
  local iv = {}
  for id = 1, #GEAR do iv[#iv + 1] = inv[id] or 0 end
  local wd = {}
  for i = 1, 4 do wd[i] = wardsdown[i] and 1 or 0 end
  local ox, oy = px, py
  if mapname ~= "over" then ox, oy = returnx or px, returny or py end
  local blob = table.concat({
    "2", flr(gold), flr(aspbits),
    table.concat(wd, ""), flr(ox), flr(oy),
    table.concat(iv, "."), table.concat(p, "|"),
  }, ";")
  save("run", blob)
end

function load_game()
  local blob = load("run")
  if not blob or blob == "" then return false end
  local parts = {}
  for s in (blob .. ";"):gmatch("(.-);") do parts[#parts + 1] = s end
  if parts[1] ~= "2" then return false end
  new_party()
  gold = tonumber(parts[2]) or 0
  aspbits = tonumber(parts[3]) or 0
  wardsdown = {}
  for i = 1, 4 do wardsdown[i] = parts[4]:sub(i, i) == "1" end
  local ox, oy = tonumber(parts[5]) or 1, tonumber(parts[6]) or 1
  inv = {}
  local id = 1
  for c in (parts[7] .. "."):gmatch("(.-)%.") do
    local n = tonumber(c) or 0 if n > 0 then inv[id] = n end id = id + 1
  end
  local hi = 1
  for hs in (parts[8] .. "|"):gmatch("(.-)|") do
    local f, h = {}, party[hi]
    for v in (hs .. ","):gmatch("(.-),") do f[#f + 1] = tonumber(v) or 0 end
    if h and #f >= 12 then
      h.hp, h.maxhp, h.mp, h.maxmp, h.atk, h.def, h.spd, h.lvl, h.xp, h.wpn, h.arm =
        f[1], f[2], f[3], f[4], f[5], f[6], f[7], f[8], f[9], f[10], f[11]
      h.alive = f[12] == 1
      h.job = f[13] or 0
    end
    hi = hi + 1
  end
  enter_over({ ox, oy })
  return true
end

-- ══ init ══════════════════════════════════════════════════════════════════════
function _init()
  tick = 0
  state = "title"
  facing, step = 3, 0
  rng = 1
end

function begin_new()
  new_party()
  gold, inv, aspbits = 20, {}, 0
  wardsdown = {}
  wardsdown[1], wardsdown[2], wardsdown[3], wardsdown[4] = false, false, false, false
  enter_over(nil)
  save_game()
end

-- ══ update ════════════════════════════════════════════════════════════════════
function _update()
  tick = tick + 1
  if state == "title" then
    if btnp(4) then begin_new()
    elseif btnp(5) then if not load_game() then begin_new() end end
    return
  end
  if state == "world" then
    if btnp(5) then state = "menu" menutab, menusel, menupick, menuchar = 1, 1, nil, nil return end
    if step > 0 then step = step - 1 end
    local dx, dy = 0, 0
    if btn(0) then dx = -1 elseif btn(1) then dx = 1
    elseif btn(2) then dy = -1 elseif btn(3) then dy = 1 end
    if (dx ~= 0 or dy ~= 0) and step == 0 then try_move(dx, dy) step = 5 end
  elseif state == "talk" then
    if btnp(4) or btnp(5) then msgi = msgi + 1 if msgi > #msg then state = "world" else sfx(0) end end
  elseif state == "battle" then update_battle()
  elseif state == "shop" then update_shop()
  elseif state == "menu" then update_menu()
  elseif state == "win" or state == "over" then
    if btnp(4) then _init() end
  end
end

-- ══ drawing ═══════════════════════════════════════════════════════════════════

function draw_tile(t, sx, sy)
  if t == "#" or t == "T" then
    rect(sx, sy, 8, 8, 5) rect(sx + 1, sy, 6, 5, 5) rect(sx + 3, sy + 5, 2, 3, 3)
  elseif t == "~" then
    rect(sx, sy, 8, 8, 6)
    if (sx + sy + flr(tick / 8)) % 16 < 8 then pset(sx + 2, sy + 3, 7) end
  elseif t == "." then
    rect(sx, sy, 8, 8, 1) pset(sx + 2, sy + 5, 5) pset(sx + 5, sy + 2, 5)
  elseif t == "," then
    rect(sx, sy, 8, 8, 0) pset(sx + 1, sy + 6, 1) pset(sx + 6, sy + 1, 1)
  elseif t == "H" or t == "I" then
    rect(sx, sy, 8, 8, 1) rect(sx + 2, sy + 1, 4, 6, 7) rect(sx + 3, sy + 2, 2, 2, 4)
  elseif t == "S" then
    rect(sx, sy, 8, 8, 1) rect(sx + 1, sy + 2, 6, 4, 3) rect(sx + 1, sy + 1, 6, 1, 4)
  elseif t == "s" then
    rect(sx, sy, 8, 8, 1) rect(sx + 3, sy + 1, 2, 6, 6) pset(sx + 3, sy, 7)
  elseif t == "$" then
    rect(sx, sy, 8, 8, 1) rect(sx + 1, sy + 3, 6, 4, 3) rect(sx + 1, sy + 2, 6, 1, 4) pset(sx + 3, sy + 4, 7)
  elseif t == "<" then
    rect(sx, sy, 8, 8, 0) rect(sx + 1, sy + 1, 6, 6, 5) print("^", sx + 2, sy + 1, 4)
  elseif t == ">" or t == "o" then
    rect(sx, sy, 8, 8, 0) rectb(sx + 1, sy + 1, 6, 6, 5)
  elseif t == "A" or t == "B" or t == "C" then
    -- a town gate: a building with a lit doorway you can actually find
    rect(sx, sy, 8, 8, 1)
    rect(sx, sy + 1, 8, 7, 5) rect(sx, sy + 1, 8, 1, 4)   -- walls + bright lintel
    rect(sx + 3, sy + 3, 3, 5, 2) pset(sx + 4, sy + 5, 4) -- the doorway, and a lamp
  elseif t == "1" or t == "2" or t == "3" or t == "4" then
    -- a tower entrance: a tall dark spire with a doorway
    rect(sx, sy, 8, 8, 1)
    rect(sx + 1, sy - 3, 6, 11, 6) rect(sx + 2, sy - 4, 4, 1, 4)
    rect(sx + 3, sy + 4, 2, 4, 2) pset(sx + 3, sy - 3, 7)
  elseif t == "x" or t == "y" then
    -- a cave mouth: a rock face with a black opening
    rect(sx, sy, 8, 8, 5)
    rect(sx + 2, sy + 2, 4, 6, 0) pset(sx + 2, sy + 2, 6) pset(sx + 5, sy + 2, 6)
  elseif t == "P" then
    rect(sx, sy, 8, 8, 1) rect(sx + 3, sy - 2, 2, 12, 4) pset(sx + 3, sy, 7)
  elseif t == "Z" then
    rect(sx, sy, 8, 8, 1) rectb(sx + 1, sy, 6, 8, 2)
  elseif t == "+" then
    rect(sx, sy, 8, 8, 5) rect(sx + 2, sy + 2, 4, 6, 3)
  elseif t == "=" then
    rect(sx, sy, 8, 8, 1)
  else
    rect(sx, sy, 8, 8, 1)
  end
end

function draw_person(sx, sy, c)
  rect(sx + 2, sy + 1, 4, 3, c) rect(sx + 2, sy + 4, 4, 3, 7) pset(sx + 3, sy + 2, 0)
end

function draw_world()
  cls((mapname == "cave" or mapname == "tower") and 0 or 1)
  -- a map smaller than the viewport is centred instead of clamped
  if gw() <= VW then camx = flr((gw() - VW) / 2)
  else camx = flr(mid(0, px - VW / 2, gw() - VW)) end
  if gh() <= VH then camy = flr((gh() - VH) / 2)
  else camy = flr(mid(0, py - VH / 2, gh() - VH)) end
  for ry = 0, VH - 1 do for rx = 0, VW - 1 do
    local mx, my = camx + rx, camy + ry
    local sx, sy = rx * TILE, ry * TILE + 16
    local t = at(mx, my)
    draw_tile(t, sx, sy)
    if FOLK[t] then draw_person(sx, sy, 3) end
  end end
  local hsx, hsy = (px - camx) * TILE, (py - camy) * TILE + 16
  draw_person(hsx, hsy, 4)

  rect(0, 0, 240, 16, 0)
  line(0, 15, 239, 15, 5)
  local place = ({ over = "CAUL", caul = "SETTLEMENT", port = "TIDEPORT",
    hold = "STONEHOLD", cave = "THE DEEP", tower = "TOWER" })[mapname] or "CAUL"
  if mapname == "tower" then place = "TOWER " .. dtower .. "-" .. dfloor end
  print(place, 3, 5, 7)
  print(count_aspects() .. "/4 ASPECTS", 148, 5, 4)
  print("G" .. gold, 208, 5, 3)
end

function draw_box(x, y, w, h, e) rect(x, y, w, h, 0) rectb(x, y, w, h, e or 5) end

function draw_talk()
  draw_world()
  draw_box(4, 116, 232, 40, 6)
  local yy = 120
  if msgwho then print(msg[1], 10, yy, 4) yy = yy + 10 end
  local first = msgwho and 2 or 1
  for i = first, mid(first, first + msgi - 1, #msg) do print(msg[i], 10, yy, 7) yy = yy + 8 end
  print("O", 226, 148, 3)
end

-- ── portraits: an actual face per sign, drawn from colour and a motif ─────────
-- `s` is the pixel scale: 1 in the lists, larger on a hero's own page.
function portrait(h, x, y, s)
  s = s or 1
  local c = h.alive and h.col or 5
  local dark = h.alive and 1 or 0
  local function q(a, b, w, hh, cc) rect(x + a * s, y + b * s, w * s, hh * s, cc) end
  q(0, 0, 16, 16, 1)                                 -- backing
  q(3, 3, 10, 11, c)                                 -- head
  q(2, 5, 1, 6, c) q(13, 5, 1, 6, c)                 -- cheeks
  q(3, 2, 10, 2, 0) q(2, 3, 2, 2, 0) q(12, 3, 2, 2, 0)   -- hair
  q(5, 7, 2, 2, 7) q(9, 7, 2, 2, 7)                  -- eye whites
  q(5, 8, 1, 1, 0) q(10, 8, 1, 1, 0)                 -- pupils
  q(8, 9, 1, 2, dark)                                -- nose
  q(6, 12, 4, 1, 0)                                  -- mouth
  -- the sign, worn on the brow
  if h.sign == "WHALE" then q(5, 5, 6, 1, 6)
  elseif h.sign == "SERPENT" then q(5, 5, 1, 1, 5) q(8, 6, 1, 1, 5) q(11, 5, 1, 1, 5)
  elseif h.sign == "FLAME" then q(7, 4, 2, 3, 2)
  else q(7, 5, 2, 1, 7) q(8, 4, 1, 3, 7) end
  rectb(x, y, 16 * s, 16 * s, h.alive and 7 or 5)
end

function bar(x, y, w, cur, max, c)
  rect(x, y, w, 3, 1)
  if max > 0 then rect(x, y, flr(w * mid(0, cur, max) / max), 3, c) end
end

-- a row of coloured pips for the statuses a combatant carries
function status_pips(c, x, y)
  if not c.st then return end
  local pip = { burn = 2, poison = 5, regen = 4, defup = 6, defdn = 1,
    atkdn = 3, haste = 4, slow = 1, stun = 2 }
  local i = 0
  for k, v in pairs(c.st) do
    if v > 0 then rect(x + i * 4, y, 3, 3, pip[k] or 7) i = i + 1 end
  end
end

function draw_battle()
  cls(0)
  local n = #foes
  for i = 1, n do
    local f = foes[i]
    local fx, fy = flr((i - 0.5) * 240 / n), 42
    if f.alive then
      local big = f.maxhp > 100
      -- a white flash on the frames just after a hit lands
      local bc = (f.flash and f.flash > 0) and 7 or f.col
      -- drawn to the stage: on 240x160 a foe is a presence, not a chip
      if big then
        rect(fx - 20, fy - 20, 40, 40, bc)
        rect(fx - 11, fy - 8, 7, 7, 4) rect(fx + 4, fy - 8, 7, 7, 4)
        rect(fx - 8, fy + 8, 16, 3, 0)
      else
        rect(fx - 10, fy - 10, 20, 20, bc)
        rect(fx - 6, fy - 4, 3, 3, 0) rect(fx + 3, fy - 4, 3, 3, 0)
        rect(fx - 3, fy + 4, 6, 2, 0)
      end
      if order[turn] and order[turn] <= 100 and CMDS[sel] == "STRIKE" and target == i then
        rect(fx - 3, fy - (big and 28 or 18), 6, 4, 4)
      end
      bar(fx - 16, fy + (big and 23 or 13), 32, f.hp, f.maxhp, 2)
      status_pips(f, fx - 14, fy + (big and 27 or 17))
    else print("X", fx - 4, fy - 5, 5, 2) end
    -- the rising damage number over whoever was just struck
    if f.dmgt and f.dmgt > 0 then
      local s = "" .. f.dmg
      print(s, fx - #s * 4, fy - 24 - flr((26 - f.dmgt) / 3), f.heal and 5 or 4, 2)
    end
  end
  if logt > 0 or result then draw_box(4, 64, 232, 12, 6) print(log, 8, 67, 7) end

  local base = 84
  for i = 1, #party do
    local h = party[i]
    local y = base + (i - 1) * 18
    local acting = order[turn] and order[turn] == i and not result and anim == 0
    if acting then rect(0, y - 1, 160, 16, h.alive and 1 or 0) end
    -- a hit flashes the row red for a couple of frames
    if h.flash and h.flash > 0 then rect(0, y - 1, 160, 16, 2) end
    print(h.name, 2, y, h.alive and h.col or 5)
    if not h.alive then print("DOWN", 2, y + 7, 5)
    else
      bar(34, y + 1, 56, h.hp, emaxhp(h), 2)
      bar(34, y + 6, 56, h.mp, emaxmp(h), 6)
      print(h.hp .. "", 96, y, 7)
      status_pips(h, 118, y + 6)
    end
    -- the number, floating up from the hero's row
    if h.dmgt and h.dmgt > 0 then
      local s = "" .. h.dmg
      print((h.heal and "+" or "-") .. s, 96, y - flr((26 - h.dmgt) / 4), h.heal and 5 or 4)
    end
    if acting then draw_bmenu(h, 86, y) end
  end
end

function draw_bmenu(h, x, y)
  if picking then draw_skillmenu(h) return end
  -- a proper boxed menu, not three lines crammed into one row. Fixed on the
  -- right so it reads the same wherever in the order the acting hero sits.
  local bx, by, bw = 174, 92, 60
  draw_box(bx, by, bw, 40, 4)
  print(h.name, bx + 3, by + 3, h.col)
  for i = 1, 3 do
    local yy = by + 12 + (i - 1) * 9
    if i == sel then rect(bx + 2, yy - 1, bw - 4, 8, 1) end
    print((i == sel and ">" or " ") .. CMDS[i], bx + 3, yy, i == sel and 4 or 7)
  end
end

-- the skill list, over the party area, when a hero is choosing one
function draw_skillmenu(h)
  local list = picking
  local w = 100
  draw_box(70, 58, w, 60, 4)
  print(h.name .. " SIGNS", 74, 62, h.col)
  for i = 1, #list do
    local sk = list[i]
    local y = 72 + (i - 1) * 9
    if i == skillsel then rect(72, y - 1, w - 4, 8, 1) end
    local afford = h.mp >= sk[2]
    print(sk[1], 76, y, afford and (i == skillsel and 4 or 7) or 5)
    print(sk[2] .. "MP", 144, y, afford and 6 or 5)
  end
end

function draw_shop()
  cls(0)
  print(shopmode == "buy" and "BUY" or "SELL", 4, 4, 4)
  print("G" .. gold, 204, 4, 3)
  line(0, 12, 239, 12, 5)
  local list = shopmode == "buy" and nil or inv_list()
  local nrows = shopmode == "buy" and #GEAR or #list
  for i = 1, nrows do
    local id = shopmode == "buy" and i or list[i]
    local g = GEAR[id]
    local y = 16 + (i - 1) * 14
    if i == shopsel then rect(0, y - 1, 240, 12, 1) end
    print(g[1], 6, y + 2, i == shopsel and 4 or 7)
    print((g[2] == 1 and "ATK+" or "DEF+") .. g[3], 120, y + 2, 6)
    if shopmode == "buy" then print("G" .. g[4], 200, y + 2, 3)
    else print("x" .. (inv[id] or 0) .. " G" .. flr(g[4] / 2), 190, y + 2, 3) end
  end
  if nrows == 0 then print("NOTHING TO SELL", 90, 70, 5) end
  line(0, 146, 239, 146, 5)
  print("O TAKE  X BUY/SELL  > LEAVE", 66, 150, 1)
end

function draw_menu()
  cls(0)
  local tabs = { "PARTY", "GEAR", "JOBS", "ASPECT" }
  for i = 1, 4 do
    local x = 4 + (i - 1) * 59
    if i == menutab then rect(x - 2, 2, 57, 10, 1) end
    print(tabs[i], x + 4, 4, i == menutab and 4 or 5)
  end
  line(0, 13, 239, 13, 5)

  if menutab == 1 then
    if menuchar then draw_charpage(party[menuchar]) return end
    for i = 1, 4 do
      local h = party[i]
      local y = 18 + (i - 1) * 30
      if i == menusel then rect(0, y - 1, 240, 26, 1) end
      portrait(h, 6, y, 1)
      print(h.name, 30, y, h.col)
      print(h.sign, 30, y + 7, 5)
      print("LV" .. h.lvl, 30, y + 14, 7)
      bar(90, y + 2, 70, h.hp, emaxhp(h), 2)
      bar(90, y + 9, 70, h.mp, emaxmp(h), 6)
      print("HP" .. h.hp .. "/" .. emaxhp(h), 90, y + 15, 1)
      print("A" .. eatk(h) .. " D" .. edef(h) .. " S" .. espd(h), 172, y + 2, 4)
      print("JOB " .. job_of(h)[1], 172, y + 10, 3)
    end
    print("O:VIEW  <>:TAB  X:BACK", 76, 151, 1)
  elseif menutab == 2 then
    for i = 1, 4 do
      local h = party[i]
      local y = 18 + (i - 1) * 30
      portrait(h, 6, y, 1)
      print(h.name, 30, y, h.col)
      local wn = h.wpn > 0 and GEAR[h.wpn][1] or "-"
      local an = h.arm > 0 and GEAR[h.arm][1] or "-"
      local wrow, arow = (i - 1) * 2 + 1, (i - 1) * 2 + 2
      if menusel == wrow then rect(28, y + 7, 180, 8, 1) end
      if menusel == arow then rect(28, y + 14, 180, 8, 1) end
      print("W:" .. wn, 30, y + 8, menusel == wrow and 4 or 6)
      print("A:" .. an, 30, y + 15, menusel == arow and 4 or 6)
    end
    print("O:EQUIP  <>:TAB  X:BACK", 74, 151, 1)
    if menupick then draw_picker() end
  elseif menutab == 3 then
    for i = 1, 4 do
      local h = party[i]
      local y = 18 + (i - 1) * 30
      if i == menusel then rect(0, y - 1, 240, 26, 1) end
      portrait(h, 6, y, 1)
      print(h.name, 30, y, h.col)
      local j = job_of(h)
      print("JOB: " .. j[1], 30, y + 8, 4)
      -- what the job changes
      local mods = ""
      if j[2] ~= 0 then mods = mods .. "ATK+" .. j[2] .. " " end
      if j[3] ~= 0 then mods = mods .. "DEF+" .. j[3] .. " " end
      if j[4] ~= 0 then mods = mods .. "SPD+" .. j[4] .. " " end
      if j[5] ~= 0 then mods = mods .. "MP+" .. j[5] .. " " end
      if j[6] then mods = mods .. j[6][1] end
      print(mods == "" and "no change" or mods, 30, y + 15, 6)
    end
    print("O:CHANGE JOB  <>:TAB  X:BACK", 64, 151, 1)
  else
    for i = 1, 4 do
      local a = ASPECTS[i]
      local y = 20 + (i - 1) * 28
      local got = has_aspect(i)
      rectb(84, y, 18, 18, got and 4 or 1)
      if got then rect(87, y + 3, 12, 12, ({ 6, 2, 4, 7 })[i]) end
      print(a[1], 110, y + 2, got and 4 or 5)
      print(a[3], 110, y + 10, got and 7 or 1)
    end
    print(count_aspects() .. " OF 4 ASPECTS", 92, 134, 4)
    if aspbits >= 15 then print("THE LAST GATE IS OPEN", 78, 144, 2) end
  end
end

-- a hero's full page: the big portrait, every stat, gear and the signs learned
function draw_charpage(h)
  portrait(h, 12, 22, 5)                              -- an 80x80 face
  print(h.name, 12, 108, h.col, 2)
  print(h.sign, 12, 122, 5)
  print("LV" .. h.lvl, 12, 130, 7)
  print("XP " .. (h.xp or 0), 12, 138, 1)

  local x = 118
  print("HP " .. h.hp .. "/" .. emaxhp(h), x, 22, 2)
  bar(x, 29, 100, h.hp, emaxhp(h), 2)
  print("MP " .. h.mp .. "/" .. emaxmp(h), x, 36, 6)
  bar(x, 43, 100, h.mp, emaxmp(h), 6)
  print("ATK " .. eatk(h), x, 52, 4)
  print("DEF " .. edef(h), x, 60, 4)
  print("SPD " .. espd(h), x, 68, 4)
  print("JOB " .. job_of(h)[1], x, 76, 3)
  print("W:" .. (h.wpn > 0 and GEAR[h.wpn][1] or "-"), x, 86, 6)
  print("A:" .. (h.arm > 0 and GEAR[h.arm][1] or "-"), x, 94, 6)

  print("SIGNS", x, 106, 5)
  local sl = skills_for(h)
  local sy = 114
  for i = 1, #sl do
    print(sl[i][1] .. " " .. sl[i][2] .. "MP", x, sy, 7)
    sy = sy + 7
  end
  print("UP/DN  X:BACK", 176, 151, 1)
end

function draw_picker()
  local h = party[ceil2(menusel)]
  local slot = (menusel - 1) % 2 + 1
  local list = gear_for_slot(slot)
  draw_box(65, 30, 110, 94, 4)
  print(h.name .. " " .. (slot == 1 and "WEAPON" or "ARMOUR"), 70, 34, 4)
  local rows = { "REMOVE" }
  for _, id in ipairs(list) do rows[#rows + 1] = id end
  for i = 1, #rows do
    local y = 46 + (i - 1) * 9
    if i == menuitem then rect(67, y - 1, 106, 8, 1) end
    if rows[i] == "REMOVE" then print("- NONE", 71, y, 5)
    else local g = GEAR[rows[i]] print(g[1], 71, y, 7) print("+" .. g[3], 150, y, 6) end
  end
end

function draw_title()
  cls(1)
  rect(0, 116, 240, 44, 6)
  rect(116, 10, 8, 106, 4) rect(119, 0, 2, 116, 7)
  for i = 0, 3 do draw_person(84 + i * 22, 110, ({ 6, 5, 2, 4 })[i + 1]) end
  rect(0, 44, 240, 42, 0)
  print("VEILWALKERS", (240 - 11 * 4 * 3) / 2, 49, 6, 3)
  print("O  NEW", 96, 68, 5)
  print("X  CONTINUE", 96, 76, 7)
end

function draw_win()
  cls(0)
  for i = 0, 70 do
    if (i * 7 + flr(tick / 3)) % 40 > (tick / 3) % 40 then pset((i * 97) % 240, (i * 53) % 130 + 10, 1) end
  end
  rect(117, 12, 6, 140, 4) rect(119, 4, 2, 152, 7)
  draw_box(50, 56, 140, 48, 4)
  print("THE VEIL GOES DARK", 84, 62, 4)
  print("CAUL ENDS.", 100, 72, 7)
  print("AMEBRAK IS BORN.", 88, 80, 6)
  print("PRESS O", 106, 92, 3)
end

function _draw()
  if state == "title" then draw_title()
  elseif state == "world" then draw_world()
  elseif state == "talk" then draw_talk()
  elseif state == "battle" then draw_battle()
  elseif state == "shop" then draw_shop()
  elseif state == "menu" then draw_menu()
  elseif state == "win" then draw_win()
  elseif state == "over" then
    cls(0) draw_box(65, 64, 110, 32, 2)
    print("THE LINEAGE FALLS", 86, 72, 2) print("PRESS O", 106, 84, 3)
  end
end

function _cover()
  cls(1)
  rect(0, 100, 240, 60, 6)
  rect(116, 6, 8, 100, 4) rect(119, 0, 2, 110, 7)
  for i = 0, 3 do draw_person(86 + i * 20, 94, ({ 6, 5, 2, 4 })[i + 1]) end
  rect(0, 116, 240, 44, 0)
  print("VEILWALKERS", (240 - 11 * 4 * 4) / 2, 129, 6, 4)
end
