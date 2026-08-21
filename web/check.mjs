// Prove the browser console draws exactly what the helper draws.
//
//   node web/check.mjs                 every cart on the shelf
//   node web/check.mjs carts/snake.lua --frames 90 --hold 2
//
// A second implementation of a renderer is a liability unless something checks
// it, and "looks right" is not a check at 128x128. This runs the same cart to
// the same frame in both and compares all 16384 pixels. Any difference is
// printed as a coordinate and the two colour indexes, because that is what
// tells you which primitive is wrong.

import { execFileSync } from "node:child_process";
import { inflateSync } from "node:zlib";
import { readFileSync, unlinkSync, readdirSync } from "node:fs";
import { LuaFactory } from "wasmoon";
import { loadCart, W, H } from "./micromachee.js";

const HELPER = new URL("../helper/target/release/omarchy-micromachee", import.meta.url).pathname;

/// The helper writes 128x128, bit depth 4, indexed, filter 0 — nothing else.
function decodeIndexed(buf) {
  let i = 8, idat = [], width = 0, height = 0, depth = 0;
  while (i + 8 <= buf.length) {
    const len = buf.readUInt32BE(i);
    const kind = buf.toString("ascii", i + 4, i + 8);
    const body = buf.subarray(i + 8, i + 8 + len);
    if (kind === "IHDR") {
      width = body.readUInt32BE(0);
      height = body.readUInt32BE(4);
      depth = body[8];
    } else if (kind === "IDAT") idat.push(body);
    else if (kind === "IEND") break;
    i += 12 + len;
  }
  const raw = inflateSync(Buffer.concat(idat));
  const stride = Math.ceil((width * depth) / 8);
  const out = new Uint8Array(width * height);
  let off = 0;
  for (let y = 0; y < height; y++) {
    if (raw[off] !== 0) throw new Error(`unexpected filter ${raw[off]} on row ${y}`);
    const row = raw.subarray(off + 1, off + 1 + stride);
    off += 1 + stride;
    for (let x = 0; x < width; x++) {
      out[y * width + x] = x % 2 === 0 ? row[x >> 1] >> 4 : row[x >> 1] & 0x0f;
    }
  }
  return out;
}

async function runHere(factory, code, frames, hold) {
  const cart = await loadCart(factory, code);
  cart.init();
  cart.setHeld(hold);
  for (let f = 0; f < Math.max(1, frames); f++) {
    cart.update();
    cart.draw();
  }
  const px = Uint8Array.from(cart.screen.px);
  cart.close();
  return px;
}

function runThere(file, frames, hold) {
  const out = `/tmp/mm-check-${process.pid}.png`;
  const args = [file, "--frames", String(frames), "-o", out];
  if (hold) {
    const bits = [];
    for (let b = 0; b < 6; b++) if (hold & (1 << b)) bits.push(String(b));
    if (bits.length) args.push("--hold", bits.join(","));
  }
  execFileSync(HELPER, ["shot", ...args], { stdio: "pipe" });
  const px = decodeIndexed(readFileSync(out));
  unlinkSync(out);
  return px;
}

function compare(a, b) {
  const diffs = [];
  for (let i = 0; i < a.length; i++) {
    if (a[i] !== b[i]) diffs.push([i % W, Math.floor(i / W), a[i], b[i]]);
  }
  return diffs;
}

const argv = process.argv.slice(2);
let frames = 90;
let hold = 0;
const files = [];
for (let i = 0; i < argv.length; i++) {
  if (argv[i] === "--frames") frames = Number(argv[++i]);
  else if (argv[i] === "--hold") hold = argv[++i].split(",").reduce((m, b) => m | (1 << Number(b)), 0);
  else files.push(argv[i]);
}
if (files.length === 0) {
  const dir = new URL("../carts/", import.meta.url).pathname;
  for (const f of readdirSync(dir)) if (f.endsWith(".lua")) files.push(dir + f);
}

const factory = new LuaFactory();
let bad = 0;
for (const file of files.sort()) {
  const code = readFileSync(file, "utf8");
  const name = file.split("/").pop();
  let mine, theirs;
  try {
    mine = await runHere(factory, code, frames, hold);
    theirs = runThere(file, frames, hold);
  } catch (e) {
    console.log(`  ✗ ${name.padEnd(14)} ${e.message.split("\n")[0]}`);
    bad++;
    continue;
  }
  const diffs = compare(mine, theirs);
  if (diffs.length === 0) {
    console.log(`  ✓ ${name.padEnd(14)} identical at frame ${frames}`);
  } else {
    bad++;
    const [x, y, got, want] = diffs[0];
    console.log(
      `  ✗ ${name.padEnd(14)} ${diffs.length}/${W * H} pixels differ — ` +
      `first at ${x},${y}: browser drew ${got}, helper drew ${want}`
    );
  }
}
console.log(bad === 0 ? "\nthe browser draws what the console draws." : `\n${bad} cart(s) differ.`);
process.exit(bad === 0 ? 0 : 1);
