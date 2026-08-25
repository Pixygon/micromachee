// The shelf, drawn by the console itself — the browser twin of
// helper/src/browse.rs. Choosing a game is made of the same pixels as playing
// one: a grid of cover tiles on the 128x128 screen, navigated with the same six
// buttons, so nothing on the web reaches for a mouse the desktop does not.
//
// This is a port kept deliberately close to the Rust: the same tile size, the
// same block sampling that turns a cover into a legible thumbnail, the same
// info card. `web/browse-check` is not a thing — parity here is by eye — but
// the layout constants and the sampling rule are copied verbatim so the two
// shelves look like one shelf.

import { Screen, W, CHAR_WIDTH } from "./micromachee.js";
import { RANK } from "./console-data.js";

const COLS = 3;
const TILE = 38;
const GAP = 3;
const X0 = 4;
const GY = 16;
const VIS_ROWS = 2;
const COVER_ART = 96;
const MEGA_ART = 82;

export const MAKE_ID = "make";

const centre = (text, scale = 1) => Math.floor((W - text.length * CHAR_WIDTH * scale) / 2);

// rank_of[slot] = its place in the luminance order, for the sampling tie-break.
const RANK_OF = (() => {
  const r = new Array(8).fill(0);
  RANK.forEach((slot, place) => { r[slot & 7] = place; });
  return r;
})();

// The commonest colour in a block of the cover, with the two adjustments the
// Rust makes: background (slot 0) must win outright rather than merely lead, so
// a small bright thing on black survives being shrunk; ties go to the lighter
// colour, because on a dark cover the lighter pixel carries the shape.
function block(art, x0, x1, y0, y1) {
  const count = new Array(8).fill(0);
  for (let y = y0; y < Math.max(y1, y0 + 1); y++) {
    for (let x = x0; x < Math.max(x1, x0 + 1); x++) {
      count[art.pget(x, y) & 7]++;
    }
  }
  let best = 0, bestScore = 0;
  for (let c = 0; c < 8; c++) {
    const score = count[c] * (c === 0 ? 7 : 10);
    if (score > bestScore || (score === bestScore && RANK_OF[c] > RANK_OF[best])) {
      best = c; bestScore = score;
    }
  }
  return best;
}

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
        best: 0, inMega: false, isMega: false, art, artRows: COVER_ART, make: true,
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
    this.out.print("NOTHING ON THE SHELF", centre("NOTHING ON THE SHELF"), 56, 2, 1);
    this.out.print("RUN MICROMACHEE SYNC", centre("RUN MICROMACHEE SYNC"), 68, 1, 1);
  }

  drawTile(at, x, y) {
    const e = this.entries[at];
    const rows = e.artRows || (e.isMega ? MEGA_ART : COVER_ART);
    for (let ty = 0; ty < TILE; ty++) {
      const y0 = Math.floor((ty * rows) / TILE), y1 = Math.floor(((ty + 1) * rows) / TILE);
      for (let tx = 0; tx < TILE; tx++) {
        const x0 = Math.floor((tx * W) / TILE), x1 = Math.floor(((tx + 1) * W) / TILE);
        this.out.pset(x + tx, y + ty, block(e.art, x0, x1, y0, y1));
      }
    }
    if (e.draft) this.out.rect(x + TILE - 4, y + 1, 3, 3, 2);
    this.out.rectb(x - 1, y - 1, TILE + 2, TILE + 2, at === this.sel ? 7 : 1);
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
    this.out.print(e.title.toUpperCase(), 3, 4, e.draft ? 2 : 7, 1);
    if (e.best > 0) {
      const label = ("best " + e.best).toUpperCase();
      this.out.print(label, W - 3 - label.length * CHAR_WIDTH, 4, 6, 1);
    }
    this.out.line(0, 13, W - 1, 13, 1);

    const first = this.scroll * COLS;
    for (let slot = 0; slot < COLS * VIS_ROWS; slot++) {
      const at = first + slot;
      if (at >= this.entries.length) break;
      const x = X0 + (slot % COLS) * (TILE + GAP);
      const y = GY + Math.floor(slot / COLS) * (TILE + GAP);
      this.drawTile(at, x, y);
    }
    if (this.scroll > 0) this.arrow(W / 2, GY - 2, true, 1);
    if (this.scroll + VIS_ROWS < this.rows()) this.arrow(W / 2, GY + VIS_ROWS * (TILE + GAP), false, 1);

    this.out.line(0, 104, W - 1, 104, 1);
    const hint = "O PLAY   X INFO";
    this.out.print(hint, centre(hint), 110, 6, 1);
    const count = `${this.sel + 1} OF ${this.entries.length}`;
    this.out.print(count, centre(count), 119, 1, 1);
  }

  drawInfo() {
    this.out.cls(0);
    const e = this.entries[this.sel];
    const title = e.title.toUpperCase();
    const scale = title.length * CHAR_WIDTH * 2 <= W - 8 ? 2 : 1;
    this.out.print(title, centre(title, scale), 10, 7, scale);
    const by = ("by " + e.author).toUpperCase();
    this.out.print(by, centre(by), 28, 1, 1);

    let y = 46;
    for (const line of wrap(e.about.toUpperCase(), 30)) {
      this.out.print(line, centre(line), y, 6, 1);
      y += 9;
    }
    y = 70;
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
    this.out.line(0, 104, W - 1, 104, 1);
    const hint = "O PLAY   X BACK";
    this.out.print(hint, centre(hint), 112, 6, 1);
  }
}

// The make tile: a plus, the one tile that is not a picture of a game.
function makeTile() {
  const s = new Screen();
  s.cls(0);
  s.rectb(10, 8, 108, 80, 1);
  s.rectb(11, 9, 106, 78, 1);
  s.rect(56, 30, 16, 36, 5);
  s.rect(46, 40, 36, 16, 5);
  return s;
}
