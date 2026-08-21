// The console, in a browser.
//
// This is a second implementation of `helper/src/console.rs`, and the only
// thing that makes a second implementation safe is proving it draws the same
// pixels: `web/check.mjs` runs a cart here and against the real helper and
// compares all 16384 of them. The font and the palettes are not copied at all —
// they are generated from the Rust source into `console-data.js`.
//
// Lua is real Lua 5.4 (wasmoon), the same version the helper embeds, which
// matters more than it sounds: carts rely on 5.4 integer semantics, and `flr`
// returning a float is what once put "SCORE 30.0" in the corner of every game.
// So `flr`, `mid` and `rnd` are implemented IN Lua rather than crossing the
// JS boundary, where an integer would quietly become a float.

import { W, H, CHAR_WIDTH, LINE_HEIGHT, FONT, THEMES } from "./console-data.js";

export { W, H, THEMES };

const wrap = (c) => ((Math.floor(c) % 8) + 8) % 8;

export class Screen {
  constructor() {
    this.px = new Uint8Array(W * H);
  }

  cls(c = 0) {
    this.px.fill(wrap(c));
  }

  pset(x, y, c) {
    x = Math.floor(x);
    y = Math.floor(y);
    if (x >= 0 && y >= 0 && x < W && y < H) this.px[y * W + x] = wrap(c);
  }

  pget(x, y) {
    x = Math.floor(x);
    y = Math.floor(y);
    return x >= 0 && y >= 0 && x < W && y < H ? this.px[y * W + x] : 0;
  }

  rect(x, y, w, h, c) {
    x = Math.floor(x); y = Math.floor(y); w = Math.floor(w); h = Math.floor(h);
    if (w <= 0 || h <= 0) return;
    const col = wrap(c);
    const x1 = Math.min(x + w, W);
    const y1 = Math.min(y + h, H);
    for (let yy = Math.max(y, 0); yy < y1; yy++) {
      const row = yy * W;
      for (let xx = Math.max(x, 0); xx < x1; xx++) this.px[row + xx] = col;
    }
  }

  rectb(x, y, w, h, c) {
    x = Math.floor(x); y = Math.floor(y); w = Math.floor(w); h = Math.floor(h);
    if (w <= 0 || h <= 0) return;
    this.rect(x, y, w, 1, c);
    this.rect(x, y + h - 1, w, 1, c);
    this.rect(x, y, 1, h, c);
    this.rect(x + w - 1, y, 1, h, c);
  }

  line(x0, y0, x1, y1, c) {
    // Bresenham in the form that needs no special cases for steepness or
    // direction — the same one the helper uses.
    x0 = Math.floor(x0); y0 = Math.floor(y0);
    x1 = Math.floor(x1); y1 = Math.floor(y1);
    let x = x0, y = y0;
    const dx = Math.abs(x1 - x0);
    const dy = -Math.abs(y1 - y0);
    const sx = x0 < x1 ? 1 : -1;
    const sy = y0 < y1 ? 1 : -1;
    let err = dx + dy;
    for (;;) {
      this.pset(x, y, c);
      if (x === x1 && y === y1) break;
      const e2 = 2 * err;
      if (e2 >= dy) { err += dy; x += sx; }
      if (e2 <= dx) { err += dx; y += sy; }
    }
  }

  circ(cx, cy, r, c) {
    cx = Math.floor(cx); cy = Math.floor(cy); r = Math.floor(r);
    if (r < 0) return;
    const rr = r * r;
    for (let dy = -r; dy <= r; dy++) {
      const span = Math.floor(Math.sqrt(rr - dy * dy));
      this.rect(cx - span, cy + dy, span * 2 + 1, 1, c);
    }
  }

  circb(cx, cy, r, c) {
    cx = Math.floor(cx); cy = Math.floor(cy); r = Math.floor(r);
    if (r < 0) return;
    let x = r, y = 0, d = 1 - r;
    while (x >= y) {
      for (const [px, py] of [
        [cx + x, cy + y], [cx + y, cy + x], [cx - y, cy + x], [cx - x, cy + y],
        [cx - x, cy - y], [cx - y, cy - x], [cx + y, cy - x], [cx + x, cy - y],
      ]) this.pset(px, py, c);
      y += 1;
      if (d < 0) d += 2 * y + 1;
      else { x -= 1; d += 2 * (y - x) + 1; }
    }
  }

  print(text, x, y, c = 7, scale = 1) {
    const s = Math.max(1, Math.floor(scale));
    let cx = Math.floor(x);
    let cy = Math.floor(y);
    for (const ch of String(text)) {
      if (ch === "\n") { cx = Math.floor(x); cy += LINE_HEIGHT * s; continue; }
      const rows = FONT[ch.toUpperCase()];
      if (rows) {
        for (let ry = 0; ry < 5; ry++) {
          for (let rx = 0; rx < 3; rx++) {
            if (rows[ry] & (0b100 >> rx)) {
              if (s === 1) this.pset(cx + rx, cy + ry, c);
              else this.rect(cx + rx * s, cy + ry * s, s, s, c);
            }
          }
        }
      }
      cx += CHAR_WIDTH * s;
    }
  }
}

// The parts of the API whose NUMBER TYPES matter, written in Lua so they stay
// Lua. `rnd` is the helper's xorshift64*, digit for digit, so a game that leans
// on randomness draws the same thing in both places.
const PRELUDE = `
local __held, __last, __frame = 0, 0, 0
local __seed = 0x2545f4914f6cdd1d

function __set_input(h, l, f) __held, __last, __frame = h, l, f end

function btn(i)
  local b = 1 << math.floor(i)
  return (__held & b) ~= 0
end

function btnp(i)
  local b = 1 << math.floor(i)
  return (__held & b) ~= 0 and (__last & b) == 0
end

function t() return __frame / 30 end

function rnd(max)
  __seed = __seed ~ (__seed >> 12)
  __seed = __seed ~ (__seed << 25)
  __seed = __seed ~ (__seed >> 27)
  local u = (__seed * 0x2545f4914f6cdd1d) >> 11
  local unit = (u & 0x1fffffffffffff) / 0x20000000000000
  return unit * (max or 1.0)
end

function flr(x) return math.floor(x) end

-- Persistence and the wall clock. This load() deliberately shadows Lua's own
-- load() (which compiles a string) -- a cart asking to load "coins" means the
-- save, and the standard one would hand back nil and look like it worked.
local __store = {}

function __seed_store(k, v) __store[k] = v end

function save(k, v)
  __store[k] = v
  __persist(k, v)
end

function load(k)
  local v = __store[k]
  -- A number that came back through JSON is a float; a cart that concatenates
  -- it would print "COINS 9.0".
  if type(v) == "number" and v == math.floor(v) then return math.tointeger(v) end
  return v
end

function now() return __now() end


function mid(a, b, c)
  local lo, hi = a, c
  if a > c then lo, hi = c, a end
  if b < lo then return lo end
  if b > hi then return hi end
  return b
end
`;

/// Load a cart and give back something you can drive a frame at a time.
export async function loadCart(factory, code, { onScore, storage } = {}) {
  const lua = await factory.createEngine({ openStandardLibs: true });
  const screen = new Screen();
  const mem = {};
  let score = 0;

  const g = lua.global;
  // Where `save` puts things. In a browser that is localStorage keyed by cart,
  // so a farm planted on Monday is still growing on Tuesday; in node it is a
  // plain object, which is what the pixel comparison wants.
  const store = storage || {
    get: (k) => mem[k],
    set: (k, v) => { mem[k] = v; },
    all: () => ({ ...mem }),
  };
  g.set("__persist", (k, v) => store.set(k, v));
  g.set("__now", () => Math.floor(Date.now() / 1000));
  g.set("cls", (c) => screen.cls(c ?? 0));
  g.set("pset", (x, y, c) => screen.pset(x, y, c));
  g.set("pget", (x, y) => screen.pget(x, y));
  g.set("rect", (x, y, w, h, c) => screen.rect(x, y, w, h, c));
  g.set("rectb", (x, y, w, h, c) => screen.rectb(x, y, w, h, c));
  g.set("line", (a, b, c, d, e) => screen.line(a, b, c, d, e));
  g.set("circ", (x, y, r, c) => screen.circ(x, y, r, c));
  g.set("circb", (x, y, r, c) => screen.circb(x, y, r, c));
  g.set("print", (text, x, y, c, scale) => {
    // A Lua number arrives as a JS number; render an integral one without the
    // trailing ".0", which is what the helper does.
    let s;
    if (typeof text === "number") s = Number.isInteger(text) ? String(text) : String(text);
    else if (text === null || text === undefined) s = "NIL";
    else s = String(text);
    screen.print(s, x, y, c ?? 7, scale ?? 1);
  });
  g.set("score", (n) => {
    score = Math.floor(n);
    if (onScore) onScore(score);
  });

  await lua.doString(PRELUDE);
  // Anything saved before this run has to be in place before `_init` reads it.
  const seed = g.get("__seed_store");
  for (const [k, v] of Object.entries(store.all ? store.all() : {})) seed(k, v);
  await lua.doString(code);

  const has = (name) => typeof g.get(name) === "function";
  const call = (name) => { const f = g.get(name); if (typeof f === "function") f(); };

  let held = 0, last = 0, frame = 0;
  const sync = () => g.get("__set_input")(held, last, frame);

  return {
    screen,
    get score() { return score; },
    hasCover: () => has("_cover"),
    setHeld(mask) { held = mask & 0b111111; },
    init() { sync(); call("_init"); },
    update() { sync(); call("_update"); last = held; },
    draw() { sync(); call("_draw"); frame += 1; },
    cover() { sync(); call("_cover"); },
    close() { lua.global.close(); },
  };
}

/// Persistence for a browser: one localStorage entry per cart.
export function localStore(id) {
  const key = "micromachee:" + id;
  const read = () => {
    try { return JSON.parse(localStorage.getItem(key) || "{}"); } catch { return {}; }
  };
  return {
    all: read,
    get: (k) => read()[k],
    set: (k, v) => {
      const all = read();
      all[k] = v;
      try { localStorage.setItem(key, JSON.stringify(all)); } catch { /* full or blocked */ }
    },
  };
}

/// Blit the index buffer onto a canvas, nearest-neighbour. Every console pixel
/// is exactly `scale` canvas pixels — a fractional scale makes some pixels wider
/// than others and the whole screen shimmers when anything moves.
export function blit(screen, ctx, palette, scale) {
  const rgb = palette.map((hex) => [
    parseInt(hex.slice(1, 3), 16),
    parseInt(hex.slice(3, 5), 16),
    parseInt(hex.slice(5, 7), 16),
  ]);
  const img = ctx.createImageData(W * scale, H * scale);
  const data = img.data;
  for (let y = 0; y < H; y++) {
    for (let x = 0; x < W; x++) {
      const [r, g, b] = rgb[screen.px[y * W + x]];
      for (let dy = 0; dy < scale; dy++) {
        let o = ((y * scale + dy) * W * scale + x * scale) * 4;
        for (let dx = 0; dx < scale; dx++) {
          data[o] = r; data[o + 1] = g; data[o + 2] = b; data[o + 3] = 255;
          o += 4;
        }
      }
    }
  }
  ctx.putImageData(img, 0, 0);
}
