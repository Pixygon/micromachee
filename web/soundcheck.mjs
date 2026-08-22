// Prove the browser's speaker is the console's speaker.
//
//   node web/soundcheck.mjs
//
// `sound.js` restates the recipe table from `helper/src/wav.rs`. Restated
// numbers drift, so these are read back out of the Rust and compared, exactly
// the way megacheck.mjs does for the meta-game's difficulty curve.

import { readFileSync } from "node:fs";
import { RECIPES, NAMES } from "./sound.js";

const rust = readFileSync(new URL("../helper/src/wav.rs", import.meta.url), "utf8");

// Everything between `fn recipe(` and its closing brace, arm by arm.
const body = rust.slice(rust.indexOf("fn recipe("));
const arms = [...body.matchAll(/^\s*(\d|_)\s*=>\s*(vec!\[[\s\S]*?\]),$/gm)];
if (arms.length !== 8) {
  console.error(`✗ found ${arms.length} arms in recipe(), expected 8`);
  process.exit(1);
}

const num = (s) => Number(s);
let bad = 0;

console.log("recipes:");
arms.forEach(([, key, vec], order) => {
  const i = key === "_" ? 7 : Number(key);
  const segs = [...vec.matchAll(/seg\(([^)]*)\)/g)].map((m) =>
    m[1].split(",").map((v) => num(v.trim())),
  );
  const mine = RECIPES[i];
  const same =
    mine &&
    mine.length === segs.length &&
    segs.every((s, j) => s.length === 6 && s.every((v, k) => Math.abs(v - mine[j][k]) < 1e-6));
  if (!same) bad++;
  const label = (NAMES[i] || i).padEnd(7);
  console.log(`  ${same ? "✓" : "✗"} ${label} ${segs.length} segment(s)`);
  if (!same) {
    console.log(`      helper  ${JSON.stringify(segs)}`);
    console.log(`      browser ${JSON.stringify(mine)}`);
  }
});

// A name in the wrong slot is a pickup that sounds like a death.
const names = rust.match(/pub const NAMES: \[&str; 8\] =\s*\[([\s\S]*?)\];/);
const rustNames = [...names[1].matchAll(/"([a-z]+)"/g)].map((m) => m[1]);
const namesMatch = rustNames.join(",") === NAMES.join(",");
if (!namesMatch) bad++;
console.log(`\n${namesMatch ? "✓" : "✗"} the bank is in the same order`);

if (bad > 0) {
  console.error(`\n✗ ${bad} sound(s) differ between the browser and the helper`);
  process.exit(1);
}
console.log("\nthe browser sounds like the console does.");
