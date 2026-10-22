// Emits Tests/GrafixRenderTests/Fixtures/rough-golden.json from the installed roughjs.
// Usage: node scripts/port/rough-golden.mjs
import { writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

import { createRequire } from 'node:module';
const ref = path.join(homedir(), 'Workspace/oss/npm-ref/node_modules/roughjs/bundled/rough.cjs.js');
const rough = createRequire(import.meta.url)(ref);
const gen = rough.generator();

const PATH_D = 'M 10 0 L 90 0 Q 100 0, 100 10 L 100 90 Q 100 100, 90 100 L 10 100 Q 0 100, 0 90 L 0 10 Q 0 0, 10 0';
const RELPATH = 'm 10 10 h 80 v 60 c -10 20 -50 20 -60 0 s -20 -30 -20 -60 z';
const cases = [];
const add = (name, fn, args, options = {}) => cases.push({ name, fn, args, options });

const fills = ['hachure', 'solid', 'cross-hatch', 'zigzag', 'dashed', 'zigzag-line'];
for (const fs of fills) {
  add(`rect-${fs}`, 'rectangle', [10, 20, 120, 80], { seed: 12345, fill: '#f00', fillStyle: fs });
  add(`rect-${fs}-gap`, 'rectangle', [0, 0, 60, 90], { seed: 77, fill: '#0f0', fillStyle: fs, hachureGap: 6, fillWeight: 2, strokeWidth: 2, roughness: 2 });
  add(`rect-${fs}-r0`, 'rectangle', [5, 5, 50, 40], { seed: 9, fill: '#00f', fillStyle: fs, roughness: 0.5, hachureAngle: 30 });
  add(`ellipse-${fs}`, 'ellipse', [100, 80, 120, 70], { seed: 4242, fill: '#f0f', fillStyle: fs });
  add(`polygon-${fs}`, 'polygon', [[[10, 10], [100, 30], [80, 120], [20, 90], [5, 50]]], { seed: 31337, fill: '#ccc', fillStyle: fs, hachureGap: 8 });
  add(`curve-${fs}`, 'curve', [[[0, 0], [50, 80], [100, 20], [150, 90], [200, 10]]], { seed: 2024, fill: '#abc', fillStyle: fs });
  add(`path-${fs}`, 'path', [PATH_D], { seed: 555, fill: '#123', fillStyle: fs });
}
add('rect-nofill', 'rectangle', [0, 0, 100, 50], { seed: 1 });
add('rect-nofill-pv', 'rectangle', [0, 0, 100, 50], { seed: 2, preserveVertices: true });
add('rect-dms', 'rectangle', [0, 0, 100, 50], { seed: 3, disableMultiStroke: true, strokeWidth: 3 });
add('rect-dmsf', 'rectangle', [0, 0, 100, 50], { seed: 3, disableMultiStrokeFill: true, fill: 'red', hachureGap: 5 });
add('rect-large', 'rectangle', [0, 0, 600, 400], { seed: 8, roughness: 1.5, bowing: 2, fill: 'red', hachureGap: 12 });
add('rect-nostroke', 'rectangle', [0, 0, 100, 50], { seed: 3, stroke: 'none', fill: 'red' });
for (const r of [0, 1, 2]) {
  add(`ellipse-r${r}`, 'ellipse', [50, 50, 100, 60], { seed: 100 + r, roughness: r });
  add(`ellipse-solid-r${r}`, 'ellipse', [50, 50, 100, 60], { seed: 200 + r, roughness: r, fill: 'blue', fillStyle: 'solid' });
}
add('ellipse-big', 'ellipse', [300, 200, 500, 300], { seed: 6, curveStepCount: 12 });
add('circle', 'circle', [40, 40, 80], { seed: 17 });
add('circle-fill', 'circle', [40, 40, 80], { seed: 18, fill: 'green' });
add('line', 'line', [0, 0, 100, 50], { seed: 5 });
add('line-long', 'line', [0, 0, 400, 300], { seed: 5, strokeWidth: 4 });
add('line-short', 'line', [0, 0, 5, 5], { seed: 5 });
add('line-pv', 'line', [10, 10, 200, 20], { seed: 5, preserveVertices: true, roughness: 2.5 });
add('linearPath', 'linearPath', [[[0, 0], [50, 40], [100, 0], [150, 60]]], { seed: 11 });
add('linearPath2', 'linearPath', [[[0, 0], [50, 40]]], { seed: 11 });
add('polygon', 'polygon', [[[0, 0], [100, 10], [90, 80]]], { seed: 12, preserveVertices: true });
add('curve', 'curve', [[[0, 0], [50, 80], [100, 20], [150, 90]]], { seed: 13 });
add('curve3', 'curve', [[[0, 0], [50, 80], [100, 20]]], { seed: 13, disableMultiStroke: true });
add('curve-solid-r2', 'curve', [[[0, 0], [50, 80], [100, 20], [150, 90], [200, 0]]], { seed: 14, roughness: 2, fill: 'red', fillStyle: 'solid' });
add('path', 'path', [PATH_D], { seed: 15 });
add('path-pv', 'path', [PATH_D], { seed: 15, preserveVertices: true, disableMultiStroke: true });
add('path-rel', 'path', [RELPATH], { seed: 16, fill: 'red' });
add('path-rel-solid', 'path', [RELPATH], { seed: 16, fill: 'red', fillStyle: 'solid' });
add('path-simplified', 'path', [PATH_D], { seed: 19, simplification: 0.5, fill: 'red' });
add('path-arc', 'path', ['M 10 80 A 45 45, 0, 0, 0, 125 125 L 125 80 Z'], { seed: 20, fill: 'red', fillStyle: 'solid' });
add('path-multi', 'path', ['M0 0 L50 0 L50 50 L0 50 Z M10 10 L40 10 L40 40 L10 40 Z'], { seed: 21, fill: 'red' });
add('path-smooth', 'path', ['M0 0 C 20 50, 60 50, 80 0 S 140 -50, 160 0 Q 180 40, 200 0 T 240 0'], { seed: 22 });

const out = cases.map((c) => {
  const toPts = (a) => (Array.isArray(a) ? a : a);
  const d = gen[c.fn](...c.args.map(toPts), { ...c.options });
  return {
    name: c.name, fn: c.fn, args: c.args, options: c.options,
    shape: d.shape,
    sets: d.sets.map((s) => ({ type: s.type, ops: s.ops.map((o) => ({ op: o.op, data: o.data })) })),
  };
});
const here = path.dirname(fileURLToPath(import.meta.url));
const dest = path.join(here, '../../Tests/GrafixRenderTests/Fixtures/rough-golden.json');
writeFileSync(dest, JSON.stringify(out));
console.log(`wrote ${out.length} cases to ${dest}`);
