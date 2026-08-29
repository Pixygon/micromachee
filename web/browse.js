// The shelf, drawn by the console itself — the browser twin of
// helper/src/browse.rs. Choosing a game is made of the same pixels as playing
// one: a grid of cover tiles on the 128x128 screen, navigated with the same six
// buttons, so nothing on the web reaches for a mouse the desktop does not.
//
// This is a port kept deliberately close to the Rust: the same tile size, the
// same faithful downscale that turns a cover into a legible thumbnail, the same
// info card. `web/browse-check` is not a thing — parity here is by eye — but
// the layout constants and the sampling rule are copied verbatim so the two
// shelves look like one shelf.

import { Screen, W, H, CHAR_WIDTH } from "./micromachee.js";
import { HEADLINE, HEADLINE_WIDTH, RANK } from "./console-data.js";

const COLS = 3;
// A tile is a CARD: art on top, the title set properly underneath. The art
// crops to the top 3/4 of the cover — the band where covers bake their big
// painted titles is cut, because a scale-4 title squeezed through a 3.3:1
// downsample is mush, and the caption below says the same thing legibly.
const TILE_W = 72;
const TILE_H = 48;
const ART_H = 36;
const ART_SRC_H = 120;
const CAP_H = TILE_H - ART_H;

// rank_of[slot] = place in the luminance order, so bright art outvotes its
// dark ground when a block is squeezed to one pixel.
const RANK_OF = (() => { const r = new Array(8).fill(0); RANK.forEach((s, i) => { r[s & 7] = i; }); return r; })();

// The console's own display face: 5x7, for titles the 3x5 font turns to mush.
function headline(out, text, x, y, c, scale = 1) {
  let cx = x;
  for (const ch of String(text).toUpperCase()) {
    const rows = HEADLINE[ch];
    if (rows) {
      for (let ry = 0; ry < 7; ry++) {
        for (let rx = 0; rx < 5; rx++) {
          if (rows[ry] & (0b10000 >> rx)) {
            if (scale === 1) out.pset(cx + rx, y + ry, c);
            else out.rect(cx + rx * scale, y + ry * scale, scale, scale, c);
          }
        }
      }
    }
    cx += HEADLINE_WIDTH * scale;
  }
}
const headlineCentre = (text, scale = 1) => Math.floor((W - text.length * HEADLINE_WIDTH * scale) / 2);
const GAP = 4;
const X0 = 8;
const GY = 18;
const VIS_ROWS = 2;

export const MAKE_ID = "make";

const centre = (text, scale = 1) => Math.floor((W - text.length * CHAR_WIDTH * scale) / 2);

function wrap(text, cols) {
  const out = [];
  let line = "";
  for (const word of text.split(/\s+/).filter(Boolean)) {
    if (line && line.length + 1 + word.length > cols) { out.push(line); line = ""; }
    line = line ? line + " " + word : word;
  }
  if (line) out.push(line);
  return out;
}

export class Browse {
  // entries: [{ id, title, author, about, best, inMega, isMega, art:Screen }]
  // A trailing make tile is added unless `withMake` is false.
  constructor(entries, withMake = true) {
    this.entries = entries.slice();
    if (withMake) {
      const art = makeTile();
      this.entries.push({
        id: MAKE_ID, title: "Make a game", author: "you",
        about: "say what it is. the console writes it",
        best: 0, inMega: false, isMega: false, art, make: true,
      });
    }
    this.sel = 0;
    this.scroll = 0;
    this.info = false;
    this.last = 0;
    this.picked = null;
    this.wantsMake = false;
    this.out = new Screen();
  }

  rows() { return Math.ceil(this.entries.length / COLS); }

  moveTo(next) {
    this.sel = Math.max(0, Math.min(next, this.entries.length - 1));
    const row = Math.floor(this.sel / COLS);
    if (row < this.scroll) this.scroll = row;
    else if (row >= this.scroll + VIS_ROWS) this.scroll = row + 1 - VIS_ROWS;
  }

  choose() {
    const e = this.entries[this.sel];
    if (e.make) this.wantsMake = true;
    else this.picked = e.id;
  }

  // One frame. `held` is the same bitmask a cart sees; returns the Screen.
  frame(held) {
    const pressed = held & ~this.last;
    this.last = held;
    const hit = (b) => (pressed & (1 << b)) !== 0;

    if (this.entries.length === 0) { this.drawEmpty(); return this.out; }

    if (this.info) {
      if (hit(4)) this.choose();
      else if (hit(5)) this.info = false;
      this.drawInfo();
      return this.out;
    }

    if (hit(0) && this.sel > 0) this.moveTo(this.sel - 1);
    if (hit(1)) this.moveTo(this.sel + 1);
    if (hit(2) && this.sel >= COLS) this.moveTo(this.sel - COLS);
    if (hit(3)) this.moveTo(Math.min(this.sel + COLS, this.entries.length - 1));
    if (hit(4)) this.choose();
    if (hit(5)) this.info = true;

    this.drawGrid();
    return this.out;
  }

  drawEmpty() {
    this.out.cls(0);
    this.out.print("NOTHING ON THE SHELF", centre("NOTHING ON THE SHELF"), H / 2 - 8, 2, 1);
    this.out.print("RUN MICROMACHEE SYNC", centre("RUN MICROMACHEE SYNC"), H / 2 + 4, 1, 1);
  }

  drawTile(at, x, y) {
    const e = this.entries[at];
    for (let ty = 0; ty < ART_H; ty++) {
      const sy0 = Math.floor((ty * ART_SRC_H) / ART_H);
      const sy1 = Math.max(sy0 + 1, Math.floor(((ty + 1) * ART_SRC_H) / ART_H));
      for (let tx = 0; tx < TILE_W; tx++) {
        const sx0 = Math.floor((tx * W) / TILE_W);
        const sx1 = Math.max(sx0 + 1, Math.floor(((tx + 1) * W) / TILE_W));
        const votes = [0, 0, 0, 0, 0, 0, 0, 0];
        for (let sy = sy0; sy < sy1; sy++) {
          for (let sx = sx0; sx < sx1; sx++) {
            const c = e.art.pget(sx, sy) & 7;
            votes[c] += 1 + RANK_OF[c];
          }
        }
        let best = 0;
        for (let c = 1; c < 8; c++) if (votes[c] > votes[best]) best = c;
        this.out.pset(x + tx, y + ty, best);
      }
    }
    // the caption: the title, set in the headline face, never sampled
    this.out.rect(x, y + ART_H, TILE_W, CAP_H, 0);
    this.out.line(x, y + ART_H, x + TILE_W - 1, y + ART_H, 1);
    const full = e.title.toUpperCase();
    const sel = at === this.sel;
    const colour = sel ? 7 : 6;
    if (full.length * HEADLINE_WIDTH <= TILE_W) {
      headline(this.out, full, x + Math.floor((TILE_W - full.length * HEADLINE_WIDTH) / 2), y + ART_H + 3, colour, 1);
    } else {
      const t = full.slice(0, Math.floor(TILE_W / CHAR_WIDTH));
      this.out.print(t, x + Math.floor((TILE_W - t.length * CHAR_WIDTH) / 2), y + ART_H + 4, colour, 1);
    }
    if (e.draft) this.out.rect(x + TILE_W - 4, y + 1, 3, 3, 2);
    this.out.rectb(x - 1, y - 1, TILE_W + 2, TILE_H + 2, sel ? 7 : 1);
  }

  arrow(cx, y, up, c) {
    for (let i = 0; i < 3; i++) {
      const w = 1 + i * 2;
      const row = up ? y + i : y + 2 - i;
      this.out.rect(cx - i, row, w, 1, c);
    }
  }

  drawGrid() {
    this.out.cls(0);
    const e = this.entries[this.sel];
    headline(this.out, e.title, 4, 3, e.draft ? 2 : 7, 1);
    if (e.best > 0) {
      const label = ("best " + e.best).toUpperCase();
      this.out.print(label, W - 3 - label.length * CHAR_WIDTH, 4, 6, 1);
    }
    this.out.line(0, 13, W - 1, 13, 1);

    const first = this.scroll * COLS;
    for (let slot = 0; slot < COLS * VIS_ROWS; slot++) {
      const at = first + slot;
      if (at >= this.entries.length) break;
      const x = X0 + (slot % COLS) * (TILE_W + GAP);
      const y = GY + Math.floor(slot / COLS) * (TILE_H + GAP);
      this.drawTile(at, x, y);
    }
    if (this.scroll > 0) this.arrow(W / 2, GY - 3, true, 1);
    if (this.scroll + VIS_ROWS < this.rows()) this.arrow(W / 2, GY + VIS_ROWS * (TILE_H + GAP), false, 1);

    this.out.line(0, H - 24, W - 1, H - 24, 1);
    const hint = "O PLAY   X INFO";
    this.out.print(hint, centre(hint), H - 18, 6, 1);
    const count = `${this.sel + 1} OF ${this.entries.length}`;
    this.out.print(count, centre(count), H - 9, 1, 1);
  }

  drawInfo() {
    this.out.cls(0);
    const e = this.entries[this.sel];
    const title = e.title.toUpperCase();
    const scale = title.length * HEADLINE_WIDTH * 2 <= W - 8 ? 2 : 1;
    headline(this.out, title, headlineCentre(title, scale), 14, 7, scale);
    const by = ("by " + e.author).toUpperCase();
    this.out.print(by, centre(by), 38, 1, 1);

    let y = 58;
    for (const line of wrap(e.about.toUpperCase(), 48)) {
      this.out.print(line, centre(line), y, 6, 1);
      y += 9;
    }
    y = 88;
    if (e.best > 0) {
      const b = ("best " + e.best).toUpperCase();
      this.out.print(b, centre(b), y, 4, 1);
      y += 11;
    }
    if (!e.isMega && !e.make) {
      const [text, c] = e.inMega ? ["PLAYS IN MEGA", 5] : ["TOO SLOW FOR MEGA", 1];
      this.out.print(text, centre(text), y, c, 1);
      y += 11;
    }
    this.out.line(0, H - 24, W - 1, H - 24, 1);
    const hint = "O PLAY   X BACK";
    this.out.print(hint, centre(hint), H - 16, 6, 1);
  }
}

// The make tile: a plus, the one tile that is not a picture of a game.
function makeTile() {
  const s = new Screen();
  s.cls(0);
  s.rectb(20, 12, W - 40, H - 44, 1);
  s.rectb(21, 13, W - 42, H - 46, 1);
  s.rect(W / 2 - 8, H / 2 - 24, 16, 40, 5);
  s.rect(W / 2 - 20, H / 2 - 12, 40, 16, 5);
  return s;
}
