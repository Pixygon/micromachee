// Prove the browser's meta-game is the same meta-game.
//
//   node web/megacheck.mjs
//
// `mega.js` is a second implementation of `helper/src/mega.rs`. Two of anything
// drift, and a difficulty curve that quietly differs between the desktop and the
// site is exactly the kind of drift nobody notices until someone compares scores.
// So the constants are read back out of the Rust source and compared, and the
// curves are walked round by round.

import { readFileSync } from "node:fs";
import {
  Mega, LIVES, STEP_EVERY, START_SECONDS, FLOOR_SECONDS, SPEED_STEP, MAX_SPEED,
} from "./mega.js";

const rust = readFileSync(new URL("../helper/src/mega.rs", import.meta.url), "utf8");

/** `const NAME: type = value;` out of the Rust. */
function constant(name) {
  const m = rust.match(new RegExp(`const ${name}\\s*:\\s*[\\w]+\\s*=\\s*([0-9.]+)`));
  if (!m) throw new Error(`could not find ${name} in mega.rs`);
  return Number(m[1]);
}

let bad = 0;
const same = (what, mine, theirs) => {
  const ok = mine === theirs;
  if (!ok) bad++;
  console.log(`  ${ok ? "✓" : "✗"} ${what.padEnd(16)} browser ${mine}  helper ${theirs}`);
};

console.log("constants:");
same("LIVES", LIVES, constant("LIVES"));
same("STEP_EVERY", STEP_EVERY, constant("STEP_EVERY"));
same("START_SECONDS", START_SECONDS, constant("START_SECONDS"));
same("FLOOR_SECONDS", FLOOR_SECONDS, constant("FLOOR_SECONDS"));
same("SPEED_STEP", SPEED_STEP, constant("SPEED_STEP"));
same("MAX_SPEED", MAX_SPEED, constant("MAX_SPEED"));

// Which carts are dealt at all. Both sides drop the meta-game itself and
// anything that opted out; a shelf that differs here is two different games.
{
  const rustFilters = /c\.id != MEGA_ID && c\.in_mega/.test(rust);
  const shelf = [
    { id: "mega", title: "Mega" },
    { id: "quick", title: "Quick" },
    { id: "slow", title: "Slow", mega: false },
    { id: "silent", title: "Silent" },
  ];
  const dealt = new Mega(null, shelf).carts.map((c) => c.id).join(",");
  console.log("shelf:");
  same("rust filters on in_mega", true, rustFilters);
  same("dealt", dealt, "quick,silent");
}

// The curves, walked round by round against the Rust formulas restated here.
// If someone changes the shape in one place, this is where it shows up.
const rustSeconds = (r) => Math.max(FLOOR_SECONDS, START_SECONDS - Math.floor(r / STEP_EVERY));
const rustSpeed = (r) => Math.min(MAX_SPEED, 1 + Math.floor(r / STEP_EVERY) * SPEED_STEP);

const m = new Mega(null, [{ id: "x", title: "X", code: "" }]);
let curveBad = 0;
for (let round = 0; round < 200; round++) {
  m.round = round;
  if (m.seconds() !== rustSeconds(round)) curveBad++;
  if (Math.abs(m.speed() - rustSpeed(round)) > 1e-9) curveBad++;
}
console.log(`\ncurves over 200 rounds: ${curveBad === 0 ? "✓ identical" : `✗ ${curveBad} differences`}`);
if (curveBad) bad++;

// And the shape of the ramp itself, so a typo that makes it easier is caught.
m.round = 0;
console.log(`\nround 1:   ${m.seconds()}s at ${m.speed().toFixed(2)}x`);
m.round = STEP_EVERY * 5;
console.log(`round 26:  ${m.seconds()}s at ${m.speed().toFixed(2)}x`);
m.round = 1000;
console.log(`far in:    ${m.seconds()}s at ${m.speed().toFixed(2)}x  (the floor and the cap)`);
if (m.seconds() !== FLOOR_SECONDS || m.speed() !== MAX_SPEED) {
  console.log("  ✗ it does not bottom out where it should");
  bad++;
}

console.log(bad === 0 ? "\nthe browser plays the same meta-game." : `\n${bad} difference(s).`);
process.exit(bad === 0 ? 0 : 1);
