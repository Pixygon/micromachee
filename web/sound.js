// The console's speaker, in a browser.
//
// A port of the recipe table in `helper/src/wav.rs`. The helper renders those
// segments to WAV files for the desktop panel; here the same numbers drive Web
// Audio oscillators directly, because a browser can make the sound rather than
// download it.
//
// Two implementations of anything drift, so `web/soundcheck.mjs` reads the
// segments back out of the Rust source and compares them to these. If they stop
// matching, the site and the desktop stop sounding like the same console.

// secs, from, to, grit, amp0, amp1
export const RECIPES = [
  [[0.045, 900, 1250, 0.0, 0.55, 0.0]],
  [[0.085, 520, 150, 0.15, 0.65, 0.0]],
  [[0.30, 200, 40, 0.85, 0.8, 0.0]],
  [[0.045, 660, 660, 0.0, 0.5, 0.5],
   [0.045, 880, 880, 0.0, 0.5, 0.5],
   [0.075, 1320, 1320, 0.0, 0.55, 0.0]],
  [[0.12, 300, 760, 0.0, 0.5, 0.05]],
  [[0.24, 420, 90, 0.5, 0.7, 0.0]],
  [[0.09, 523, 523, 0.0, 0.5, 0.5],
   [0.09, 659, 659, 0.0, 0.5, 0.5],
   [0.09, 784, 784, 0.0, 0.5, 0.5],
   [0.20, 1046, 1046, 0.0, 0.55, 0.0]],
  [[0.10, 440, 440, 0.0, 0.5, 0.5],
   [0.10, 349, 349, 0.0, 0.5, 0.5],
   [0.26, 196, 165, 0.1, 0.55, 0.0]],
];

export const NAMES = ["blip", "hit", "boom", "pickup", "jump", "hurt", "win", "lose"];

/** Kept low on purpose: this plays on a page somebody opened to look at games. */
const LEVEL = 0.22;

export class Speaker {
  constructor() {
    this.ctx = null;
    this.noise = null;
    this.muted = false;
  }

  // Browsers refuse to start audio until the page has been interacted with, so
  // the context is made on the first sound rather than up front.
  wake() {
    if (this.ctx) return this.ctx;
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return null;
    this.ctx = new AC();

    // One second of noise, made once and replayed. Generating it per sound is
    // the sort of thing that stutters on a slow machine for no benefit.
    const n = this.ctx.sampleRate;
    const buf = this.ctx.createBuffer(1, n, n);
    const d = buf.getChannelData(0);
    let seed = 0x12345678;
    for (let i = 0; i < n; i++) {
      seed = (seed * 1664525 + 1013904223) >>> 0;
      d[i] = (seed >>> 16) / 32768 - 1;
    }
    this.noise = buf;
    return this.ctx;
  }

  play(which) {
    if (this.muted) return;
    const ctx = this.wake();
    if (!ctx) return;
    if (ctx.state === "suspended") ctx.resume();

    const recipe = RECIPES[((Math.floor(which) % 8) + 8) % 8];
    let t = ctx.currentTime;

    for (const [secs, from, to, grit, amp0, amp1] of recipe) {
      const gain = ctx.createGain();
      gain.gain.setValueAtTime(amp0 * LEVEL, t);
      gain.gain.linearRampToValueAtTime(Math.max(0.0001, amp1 * LEVEL), t + secs);
      gain.connect(ctx.destination);

      if (grit < 1) {
        // Square, because that is what the helper writes and what a console
        // this size would have had.
        const osc = ctx.createOscillator();
        osc.type = "square";
        osc.frequency.setValueAtTime(from, t);
        osc.frequency.linearRampToValueAtTime(to, t + secs);
        const g = ctx.createGain();
        g.gain.value = 1 - grit;
        osc.connect(g).connect(gain);
        osc.start(t);
        osc.stop(t + secs);
      }
      if (grit > 0) {
        const src = ctx.createBufferSource();
        src.buffer = this.noise;
        src.loop = true;
        const g = ctx.createGain();
        g.gain.value = grit;
        src.connect(g).connect(gain);
        src.start(t);
        src.stop(t + secs);
      }
      t += secs;
    }
  }
}
