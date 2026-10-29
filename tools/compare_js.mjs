// Renders tools/scenario.json with the ORIGINAL pink-trombone-mod TypeScript and compares
// it with the C++ output. Usage (needs node + esbuild, and a checkout of pink-trombone-mod):
//   node tools/compare_js.mjs <path/to/pink-trombone-mod/src> tools/scenario.json cpp_out.f32
import { build } from "esbuild";
import fs from "fs";
import path from "path";
import os from "os";

const [srcDir, scenarioPath, cppPath] = process.argv.slice(2);
const entry = path.join(os.tmpdir(), "pt_entry.ts");
fs.writeFileSync(entry, `
export {Synthesizer} from ${JSON.stringify(path.resolve(srcDir, "Synthesizer"))};
export {TractUi} from ${JSON.stringify(path.resolve(srcDir, "TractUi"))};
export * as NoiseGenerator from ${JSON.stringify(path.resolve(srcDir, "NoiseGenerator"))};
`);
const outFile = path.join(os.tmpdir(), "pt_bundle.mjs");
await build({ entryPoints: [entry], bundle: true, format: "esm", outfile: outFile, logLevel: "error" });

// identical LCG to render_test.cpp, installed before the module creates any noise buffers
let state = 1;
Math.random = () => { state = Number((BigInt(state) * 1664525n + 1013904223n) & 0xffffffffn); return state / 4294967296; };

const { Synthesizer, TractUi, NoiseGenerator } = await import(outFile);
const sc = JSON.parse(fs.readFileSync(scenarioPath, "utf8"));
NoiseGenerator.setSeed(sc.seed);
const synth = new Synthesizer(sc.sampleRate);
synth.reset();
const ui = new TractUi(synth.tract, synth.tractShaper);

// tract coordinates -> canvas coordinates, the inverse of TractUi.getIndex/getDiameter
function toXY(index, diameter) {
   const angle = -0.24 + index * 0.64 * Math.PI / (synth.tract.lipStart - 1);
   const r = 298 - 60 * diameter;
   return { x: 340 - r * Math.cos(angle), y: 449 - r * Math.sin(angle) };
}
const touches = [];
const out = new Float32Array(sc.blocks * 512);
for (let b = 0; b < sc.blocks; b++) {
   const time = synth.tract.time;
   for (let i = touches.length - 1; i >= 0; i--) {
      if (!touches[i].alive && time > touches[i].endTime + 1) touches.splice(i, 1);
   }
   for (const e of sc.events.filter(e => e.block === b)) {
      if (e.type === "tongue" || e.type === "touch") {
         touches.push({ ...toXY(e.index, e.diameter), id: e.id, alive: true, index: e.index, diameter: e.diameter, startTime: time, endTime: 0 });
      } else if (e.type === "tongueMove") {
         const t = touches.find(t => t.id === e.id && t.alive);
         Object.assign(t, toXY(e.index, e.diameter), { index: e.index, diameter: e.diameter });
      } else if (e.type === "end") {
         const t = touches.find(t => t.id === e.id && t.alive);
         t.alive = false; t.endTime = time;
      } else if (e.type === "pitch") {
         synth.glottis.targetFrequency = e.frequency;
         synth.glottis.targetTenseness = e.tenseness;
         synth.glottis.isTouched = e.touched;
      }
   }
   ui.handleTouches(touches, time);
   synth.synthesize(out.subarray(b * 512, b * 512 + 512));
}

const cpp = new Float32Array(fs.readFileSync(cppPath).buffer.slice(0));
let maxDiff = 0, rms = 0, rmsDiff = 0;
for (let i = 0; i < out.length; i++) {
   const d = Math.abs(out[i] - cpp[i]);
   maxDiff = Math.max(maxDiff, d);
   rms += out[i] * out[i];
   rmsDiff += d * d;
}
rms = Math.sqrt(rms / out.length);
rmsDiff = Math.sqrt(rmsDiff / out.length);
console.log(`samples ${out.length}  js rms ${rms.toFixed(5)}  max diff ${maxDiff.toExponential(2)}  rms diff ${rmsDiff.toExponential(2)}`);
process.exit(maxDiff < 1e-3 ? 0 : 1);
