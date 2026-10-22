// Generates Tests/GrafixRenderTests/Fixtures/freehand-golden.json using the installed
// perfect-freehand 1.2.0 with Excalidraw's freedraw options.
// Usage: node scripts/port/freehand-golden.mjs [path/to/perfect-freehand]
import { createRequire } from "node:module";
import { writeFileSync, mkdirSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const require = createRequire(import.meta.url);
const pkg = process.argv[2] ?? join(homedir(), "Workspace/oss/npm-ref/node_modules/perfect-freehand");
const { getStroke } = require(pkg);

const curve = Array.from({ length: 30 }, (_, i) => [i * 4, Math.sin(i / 4) * 20 + i * 0.7]);
const zigzag = Array.from({ length: 20 }, (_, i) => [i * 6, i % 2 ? 18 : 0]);
const jittery = Array.from({ length: 40 }, (_, i) => [
  i * 3 + Math.sin(i * 1.7) * 2.1, Math.cos(i * 0.9) * 15 + Math.sin(i * 2.3)]);
const press = (pts, f) => pts.map((_, i) => f(i, pts.length));

const cases = [
  { name: "straight-sim", points: [[0, 0], [10, 0], [20, 0], [30, 0], [60, 0], [100, 0]], simulatePressure: true },
  { name: "straight-pressure", points: [[0, 0], [10, 0], [20, 0], [30, 0], [60, 0], [100, 0]], pressures: [0.2, 0.4, 0.6, 0.8, 0.9, 0.5], simulatePressure: false },
  { name: "curve-sim", points: curve, simulatePressure: true },
  { name: "curve-pressure", points: curve, pressures: press(curve, (i, n) => 0.2 + 0.7 * (i / n)), simulatePressure: false },
  { name: "zigzag-sim", points: zigzag, simulatePressure: true },
  { name: "zigzag-pressure", points: zigzag, pressures: press(zigzag, (i) => (i % 3) / 3 + 0.1), simulatePressure: false },
  { name: "jittery-sim-thick", points: jittery, simulatePressure: true, strokeWidth: 4 },
  { name: "streamline-low", points: curve, simulatePressure: true, streamline: 0.2 },
  { name: "single-sim", points: [[0, 0]], simulatePressure: true },
  { name: "single-pressure", points: [[5, 5]], pressures: [0.7], simulatePressure: false },
  { name: "two-points-sim", points: [[0, 0], [30, 10]], simulatePressure: true },
  { name: "two-points-pressure", points: [[0, 0], [30, 10]], pressures: [0.3, 0.8], simulatePressure: false },
  { name: "tiny-stroke", points: [[0, 0], [1, 1], [2, 1]], simulatePressure: true },
  { name: "empty-pressure", points: [], pressures: [], simulatePressure: false },
  { name: "empty-sim", points: [], simulatePressure: true },
  { name: "loop-back", points: [[0, 0], [30, 0], [60, 0], [30, 2], [0, 4], [-30, 6]], simulatePressure: true },
];

for (const c of cases) {
  c.strokeWidth ??= 2;
  c.streamline ??= 0.5;
  c.pressures ??= [];
  const input = c.simulatePressure
    ? c.points
    : c.points.length ? c.points.map(([x, y], i) => [x, y, c.pressures[i]]) : [[0, 0, 0.5]];
  c.outline = getStroke(input, {
    simulatePressure: c.simulatePressure,
    size: c.strokeWidth * 4.25,
    thinning: 0.6,
    smoothing: 0.5,
    streamline: c.streamline,
    easing: (t) => Math.sin((t * Math.PI) / 2),
    last: true,
  });
}

const out = join(dirname(fileURLToPath(import.meta.url)), "../../Tests/GrafixRenderTests/Fixtures/freehand-golden.json");
mkdirSync(dirname(out), { recursive: true });
writeFileSync(out, JSON.stringify(cases));
console.log(`wrote ${cases.length} cases to ${out}`);
