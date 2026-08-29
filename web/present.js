// The glass in front of the screen.
//
// `blit` paints the framebuffer as flat squares of colour, and that is what the
// pixel-parity check compares. This does the same job for a person watching:
// the console's 128x128 is drawn through whatever screen the current theme
// imitates — the raster gaps of a CRT, the glow of a phosphor, the RGB fringing
// of a shadow mask, the flat cell grid of a Game Boy's LCD.
//
// **It changes no pixel a cart drew.** Every effect happens after the
// framebuffer is final, on the way to the display, so `web/check.mjs` still
// compares identical pixels and no cart can tell which screen it is on. The
// effects themselves are theme DATA (`THEME_FX` in console-data.js, generated
// from helper/src/palettes.rs), so the description of a screen lives beside the
// palette it belongs to rather than in this file.
//
// The cost is bounded on purpose: the per-pixel work is four writes of 16k
// pixels (the console's own resolution), and everything expensive after that is
// drawImage and one blur, which the browser does on the GPU.

import { W, H } from "./console-data.js";

const canvas2d = (w, h) => {
  const c = document.createElement("canvas");
  c.width = w; c.height = h;
  return c;
};

const FLAT = { scanline: 0, bloom: 0, aberration: 0, noise: 0, vignette: 0, grid: 0, persist: 0 };

export class Presenter {
  /// `out` is the visible canvas. Its backing store is resized to whole
  /// console pixels, so nothing is ever drawn on a half pixel.
  constructor(out) {
    this.out = out;
    this.ctx = out.getContext("2d");
    this.u = 0;              // device pixels per console pixel
    this.frame = 0;

    // the framebuffer as colour, plus one canvas per channel for fringing
    this.base = canvas2d(W, H);
    this.baseCtx = this.base.getContext("2d");
    this.baseImg = this.baseCtx.createImageData(W, H);
    this.chan = [0, 1, 2].map(() => {
      const c = canvas2d(W, H);
      return { c, ctx: c.getContext("2d"), img: c.getContext("2d").createImageData(W, H) };
    });

    this.prev = null;        // the last frame, for persistence
    this.glow = null;        // half-resolution copy, for bloom
    this.mask = null;        // cached scanline / grid overlay
    this.maskKey = "";
    this.vig = null;         // cached vignette
    this.vigKey = "";
    this.noise = [];         // a few tiles of grain, cycled
    this.noiseKey = "";
  }

  /// Size the backing store to `u` device pixels per console pixel.
  resize(u) {
    if (u === this.u) return;
    this.u = u;
    const n = W * u;
    this.out.width = n;
    this.out.height = n;
    this.prev = canvas2d(n, n);
    this.glow = canvas2d(n >> 1, n >> 1);
    this.mask = null; this.maskKey = "";
    this.vig = null; this.vigKey = "";
    this.noise = []; this.noiseKey = "";
  }

  // ── the cached overlays ───────────────────────────────────────────────────
  // Each is one canvas, rebuilt only when the theme or the size changes, then
  // drawn with a single drawImage per frame.

  buildMask(fx) {
    const key = `${this.u}:${fx.scanline}:${fx.grid}`;
    if (key === this.maskKey) return;
    this.maskKey = key;
    const u = this.u, n = W * u;
    if (fx.scanline <= 0 && fx.grid <= 0) { this.mask = null; return; }
    const c = canvas2d(n, n), g = c.getContext("2d");
    if (fx.scanline > 0) {
      // The gap between raster lines. One console pixel is one line here, so
      // the dark band is a fraction of each row.
      const band = Math.max(1, Math.round(u / 3));
      g.fillStyle = `rgba(0,0,0,${fx.scanline})`;
      for (let y = 0; y < H; y++) g.fillRect(0, y * u + (u - band), n, band);
    }
    if (fx.grid > 0) {
      // An LCD has cells, so the gap runs both ways and is thin and hard.
      const band = Math.max(1, Math.round(u / 5));
      g.fillStyle = `rgba(0,0,0,${fx.grid * 0.55})`;
      for (let y = 0; y < H; y++) g.fillRect(0, y * u + (u - band), n, band);
      for (let x = 0; x < W; x++) g.fillRect(x * u + (u - band), 0, band, n);
    }
    this.mask = c;
  }

  buildVignette(fx) {
    const key = `${this.u}:${fx.vignette}`;
    if (key === this.vigKey) return;
    this.vigKey = key;
    if (fx.vignette <= 0) { this.vig = null; return; }
    const n = W * this.u;
    const c = canvas2d(n, n), g = c.getContext("2d");
    const grad = g.createRadialGradient(n / 2, n / 2, n * 0.30, n / 2, n / 2, n * 0.75);
    grad.addColorStop(0, "rgba(0,0,0,0)");
    grad.addColorStop(1, `rgba(0,0,0,${fx.vignette})`);
    g.fillStyle = grad;
    g.fillRect(0, 0, n, n);
    this.vig = c;
  }

  buildNoise() {
    const key = `${this.u}`;
    if (key === this.noiseKey && this.noise.length) return;
    this.noiseKey = key;
    // A handful of tiles, cycled per frame: grain that moves without costing a
    // random number per pixel per frame. Tiled at console resolution so the
    // grain is the size of a console pixel rather than a device pixel.
    this.noise = [];
    for (let k = 0; k < 4; k++) {
      const c = canvas2d(W, H), g = c.getContext("2d");
      const img = g.createImageData(W, H);
      for (let i = 0; i < W * H; i++) {
        const v = Math.random() * 255;
        img.data[i * 4] = v; img.data[i * 4 + 1] = v; img.data[i * 4 + 2] = v;
        img.data[i * 4 + 3] = 255;
      }
      g.putImageData(img, 0, 0);
      this.noise.push(c);
    }
  }

  // ── one frame ─────────────────────────────────────────────────────────────
  /// `screen` is the console's framebuffer, `palette` its eight colours, `fx`
  /// the screen the theme imitates, `u` device pixels per console pixel.
  draw(screen, palette, fx, u) {
    fx = fx || FLAT;
    this.resize(Math.max(1, Math.floor(u)));
    const ctx = this.ctx, n = W * this.u, px = screen.px;
    this.frame++;

    const rgb = palette.map((hex) => [
      parseInt(hex.slice(1, 3), 16),
      parseInt(hex.slice(3, 5), 16),
      parseInt(hex.slice(5, 7), 16),
    ]);

    // The framebuffer as colour. When the theme fringes, the same pass splits
    // it into channels, because a shadow mask does not move whole pixels — it
    // lands red, green and blue in slightly different places.
    const split = fx.aberration > 0;
    const b = this.baseImg.data;
    const [cr, cg, cb] = this.chan;
    for (let i = 0; i < W * H; i++) {
      const [r, g, bl] = rgb[px[i]];
      const o = i * 4;
      b[o] = r; b[o + 1] = g; b[o + 2] = bl; b[o + 3] = 255;
      if (split) {
        cr.img.data[o] = r; cr.img.data[o + 3] = 255;
        cg.img.data[o + 1] = g; cg.img.data[o + 3] = 255;
        cb.img.data[o + 2] = bl; cb.img.data[o + 3] = 255;
      }
    }
    this.baseCtx.putImageData(this.baseImg, 0, 0);

    ctx.save();
    ctx.globalCompositeOperation = "source-over";
    ctx.globalAlpha = 1;
    ctx.imageSmoothingEnabled = false;
    ctx.fillStyle = "#000";
    ctx.fillRect(0, 0, n, n);

    if (split) {
      const a = fx.aberration * this.u * 0.5;   // in device pixels
      cr.ctx.putImageData(cr.img, 0, 0);
      cg.ctx.putImageData(cg.img, 0, 0);
      cb.ctx.putImageData(cb.img, 0, 0);
      ctx.globalCompositeOperation = "lighter";
      ctx.drawImage(cr.c, -a, 0, n, n);
      ctx.drawImage(cg.c, 0, 0, n, n);
      ctx.drawImage(cb.c, a, 0, n, n);
      ctx.globalCompositeOperation = "source-over";
    } else {
      ctx.drawImage(this.base, 0, 0, n, n);
    }

    // What the last frame left behind. A phosphor ADDS its dying light; an LCD
    // instead LAGS, showing some of what was there a moment ago — which is why
    // the grid themes blend rather than add.
    if (fx.persist > 0 && this.prev) {
      ctx.globalAlpha = fx.persist;
      ctx.globalCompositeOperation = fx.grid > 0 ? "source-over" : "lighter";
      ctx.drawImage(this.prev, 0, 0);
      ctx.globalAlpha = 1;
      ctx.globalCompositeOperation = "source-over";
    }

    // Light spilling out of the bright parts. Taken from a half-size copy, so
    // the blur is wider and cheaper than doing it at full resolution.
    if (fx.bloom > 0) {
      const h = n >> 1, gctx = this.glow.getContext("2d");
      gctx.clearRect(0, 0, h, h);
      gctx.drawImage(this.out, 0, 0, h, h);
      ctx.save();
      ctx.filter = `blur(${Math.max(1, this.u * 0.7)}px)`;
      ctx.globalCompositeOperation = "lighter";
      ctx.globalAlpha = fx.bloom;
      ctx.drawImage(this.glow, 0, 0, h, h, 0, 0, n, n);
      ctx.restore();
    }

    // The structure of the screen itself: raster gaps, or LCD cells.
    if (fx.scanline > 0 || fx.grid > 0) {
      this.buildMask(fx);
      if (this.mask) ctx.drawImage(this.mask, 0, 0);
    }

    if (fx.noise > 0) {
      this.buildNoise();
      ctx.globalCompositeOperation = "lighter";
      ctx.globalAlpha = fx.noise;
      ctx.imageSmoothingEnabled = false;
      ctx.drawImage(this.noise[this.frame & 3], 0, 0, n, n);
      ctx.globalAlpha = 1;
      ctx.globalCompositeOperation = "source-over";
    }

    if (fx.vignette > 0) {
      this.buildVignette(fx);
      if (this.vig) ctx.drawImage(this.vig, 0, 0);
    }

    ctx.restore();

    // Keep this frame for the next one's persistence. Skipped entirely when
    // the theme has none, so most themes never pay for it.
    if (fx.persist > 0 && this.prev) {
      const p = this.prev.getContext("2d");
      p.globalCompositeOperation = "source-over";
      p.clearRect(0, 0, n, n);
      p.drawImage(this.out, 0, 0);
    }
  }
}
