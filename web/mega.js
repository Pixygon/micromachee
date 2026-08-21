// Mega Micromachee, in a browser.
//
// A port of `helper/src/mega.rs`, kept deliberately close to it — same phases,
// same constants, same speed curve — because two implementations that drift are
// worse than one. `web/megacheck.mjs` asserts the numbers still line up with the
// Rust source rather than trusting that they do.
//
// The one real difference is that loading a cart is asynchronous here, so a
// round begins with an await rather than a function call. Everything else is
// the same state machine.

import { Screen, loadCart, W, H, CHAR_WIDTH } from "./micromachee.js";

export const MEGA_ID = "mega";
export const MEGA_TITLE = "Mega Micromachee";
export const MEGA_ABOUT = "every pearl, a few seconds each, faster and faster";

export const LIVES = 3;
const FPS = 30;
const INTRO_FRAMES = 60;
const CARD_FRAMES = 36;
const VERDICT_FRAMES = 27;

/** Rounds between each turn of the screw. */
export const STEP_EVERY = 5;
export const START_SECONDS = 10;
export const FLOOR_SECONDS = 5;
export const SPEED_STEP = 0.15;
export const MAX_SPEED = 2.5;

const centre = (text, scale) => Math.floor((W - text.length * CHAR_WIDTH * scale) / 2);

export class Mega {
  constructor(factory, carts) {
    this.factory = factory;
    this.carts = carts.filter((c) => c.id !== MEGA_ID);
    this.order = this.carts.map((_, i) => i);
    this.at = 0;
    this.round = 0;
    this.lives = LIVES;
    this.survived = 0;
    this.cart = null;
    this.phase = "intro";
    this.left = INTRO_FRAMES;
    this.carry = 0;
    this.seed = (Date.now() & 0x7fffffff) | 1;
    this.out = new Screen();
    this.busy = false;
    this.shuffle();
  }

  rand() {
    // A plain LCG here: the Rust side uses xorshift64*, but nothing compares
    // the two orders, and 64-bit maths in JS would mean BigInt for no gain.
    this.seed = (this.seed * 1664525 + 1013904223) >>> 0;
    return this.seed;
  }

  shuffle() {
    for (let i = this.order.length - 1; i > 0; i--) {
      const j = this.rand() % (i + 1);
      [this.order[i], this.order[j]] = [this.order[j], this.order[i]];
    }
  }

  seconds() {
    return Math.max(FLOOR_SECONDS, START_SECONDS - Math.floor(this.round / STEP_EVERY));
  }

  speed() {
    return Math.min(MAX_SPEED, 1 + Math.floor(this.round / STEP_EVERY) * SPEED_STEP);
  }

  current() {
    return this.carts[this.order[this.at % this.order.length]];
  }

  get score() {
    return this.survived;
  }

  get over() {
    return this.phase === "over";
  }

  async beginRound() {
    // A fresh engine every round and no saved state: a micro-game starts from
    // nothing, and a farm's coins have no business in here.
    this.cart = await loadCart(this.factory, this.current().code);
    this.cart.init();
    this.carry = 0;
    this.left = Math.floor(this.seconds() * FPS);
    this.phase = "play";
  }

  nextRound() {
    this.round += 1;
    this.at += 1;
    if (this.at % this.order.length === 0) this.shuffle();
  }

  finishRound(survived) {
    if (this.cart) { this.cart.close(); this.cart = null; }
    if (survived) this.survived += 1;
    else this.lives -= 1;
    this.phase = "verdict";
    this.verdictOk = survived;
    this.left = VERDICT_FRAMES;
  }

  /** One frame. Awaits only when a round is starting. */
  async step(held) {
    switch (this.phase) {
      case "intro":
        this.drawIntro();
        if (--this.left <= 0) { this.phase = "card"; this.left = CARD_FRAMES; }
        break;

      case "card":
        this.drawCard();
        if (--this.left <= 0) {
          try { await this.beginRound(); }
          catch { this.finishRound(false); }   // would not even load: a miss
        }
        break;

      case "play":
        this.playFrame(held);
        break;

      case "verdict":
        this.drawVerdict(this.verdictOk);
        if (--this.left <= 0) {
          if (this.lives <= 0) this.phase = "over";
          else { this.nextRound(); this.phase = "card"; this.left = CARD_FRAMES; }
        }
        break;

      case "over":
        this.drawOver();
        if (held & (1 << 4)) {
          this.round = 0; this.lives = LIVES; this.survived = 0; this.at = 0;
          this.shuffle();
          this.phase = "card";
          this.left = CARD_FRAMES;
        }
        break;
    }
  }

  playFrame(held) {
    const c = this.cart;
    if (!c) { this.finishRound(false); return; }
    c.setHeld(held);

    // Faster means more turns of the cart's own loop per frame — never a
    // bigger step, because no cart was written in terms of one.
    this.carry += this.speed();
    const steps = Math.max(1, Math.floor(this.carry));
    this.carry -= steps;

    let lost = false;
    try {
      for (let i = 0; i < steps; i++) {
        c.update();
        if (c.outcome === 1) { lost = true; break; }
      }
      if (!lost) c.draw();
    } catch {
      lost = true;   // a cart falling over costs the round, not the run
    }
    if (lost) { this.finishRound(false); return; }

    this.out.px.set(c.screen.px);
    this.left -= 1;
    this.drawHud();
    if (this.left <= 0) this.finishRound(true);
  }

  // ── what it looks like ───────────────────────────────────────────────────

  /** A thin bar and three pips — the least that can be laid over a cart. */
  drawHud() {
    const total = Math.floor(this.seconds() * FPS);
    const w = total === 0 ? 0 : Math.floor((this.left * W) / total);
    this.out.rect(0, H - 2, W, 2, 0);
    this.out.rect(0, H - 2, w, 2, this.left < FPS ? 2 : 5);
    for (let i = 0; i < LIVES; i++) {
      this.out.rect(W - 4 - i * 5, 1, 3, 3, i < this.lives ? 2 : 1);
    }
  }

  drawIntro() {
    this.out.cls(0);
    this.out.print("MEGA", centre("MEGA", 3), 34, 4, 3);
    this.out.print("MICROMACHEE", centre("MICROMACHEE", 1), 58, 7, 1);
    this.out.print("EVERY PEARL. NO TIME.", centre("EVERY PEARL. NO TIME.", 1), 78, 1, 1);
    const lives = `${LIVES} LIVES`;
    this.out.print(lives, centre(lives, 1), 94, 2, 1);
  }

  drawCard() {
    this.out.cls(0);
    const round = `ROUND ${this.round + 1}`;
    this.out.print(round, centre(round, 1), 18, 1, 1);

    const title = this.current().title;
    const scale = title.length * 4 * 2 <= 120 ? 2 : 1;
    this.out.print(title, centre(title, scale), 46, 7, scale);

    const secs = `${this.seconds()} SECONDS`;
    this.out.print(secs, centre(secs, 1), 74, 5, 1);

    if (this.speed() > 1) {
      const sp = `SPEED ${this.speed().toFixed(1)}X`;
      this.out.print(sp, centre(sp, 1), 88, 3, 1);
    }
    for (let i = 0; i < LIVES; i++) {
      this.out.rect(W - 4 - i * 5, 1, 3, 3, i < this.lives ? 2 : 1);
    }
  }

  drawVerdict(ok) {
    this.out.cls(0);
    const word = ok ? "SURVIVED" : "MISS";
    this.out.print(word, centre(word, 2), 50, ok ? 5 : 2, 2);
    const n = `${this.survived} SURVIVED`;
    this.out.print(n, centre(n, 1), 76, 1, 1);
  }

  drawOver() {
    this.out.cls(0);
    this.out.print("GAME OVER", centre("GAME OVER", 2), 40, 2, 2);
    const n = `${this.survived} ROUNDS`;
    this.out.print(n, centre(n, 1), 64, 7, 1);
    this.out.print("PRESS O", centre("PRESS O", 1), 84, 3, 1);
  }
}

/** The shelf picture, drawn rather than stored — there is no mega.lua. */
export function megaCover() {
  const s = new Screen();
  s.cls(0);
  for (let i = 0; i < 6; i++) {
    const x = 8 + (i % 3) * 40;
    const y = 12 + Math.floor(i / 3) * 34;
    s.rect(x, y, 34, 26, 1);
    s.rect(x + 3, y + 3, 28, 20, 0);
    s.print("?", x + 14, y + 9, 2 + (i % 5), 1);
  }
  s.rect(0, 82, W, 46, 0);
  s.print("MEGA", centre("MEGA", 3), 88, 3, 3);
  s.print("MICROMACHEE", centre("MICROMACHEE", 1), 112, 7, 1);
  return s;
}
