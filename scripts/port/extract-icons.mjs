#!/usr/bin/env node
// Faithful port of Excalidraw's icon set into native Swift.
//
// Reads packages/excalidraw/components/icons.tsx from the Excalidraw checkout,
// turns every JSX/SVG primitive into absolute M/L/C/Z path data in a 512x512 box,
// and writes Sources/GrafixPort/Generated/PortIcons.swift.
//
// Run from the repository root:
//   node scripts/port/extract-icons.mjs
//
// The Excalidraw checkout is read from EXCALIDRAW_REPO, defaulting to
// ~/Workspace/oss/excalidraw. Nothing is written outside this repository.
// Plain Node ESM, no dependencies, no network.

import { execFileSync } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const SCRIPT_PATH = fileURLToPath(import.meta.url);
const GRAFIX_ROOT = resolve(dirname(SCRIPT_PATH), "..", "..");
const REPO = process.env.EXCALIDRAW_REPO ?? "/Users/uditagarwal19199/Workspace/oss/excalidraw";
const ICONS_PATH = join(REPO, "packages", "excalidraw", "components", "icons.tsx");
const OUT_PATH = join(GRAFIX_ROOT, "Sources", "GrafixPort", "Generated", "PortIcons.swift");

/** Authoring box that every generated icon is normalised into. */
const BOX = 512;
/** Stroke width used when the source has none, in the 512 box. */
const DEFAULT_STROKE_WIDTH = 32;

/** Requested key -> candidate component names in icons.tsx (first match wins). */
const REQUESTED = [
  // Toolbar tools.
  ["hand", ["handIcon"]],
  ["selection", ["SelectionIcon"]],
  ["lasso", ["LassoIcon"]],
  ["rectangle", ["RectangleIcon"]],
  ["diamond", ["DiamondIcon"]],
  ["ellipse", ["EllipseIcon"]],
  ["arrow", ["ArrowIcon"]],
  ["line", ["LineIcon"]],
  ["freedraw", ["FreedrawIcon"]],
  ["autoshape", ["drawShapeToolIcon"]],
  ["text", ["TextIcon"]],
  ["stickynote", ["stickyNoteToolIcon"]],
  ["image", ["ImageIcon"]],
  ["eraser", ["EraserIcon"]],
  ["frame", ["frameToolIcon"]],
  ["embeddable", ["EmbedIcon"]],
  ["laser", ["laserPointerToolIcon"]],
  ["bucketfill", ["bucketFillIcon"]],
  // Chrome.
  ["undo", ["UndoIcon"]],
  ["redo", ["RedoIcon"]],
  ["zoomin", ["ZoomInIcon"]],
  ["zoomout", ["ZoomOutIcon"]],
  ["fit", ["zoomAreaIcon"]],
  ["grid", ["gridIcon"]],
  ["zen", ["coffeeIcon"]],
  ["stats", ["abacusIcon"]],
  ["lock", ["LockedIcon"]],
  ["unlock", ["UnlockedIcon"]],
  ["link", ["LinkIcon"]],
  ["duplicate", ["DuplicateIcon"]],
  ["trash", ["TrashIcon"]],
  ["group", ["GroupIcon"]],
  ["ungroup", ["UngroupIcon"]],
  ["alignleft", ["AlignLeftIcon"]],
  ["aligncenter", ["CenterHorizontallyIcon"]],
  ["alignright", ["AlignRightIcon"]],
  ["exportImage", ["ExportImageIcon"]],
  ["exportJSON", ["exportToFileIcon"]],
  ["save", ["save"]],
  ["load", ["LoadIcon"]],
  ["clear", ["TrashIcon"]],
  ["theme", ["MoonIcon"]],
  ["help", ["HelpIcon"]],
  ["commandPalette", ["boltIcon"]],
  ["search", ["searchIcon"]],
  ["library", ["LibraryIcon"]],
  ["present", ["presentationIcon"]],
  ["magic", ["MagicIcon"]],
  ["pencil", ["pencilIcon"]],
  ["penmode", ["PenModeIcon"]],
  ["check", ["checkIcon"]],
  ["cross", ["CloseIcon"]],
  // Shortcuts dialog header links.
  ["externallink", ["ExternalLinkIcon"]],
  ["github", ["GithubIcon"]],
  ["youtube", ["youtubeIcon"]],
  ["chevronDown", ["chevronDownIcon"]],
  ["dots", ["DotsIcon"]],
  ["plus", ["PlusIcon"]],
  ["minus", ["zoomOut"]],
  ["reset", ["ZoomResetIcon"]],
  // Styles panel controls.
  ["strokewidthbase", ["StrokeWidthBaseIcon"]],
  ["strokewidthbold", ["StrokeWidthBoldIcon"]],
  ["strokewidthextrabold", ["StrokeWidthExtraBoldIcon"]],
  ["strokestylesolid", ["StrokeStyleSolidIcon"]],
  ["strokestyledashed", ["StrokeStyleDashedIcon"]],
  ["strokestyledotted", ["StrokeStyleDottedIcon"]],
  ["architect", ["SloppinessArchitectIcon"]],
  ["artist", ["SloppinessArtistIcon"]],
  ["cartoonist", ["SloppinessCartoonistIcon"]],
  // Friendly aliases for the properties panel and menus.
  ["sun", ["SunIcon"]],
  ["hamburger", ["HamburgerMenuIcon"]],
  ["fillhachure", ["FillHachureIcon"]],
  ["fillcrosshatch", ["FillCrossHatchIcon"]],
  ["fillsolid", ["FillSolidIcon"]],
  ["fillzigzag", ["FillZigZagIcon"]],
  ["edgesharp", ["EdgeSharpIcon"]],
  ["edgeround", ["EdgeRoundIcon"]],
  ["arrowsharp", ["sharpArrowIcon"]],
  ["arrowround", ["roundArrowIcon"]],
  ["arrowelbow", ["elbowArrowIcon"]],
  ["mermaid", ["mermaidLogoIcon"]],
  ["toolslock", ["LockedIcon"]],
  ["sendtoback", ["SendToBackIcon"]],
  ["sendbackward", ["SendBackwardIcon"]],
  ["bringforward", ["BringForwardIcon"]],
  ["bringtofront", ["BringToFrontIcon"]],
  ["aligntop", ["AlignTopIcon"]],
  ["alignbottom", ["AlignBottomIcon"]],
  ["centervertically", ["CenterVerticallyIcon"]],
  ["centerhorizontally", ["CenterHorizontallyIcon"]],
  ["distributehorizontally", ["DistributeHorizontallyIcon"]],
  ["distributevertically", ["DistributeVerticallyIcon"]],
  ["fontsizesmall", ["FontSizeSmallIcon"]],
  ["fontsizemedium", ["FontSizeMediumIcon"]],
  ["fontsizelarge", ["FontSizeLargeIcon"]],
  ["fontsizeextralarge", ["FontSizeExtraLargeIcon"]],
  ["fontfamilyhanddrawn", ["FontFamilyHeadingIcon"]],
  ["fontfamilynormal", ["FontFamilyNormalIcon"]],
  ["fontfamilycode", ["FontFamilyCodeIcon", "codeIcon"]],
  ["textalignleft", ["TextAlignLeftIcon"]],
  ["textaligncenter", ["TextAlignCenterIcon"]],
  ["textalignright", ["TextAlignRightIcon"]],
  ["textaligntop", ["TextAlignTopIcon"]],
  ["textalignmiddle", ["TextAlignMiddleIcon"]],
  ["textalignbottom", ["TextAlignBottomIcon"]],
  ["crop", ["cropIcon"]],
  ["flipvertical", ["flipVertical"]],
  ["fliphorizontal", ["flipHorizontal"]],
  ["eye", ["eyeIcon"]],
  ["eyeclosed", ["eyeClosedIcon"]],
  ["fullscreen", ["fullscreenIcon"]],
  ["settings", ["settingsIcon"]],
  ["sidebar", ["sidebarRightIcon"]],
  ["chevronright", ["chevronRight"]],
  ["chevronleft", ["chevronLeftIcon"]],
  ["chevronup", ["collapseUpIcon", "upIcon"]],
  ["copy", ["copyIcon"]],
  ["download", ["downloadIcon"]],
  ["snap", ["magnetIcon"]],
  ["png", ["pngIcon"]],
  ["svg", ["svgIcon"]],
  ["pin", ["PinIcon"]],
  ["more", ["DotsIcon"]],
];

/** Export names in icons.tsx that are data helpers, not icons. */
const NOT_ICONS = new Set(["iconFillColor", "emptyIcon", "createIcon"]);

/** Human-readable explanation for keys whose geometry is reused from another icon. */
const REUSE_NOTES = {
  clear: "Clear canvas reuses TrashIcon; Excalidraw's own ClearCanvas menu item uses TrashIcon.",
  trash: "Shares geometry with clear by design; both are TrashIcon upstream.",
  minus:
    "No minus glyph exists in icons.tsx. Mapped to the font-awesome `zoomOut` component, which is a solid horizontal bar. Identical geometry is not invented.",
  aligncenter:
    "The shape alignment row in Excalidraw uses CenterHorizontallyIcon for the middle action.",
  fit: "Zoom-to-fit actions use zoomAreaIcon in actions/actionCanvas.tsx.",
  reset: "The resetZoom action uses ZoomResetIcon in actions/actionCanvas.tsx.",
  cross: "CloseIcon is a 20x20 X (the only cross glyph in the file).",
  theme: "Theme toggle uses MoonIcon (sun/moon pair; the dark-theme action shows MoonIcon).",
  zen: "Zen mode action uses coffeeIcon in actions/actionToggleZenMode.tsx.",
  stats: "Toggle-stats action uses abacusIcon in actions/actionToggleStats.tsx.",
  commandPalette: "The command palette menu item uses boltIcon in main-menu/DefaultItems.tsx.",
  present: "presentationIcon (a projector screen with a chart) is the only presentation glyph.",
};

const EMPTY_ARRAY = Object.freeze([]);

// ---------------------------------------------------------------------------
// Small text utilities
// ---------------------------------------------------------------------------

function fail(message) {
  console.error(`[extract-icons] ${message}`);
  process.exit(1);
}

function isNameStart(ch) {
  return /[A-Za-z_$]/.test(ch);
}
function isNameChar(ch) {
  return /[A-Za-z0-9_$]/.test(ch);
}
function isSpace(ch) {
  return ch === " " || ch === "\t" || ch === "\n" || ch === "\r";
}

function skipSpace(text, i) {
  while (i < text.length && isSpace(text[i])) {
    i += 1;
  }
  return i;
}

/** Skips a quoted string (or template literal) starting at `i`. Returns the index after it. */
function skipString(text, i) {
  const quote = text[i];
  i += 1;
  while (i < text.length) {
    const ch = text[i];
    if (ch === "\\") {
      i += 2;
      continue;
    }
    if (ch === quote) {
      return i + 1;
    }
    i += 1;
  }
  return text.length;
}

/** Reads a quoted string starting at `i`; returns { value, end } or null. */
function readString(text, i) {
  const quote = text[i];
  if (quote !== '"' && quote !== "'" && quote !== "`") {
    return null;
  }
  let out = "";
  i += 1;
  while (i < text.length) {
    const ch = text[i];
    if (ch === "\\") {
      const next = text[i + 1] ?? "";
      out += next === "n" ? "\n" : next === "t" ? "\t" : next;
      i += 2;
      continue;
    }
    if (ch === quote) {
      return { value: out, end: i + 1 };
    }
    out += ch;
    i += 1;
  }
  return null;
}

/**
 * Given `text[start]` being an opening bracket, returns the index just after the
 * matching close bracket. Strings and comments are skipped. Never throws.
 */
function readBalanced(text, start) {
  const pairs = { "(": ")", "[": "]", "{": "}" };
  const stack = [pairs[text[start]]];
  let i = start + 1;
  while (i < text.length) {
    const ch = text[i];
    if (ch === '"' || ch === "'" || ch === "`") {
      i = skipString(text, i);
      continue;
    }
    if (ch === "/" && text[i + 1] === "/") {
      const nl = text.indexOf("\n", i);
      i = nl < 0 ? text.length : nl + 1;
      continue;
    }
    if (ch === "/" && text[i + 1] === "*") {
      const end = text.indexOf("*/", i + 2);
      i = end < 0 ? text.length : end + 2;
      continue;
    }
    if (ch === "(" || ch === "[" || ch === "{") {
      stack.push(pairs[ch]);
      i += 1;
      continue;
    }
    if (ch === ")" || ch === "]" || ch === "}") {
      if (stack[stack.length - 1] !== ch) {
        // Unbalanced input: stop rather than guess.
        return i;
      }
      stack.pop();
      i += 1;
      if (stack.length === 0) {
        return i;
      }
      continue;
    }
    i += 1;
  }
  return text.length;
}

/** Splits on top-level commas (bracket and string aware). */
function splitTopLevel(text, separator = ",") {
  const parts = [];
  let depth = 0;
  let startIndex = 0;
  let i = 0;
  while (i < text.length) {
    const ch = text[i];
    if (ch === '"' || ch === "'" || ch === "`") {
      i = skipString(text, i);
      continue;
    }
    if (ch === "(" || ch === "[" || ch === "{") {
      depth += 1;
      i += 1;
      continue;
    }
    if (ch === ")" || ch === "]" || ch === "}") {
      depth -= 1;
      i += 1;
      continue;
    }
    if (depth === 0 && text.startsWith(separator, i)) {
      parts.push(text.slice(startIndex, i));
      i += separator.length;
      startIndex = i;
      continue;
    }
    i += 1;
  }
  parts.push(text.slice(startIndex));
  return parts.map((part) => part.trim()).filter((part) => part.length > 0);
}

// ---------------------------------------------------------------------------
// Tiny arithmetic evaluator (for attributes such as `strokeWidth={1.25}`)
// ---------------------------------------------------------------------------

function evalArithmetic(text) {
  let i = 0;
  const expr = text.replace(/\s+/g, "");

  function parseExpression() {
    let value = parseTerm();
    while (expr[i] === "+" || expr[i] === "-") {
      const op = expr[i];
      i += 1;
      const rhs = parseTerm();
      if (value === null || rhs === null) {
        return null;
      }
      value = op === "+" ? value + rhs : value - rhs;
    }
    return value;
  }
  function parseTerm() {
    let value = parseFactor();
    while (expr[i] === "*" || expr[i] === "/") {
      const op = expr[i];
      i += 1;
      const rhs = parseFactor();
      if (value === null || rhs === null) {
        return null;
      }
      value = op === "*" ? value * rhs : value / rhs;
    }
    return value;
  }
  function parseFactor() {
    if (expr[i] === "-") {
      i += 1;
      const value = parseFactor();
      return value === null ? null : -value;
    }
    if (expr[i] === "+") {
      i += 1;
      return parseFactor();
    }
    if (expr[i] === "(") {
      i += 1;
      const value = parseExpression();
      if (expr[i] !== ")") {
        return null;
      }
      i += 1;
      return value;
    }
    const start = i;
    while (i < expr.length && /[0-9.]/.test(expr[i])) {
      i += 1;
    }
    if (i === start) {
      return null;
    }
    const value = Number(expr.slice(start, i));
    return Number.isFinite(value) ? value : null;
  }

  const result = parseExpression();
  if (result === null || i !== expr.length) {
    return null;
  }
  return result;
}

// ---------------------------------------------------------------------------
// Source definitions
// ---------------------------------------------------------------------------

const DEFINITION_RE = /^[ \t]*(?:export\s+)?const\s+([A-Za-z_$][\w$]*)\s*(?::[^=\n]*)?=\s*/gm;

/** Finds the first `name(` call inside `text`; returns the index of `(` or -1. */
function findCallOpen(text, name) {
  const re = new RegExp(`(?:^|[^A-Za-z0-9_$.])${name}\\s*\\(`, "g");
  const match = re.exec(text);
  if (!match) {
    return -1;
  }
  return text.indexOf("(", match.index + match[0].length - 1);
}

function statementEnd(text, start) {
  let depth = 0;
  let i = start;
  const limit = Math.min(text.length, start + 20000);
  while (i < limit) {
    const ch = text[i];
    if (ch === '"' || ch === "'" || ch === "`") {
      i = skipString(text, i);
      continue;
    }
    if (ch === "/" && text[i + 1] === "/") {
      const nl = text.indexOf("\n", i);
      i = nl < 0 ? text.length : nl + 1;
      continue;
    }
    if (ch === "/" && text[i + 1] === "*") {
      const end = text.indexOf("*/", i + 2);
      i = end < 0 ? text.length : end + 2;
      continue;
    }
    if (ch === "(" || ch === "[" || ch === "{") {
      depth += 1;
      i += 1;
      continue;
    }
    if (ch === ")" || ch === "]" || ch === "}") {
      depth -= 1;
      i += 1;
      continue;
    }
    if (ch === ";" && depth <= 0) {
      return i;
    }
    i += 1;
  }
  return Math.min(text.length, start + 20000);
}

/** Collects every `const NAME = ...` statement in the file. */
function collectDefinitions(source) {
  const defs = new Map();
  DEFINITION_RE.lastIndex = 0;
  let match = DEFINITION_RE.exec(source);
  while (match) {
    const name = match[1];
    const start = match.index + match[0].length;
    const end = statementEnd(source, start);
    const rhs = source.slice(start, end).trim();
    if (!defs.has(name)) {
      defs.set(name, { name, rhs });
    }
    DEFINITION_RE.lastIndex = end;
    match = DEFINITION_RE.exec(source);
  }
  return defs;
}

/** Parses an object literal into ordered entries: {spread} or {key, valueText}. */
function parseObjectEntries(objectText) {
  const text = objectText.trim();
  const open = text.indexOf("{");
  if (open < 0) {
    return null;
  }
  const close = readBalanced(text, open);
  const inner = text.slice(open + 1, close - 1);
  const entries = [];
  for (const part of splitTopLevel(inner)) {
    if (part.startsWith("...")) {
      entries.push({ spread: part.slice(3).trim() });
      continue;
    }
    const colon = findTopLevelColon(part);
    if (colon < 0) {
      entries.push({ key: part.trim(), valueText: "true" });
      continue;
    }
    entries.push({
      key: part.slice(0, colon).trim().replace(/^["']|["']$/g, ""),
      valueText: part.slice(colon + 1).trim(),
    });
  }
  return entries;
}

function findTopLevelColon(text) {
  let depth = 0;
  let i = 0;
  while (i < text.length) {
    const ch = text[i];
    if (ch === '"' || ch === "'" || ch === "`") {
      i = skipString(text, i);
      continue;
    }
    if (ch === "(" || ch === "[" || ch === "{") {
      depth += 1;
      i += 1;
      continue;
    }
    if (ch === ")" || ch === "]" || ch === "}") {
      depth -= 1;
      i += 1;
      continue;
    }
    if (ch === ":" && depth === 0) {
      return i;
    }
    i += 1;
  }
  return -1;
}

// ---------------------------------------------------------------------------
// Attribute value resolution
// ---------------------------------------------------------------------------

const VISIBLE_PAINT_HELPERS = {
  iconFillColor: "var(--icon-fill-color)",
  handlerColor: "var(--handler-color)",
  strokeColor: "var(--color-primary)",
};

/**
 * Resolves a raw JSX attribute value into a plain JS value.
 * Returns { kind: "string" | "number" | "bool" | "unknown" | "object", value? }
 * `bindings` maps a `.map((item) => ...)` parameter name to the current array item.
 */
function resolveValue(raw, defs, bindings) {
  if (raw === undefined || raw === null) {
    return { kind: "missing" };
  }
  if (raw.quoted !== undefined) {
    return { kind: "string", value: raw.quoted };
  }
  const expr = (raw.expr ?? "").trim();
  if (expr.length === 0) {
    return { kind: "unknown", value: expr };
  }
  if (bindings && bindings.has(expr)) {
    return { kind: "string", value: bindings.get(expr) };
  }
  if (expr.startsWith("{") && expr.endsWith("}")) {
    return { kind: "object", value: expr };
  }
  const str = readString(expr, 0);
  if (str && str.end === expr.length) {
    return { kind: "string", value: str.value };
  }
  const num = evalArithmetic(expr);
  if (num !== null) {
    return { kind: "number", value: num };
  }
  if (expr === "true" || expr === "false") {
    return { kind: "bool", value: expr === "true" };
  }
  for (const [helper, resolved] of Object.entries(VISIBLE_PAINT_HELPERS)) {
    if (new RegExp(`^${helper}\\s*\\(`).test(expr)) {
      return { kind: "string", value: resolved };
    }
  }
  if (expr.includes("THEME.LIGHT")) {
    // `theme === THEME.LIGHT ? "#fff" : "#1e1e1e"` and similar: both branches paint.
    return { kind: "string", value: expr.includes('"#fff"') ? "#fff" : "#1e1e1e" };
  }
  const def = defs.get(expr);
  if (def) {
    if (/^["'`]/.test(def.rhs)) {
      const resolved = readString(def.rhs, 0);
      if (resolved) {
        return { kind: "string", value: resolved.value };
      }
    }
    const number = evalArithmetic(def.rhs);
    if (number !== null) {
      return { kind: "number", value: number };
    }
  }
  return { kind: "unknown", value: expr };
}

function toNumber(resolvedValue, fallback = null) {
  if (!resolvedValue) {
    return fallback;
  }
  if (resolvedValue.kind === "number") {
    return resolvedValue.value;
  }
  if (resolvedValue.kind === "string") {
    const num = Number(resolvedValue.value);
    return Number.isFinite(num) ? num : fallback;
  }
  return fallback;
}

function isPaintVisible(resolvedValue, defaultVisible) {
  if (!resolvedValue || resolvedValue.kind === "missing") {
    return defaultVisible;
  }
  if (resolvedValue.kind === "string") {
    const value = resolvedValue.value.trim().toLowerCase();
    return value !== "none" && value !== "transparent";
  }
  if (resolvedValue.kind === "bool") {
    return false;
  }
  // Unresolvable expression: assume it paints rather than silently dropping geometry.
  return true;
}

// ---------------------------------------------------------------------------
// SVG path data -> absolute M / L / C / Z
// ---------------------------------------------------------------------------

function readNumber(text, i) {
  const re = /^[+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?/;
  const match = re.exec(text.slice(i));
  if (!match) {
    return null;
  }
  const value = Number(match[0]);
  if (!Number.isFinite(value)) {
    return null;
  }
  return { value, end: i + match[0].length };
}

function vectorAngle(ux, uy, vx, vy) {
  const dot = ux * vx + uy * vy;
  const len = Math.sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy));
  if (len === 0) {
    return 0;
  }
  let angle = Math.acos(Math.min(1, Math.max(-1, dot / len)));
  if (ux * vy - uy * vx < 0) {
    angle = -angle;
  }
  return angle;
}

/** Converts an SVG elliptical arc into one or more absolute cubic segments. */
function arcToCubics(x1, y1, rx, ry, phiDeg, largeArc, sweep, x2, y2) {
  if (x1 === x2 && y1 === y2) {
    return [];
  }
  rx = Math.abs(rx);
  ry = Math.abs(ry);
  if (rx === 0 || ry === 0) {
    return [{ kind: "L", pts: [x2, y2] }];
  }
  const phi = (phiDeg * Math.PI) / 180;
  const cosPhi = Math.cos(phi);
  const sinPhi = Math.sin(phi);
  const dx = (x1 - x2) / 2;
  const dy = (y1 - y2) / 2;
  const x1p = cosPhi * dx + sinPhi * dy;
  const y1p = -sinPhi * dx + cosPhi * dy;

  const lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry);
  if (lambda > 1) {
    const scale = Math.sqrt(lambda);
    rx *= scale;
    ry *= scale;
  }

  const numerator = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p;
  const denominator = rx * rx * y1p * y1p + ry * ry * x1p * x1p;
  let coefficient = Math.sqrt(Math.max(0, numerator / denominator));
  if (largeArc === sweep) {
    coefficient = -coefficient;
  }
  const cxp = (coefficient * (rx * y1p)) / ry;
  const cyp = (coefficient * (-ry * x1p)) / rx;
  const cx = cosPhi * cxp - sinPhi * cyp + (x1 + x2) / 2;
  const cy = sinPhi * cxp + cosPhi * cyp + (y1 + y2) / 2;

  const theta1 = vectorAngle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry);
  let delta = vectorAngle(
    (x1p - cxp) / rx,
    (y1p - cyp) / ry,
    (-x1p - cxp) / rx,
    (-y1p - cyp) / ry,
  );
  if (!sweep && delta > 0) {
    delta -= 2 * Math.PI;
  }
  if (sweep && delta < 0) {
    delta += 2 * Math.PI;
  }

  const segments = Math.max(1, Math.ceil(Math.abs(delta) / (Math.PI / 2)));
  const step = delta / segments;
  const k = (4 / 3) * Math.tan(step / 4);

  const out = [];
  let theta = theta1;
  let px = x1;
  let py = y1;
  for (let segment = 0; segment < segments; segment += 1) {
    const next = theta + step;
    const cosT1 = Math.cos(theta);
    const sinT1 = Math.sin(theta);
    const cosT2 = Math.cos(next);
    const sinT2 = Math.sin(next);
    const endX = cosPhi * rx * cosT2 - sinPhi * ry * sinT2 + cx;
    const endY = sinPhi * rx * cosT2 + cosPhi * ry * sinT2 + cy;
    const d1x = k * (-cosPhi * rx * sinT1 - sinPhi * ry * cosT1);
    const d1y = k * (-sinPhi * rx * sinT1 + cosPhi * ry * cosT1);
    const d2x = k * (cosPhi * rx * sinT2 + sinPhi * ry * cosT2);
    const d2y = k * (sinPhi * rx * sinT2 - cosPhi * ry * cosT2);
    out.push({
      kind: "C",
      pts: [px + d1x, py + d1y, endX + d2x, endY + d2y, endX, endY],
    });
    theta = next;
    px = endX;
    py = endY;
  }
  const last = out[out.length - 1];
  last.pts[4] = x2;
  last.pts[5] = y2;
  return out;
}

/** Parses SVG path data of any command set into absolute M/L/C/Z commands. */
function parsePathData(d) {
  const out = [];
  let i = 0;
  let command = null;
  let cx = 0;
  let cy = 0;
  let sx = 0;
  let sy = 0;
  let prevKind = null;
  let prevCtrlX = null;
  let prevCtrlY = null;

  const skipSeparators = () => {
    while (i < d.length && (d[i] === "," || isSpace(d[i]))) {
      i += 1;
    }
  };
  const readNum = () => {
    skipSeparators();
    const result = readNumber(d, i);
    if (!result) {
      return null;
    }
    i = result.end;
    return result.value;
  };
  const readFlag = () => {
    skipSeparators();
    if (d[i] === "0" || d[i] === "1") {
      const value = Number(d[i]);
      i += 1;
      return value;
    }
    return readNum();
  };

  let guard = 0;
  while (i < d.length && guard < 100000) {
    guard += 1;
    skipSeparators();
    if (i >= d.length) {
      break;
    }
    const ch = d[i];
    if (/[A-Za-z]/.test(ch)) {
      command = ch;
      i += 1;
    }
    if (!command) {
      break;
    }
    const upper = command.toUpperCase();
    const relative = command !== upper;

    if (upper === "Z") {
      out.push({ kind: "Z", pts: [] });
      cx = sx;
      cy = sy;
      prevKind = "Z";
      prevCtrlX = null;
      prevCtrlY = null;
      command = null;
      continue;
    }

    if (upper === "M" || upper === "L") {
      const x = readNum();
      const y = readNum();
      if (x === null || y === null) {
        command = null;
        continue;
      }
      const ax = relative ? cx + x : x;
      const ay = relative ? cy + y : y;
      if (upper === "M") {
        out.push({ kind: "M", pts: [ax, ay] });
        sx = ax;
        sy = ay;
        command = relative ? "l" : "L";
      } else {
        out.push({ kind: "L", pts: [ax, ay] });
      }
      cx = ax;
      cy = ay;
      prevKind = upper;
      prevCtrlX = null;
      prevCtrlY = null;
      continue;
    }

    if (upper === "H" || upper === "V") {
      const value = readNum();
      if (value === null) {
        command = null;
        continue;
      }
      const ax = upper === "H" ? (relative ? cx + value : value) : cx;
      const ay = upper === "V" ? (relative ? cy + value : value) : cy;
      out.push({ kind: "L", pts: [ax, ay] });
      cx = ax;
      cy = ay;
      prevKind = "L";
      prevCtrlX = null;
      prevCtrlY = null;
      continue;
    }

    if (upper === "C" || upper === "S") {
      const count = upper === "C" ? 6 : 4;
      const values = [];
      for (let n = 0; n < count; n += 1) {
        const value = readNum();
        if (value === null) {
          values.length = 0;
          break;
        }
        values.push(value);
      }
      if (values.length !== count) {
        command = null;
        continue;
      }
      let x1;
      let y1;
      let x2;
      let y2;
      let x;
      let y;
      if (upper === "C") {
        [x1, y1, x2, y2, x, y] = values;
        if (relative) {
          x1 += cx;
          y1 += cy;
          x2 += cx;
          y2 += cy;
          x += cx;
          y += cy;
        }
      } else {
        [x2, y2, x, y] = values;
        if (relative) {
          x2 += cx;
          y2 += cy;
          x += cx;
          y += cy;
        }
        const smooth = prevKind === "C" || prevKind === "S";
        x1 = smooth ? 2 * cx - prevCtrlX : cx;
        y1 = smooth ? 2 * cy - prevCtrlY : cy;
      }
      out.push({ kind: "C", pts: [x1, y1, x2, y2, x, y] });
      cx = x;
      cy = y;
      prevKind = upper;
      prevCtrlX = x2;
      prevCtrlY = y2;
      continue;
    }

    if (upper === "Q" || upper === "T") {
      const count = upper === "Q" ? 4 : 2;
      const values = [];
      for (let n = 0; n < count; n += 1) {
        const value = readNum();
        if (value === null) {
          values.length = 0;
          break;
        }
        values.push(value);
      }
      if (values.length !== count) {
        command = null;
        continue;
      }
      let qx;
      let qy;
      let x;
      let y;
      if (upper === "Q") {
        [qx, qy, x, y] = values;
        if (relative) {
          qx += cx;
          qy += cy;
          x += cx;
          y += cy;
        }
      } else {
        [x, y] = values;
        if (relative) {
          x += cx;
          y += cy;
        }
        const smooth = prevKind === "Q" || prevKind === "T";
        qx = smooth ? 2 * cx - prevCtrlX : cx;
        qy = smooth ? 2 * cy - prevCtrlY : cy;
      }
      const c1x = cx + (2 / 3) * (qx - cx);
      const c1y = cy + (2 / 3) * (qy - cy);
      const c2x = x + (2 / 3) * (qx - x);
      const c2y = y + (2 / 3) * (qy - y);
      out.push({ kind: "C", pts: [c1x, c1y, c2x, c2y, x, y] });
      cx = x;
      cy = y;
      prevKind = upper;
      prevCtrlX = qx;
      prevCtrlY = qy;
      continue;
    }

    if (upper === "A") {
      const rx = readNum();
      const ry = readNum();
      const rotation = readNum();
      const largeArc = readFlag();
      const sweep = readFlag();
      const x = readNum();
      const y = readNum();
      if ([rx, ry, rotation, largeArc, sweep, x, y].some((value) => value === null)) {
        command = null;
        continue;
      }
      const ax = relative ? cx + x : x;
      const ay = relative ? cy + y : y;
      for (const segment of arcToCubics(cx, cy, rx, ry, rotation, largeArc, sweep, ax, ay)) {
        out.push(segment);
      }
      cx = ax;
      cy = ay;
      prevKind = "A";
      prevCtrlX = null;
      prevCtrlY = null;
      continue;
    }

    // Unknown command: skip it and its parameters.
    command = null;
  }

  return out;
}

// ---------------------------------------------------------------------------
// Shape primitives -> path data
// ---------------------------------------------------------------------------

function ellipseCommands(cx, cy, rx, ry) {
  const segments = arcToCubics(cx - rx, cy, rx, ry, 0, 0, 1, cx, cy - ry).concat(
    arcToCubics(cx, cy - ry, rx, ry, 0, 0, 1, cx + rx, cy),
    arcToCubics(cx + rx, cy, rx, ry, 0, 0, 1, cx, cy + ry),
    arcToCubics(cx, cy + ry, rx, ry, 0, 0, 1, cx - rx, cy),
  );
  return [{ kind: "M", pts: [cx - rx, cy] }, ...segments, { kind: "Z", pts: [] }];
}

function roundedRectCommands(x, y, width, height, rx, ry) {
  let radiusX = rx;
  let radiusY = ry;
  if (radiusX === 0 && radiusY === 0) {
    return [
      { kind: "M", pts: [x, y] },
      { kind: "L", pts: [x + width, y] },
      { kind: "L", pts: [x + width, y + height] },
      { kind: "L", pts: [x, y + height] },
      { kind: "Z", pts: [] },
    ];
  }
  radiusX = Math.min(Math.abs(radiusX), width / 2);
  radiusY = Math.min(Math.abs(radiusY), height / 2);
  const commands = [{ kind: "M", pts: [x + radiusX, y] }];
  commands.push({ kind: "L", pts: [x + width - radiusX, y] });
  commands.push(...arcToCubics(x + width - radiusX, y, radiusX, radiusY, 0, 0, 1, x + width, y + radiusY));
  commands.push({ kind: "L", pts: [x + width, y + height - radiusY] });
  commands.push(
    ...arcToCubics(x + width, y + height - radiusY, radiusX, radiusY, 0, 0, 1, x + width - radiusX, y + height),
  );
  commands.push({ kind: "L", pts: [x + radiusX, y + height] });
  commands.push(...arcToCubics(x + radiusX, y + height, radiusX, radiusY, 0, 0, 1, x, y + height - radiusY));
  commands.push({ kind: "L", pts: [x, y + radiusY] });
  commands.push(...arcToCubics(x, y + radiusY, radiusX, radiusY, 0, 0, 1, x + radiusX, y));
  commands.push({ kind: "Z", pts: [] });
  return commands;
}

function pointsToCommands(pointsText, close) {
  const numbers = [];
  const re = /[+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?/g;
  let match = re.exec(pointsText);
  while (match) {
    numbers.push(Number(match[0]));
    match = re.exec(pointsText);
  }
  if (numbers.length < 4) {
    return null;
  }
  const commands = [];
  for (let i = 0; i + 1 < numbers.length; i += 2) {
    commands.push({ kind: i === 0 ? "M" : "L", pts: [numbers[i], numbers[i + 1]] });
  }
  if (close) {
    commands.push({ kind: "Z", pts: [] });
  }
  return commands;
}

// ---------------------------------------------------------------------------
// JSX walking
// ---------------------------------------------------------------------------

const SHAPE_TAGS = new Set(["path", "rect", "circle", "ellipse", "line", "polyline", "polygon"]);
const SKIP_TAGS = new Set([
  "defs",
  "clippath",
  "mask",
  "symbol",
  "title",
  "desc",
  "style",
  "script",
  "filter",
  "marker",
  "pattern",
  "lineargradient",
  "radialgradient",
  "stop",
  "metadata",
  "font",
  "foreignobject",
]);
const IGNORED_PAINT_TAGS = new Set(["use", "image"]);

const INHERITED_ATTRIBUTES = new Set([
  "fill",
  "stroke",
  "strokewidth",
  "strokelinecap",
  "strokelinejoin",
  "opacity",
  "fillopacity",
  "strokeopacity",
]);

function normalizeAttrName(name) {
  return name.replace(/-/g, "").toLowerCase();
}

/** Parses attributes of one JSX element. Returns { attrs, close, end }. */
function parseAttributes(text, i) {
  const attrs = [];
  while (i < text.length) {
    i = skipSpace(text, i);
    if (text[i] === "/" && text[i + 1] === ">") {
      return { attrs, close: "self", end: i + 2 };
    }
    if (text[i] === ">") {
      return { attrs, close: "open", end: i + 1 };
    }
    if (i >= text.length) {
      break;
    }
    if (text[i] === "{" && text.slice(i + 1, i + 4) === "...") {
      const end = readBalanced(text, i);
      attrs.push({ name: `...${text.slice(i + 4, end - 1).trim()}`, value: { expr: "spread" } });
      i = end;
      continue;
    }
    if (isNameStart(text[i])) {
      let start = i;
      while (i < text.length && (isNameChar(text[i]) || text[i] === "-" || text[i] === ":")) {
        i += 1;
      }
      const name = text.slice(start, i);
      i = skipSpace(text, i);
      if (text[i] !== "=") {
        attrs.push({ name, value: { expr: "true" } });
        continue;
      }
      i += 1;
      i = skipSpace(text, i);
      if (text[i] === '"' || text[i] === "'") {
        const str = readString(text, i);
        if (!str) {
          break;
        }
        attrs.push({ name, value: { quoted: str.value } });
        i = str.end;
        continue;
      }
      if (text[i] === "{") {
        const end = readBalanced(text, i);
        attrs.push({ name, value: { expr: text.slice(i + 1, end - 1).trim() } });
        i = end;
        continue;
      }
      // Unexpected bare value.
      start = i;
      while (i < text.length && !isSpace(text[i]) && text[i] !== ">" && text[i] !== "/") {
        i += 1;
      }
      attrs.push({ name, value: { quoted: text.slice(start, i) } });
      continue;
    }
    i += 1;
  }
  return { attrs, close: "eof", end: i };
}

/** Parses a transform list into a 2D affine matrix [a, b, c, d, e, f]. */
function parseTransform(text) {
  const identity = [1, 0, 0, 1, 0, 0];
  if (!text) {
    return { matrix: identity, ok: true };
  }
  let matrix = identity;
  const re = /([A-Za-z]+)\s*\(([^)]*)\)/g;
  let match = re.exec(text);
  let consumed = 0;
  while (match) {
    consumed += match[0].length;
    const name = match[1];
    const args = match[2]
      .split(/[\s,]+/)
      .map((value) => value.trim())
      .filter((value) => value.length > 0)
      .map((value) => Number(value));
    if (args.some((value) => !Number.isFinite(value))) {
      return { matrix: identity, ok: false };
    }
    let next;
    if (name === "translate") {
      next = [1, 0, 0, 1, args[0] ?? 0, args[1] ?? 0];
    } else if (name === "scale") {
      const sx = args[0] ?? 1;
      const sy = args[1] ?? sx;
      next = [sx, 0, 0, sy, 0, 0];
    } else if (name === "rotate") {
      const radians = ((args[0] ?? 0) * Math.PI) / 180;
      const cos = Math.cos(radians);
      const sin = Math.sin(radians);
      const cx = args[1] ?? 0;
      const cy = args[2] ?? 0;
      const rotation = [cos, sin, -sin, cos, 0, 0];
      const toOrigin = [1, 0, 0, 1, -cx, -cy];
      const back = [1, 0, 0, 1, cx, cy];
      // rotate(a cx cy) == translate(cx cy) * rotate(a) * translate(-cx -cy)
      next = multiplyMatrices(back, multiplyMatrices(rotation, toOrigin));
    } else if (name === "matrix") {
      if (args.length !== 6) {
        return { matrix: identity, ok: false };
      }
      next = args;
    } else {
      return { matrix: identity, ok: false };
    }
    matrix = multiplyMatrices(matrix, next);
    match = re.exec(text);
  }
  const stripped = text.replace(/[A-Za-z]+\s*\(([^)]*)\)/g, "").trim();
  if (stripped.length > 0 || consumed === 0) {
    return { matrix: identity, ok: false };
  }
  return { matrix, ok: true };
}

/** Returns m1 * m2 (m2 applied to points first). */
function multiplyMatrices(m1, m2) {
  return [
    m1[0] * m2[0] + m1[2] * m2[1],
    m1[1] * m2[0] + m1[3] * m2[1],
    m1[0] * m2[2] + m1[2] * m2[3],
    m1[1] * m2[2] + m1[3] * m2[3],
    m1[0] * m2[4] + m1[2] * m2[5] + m1[4],
    m1[1] * m2[4] + m1[3] * m2[5] + m1[5],
  ];
}

function applyMatrix(matrix, x, y) {
  return [matrix[0] * x + matrix[2] * y + matrix[4], matrix[1] * x + matrix[3] * y + matrix[5]];
}

function isIdentityMatrix(matrix) {
  return matrix.every((value, index) => value === [1, 0, 0, 1, 0, 0][index]);
}

/**
 * Walks JSX children and collects shapes.
 * ctx: { attrs: Record<string, resolved>, matrix, viewBox: {width, height} }
 * When `silent` is true, elements are walked but nothing is emitted (used for
 * <defs>, <mask>, <clipPath> and other non-painted subtrees).
 */
function walkChildren(text, i, endTag, ctx, state, silent = false) {
  while (i < text.length) {
    const ch = text[i];
    if (ch === "<") {
      if (text[i + 1] === "/") {
        const close = text.indexOf(">", i);
        if (close < 0) {
          return text.length;
        }
        return close + 1;
      }
      const open = parseElement(text, i, ctx, state, silent);
      if (open === null) {
        i += 1;
        continue;
      }
      i = open.end;
      continue;
    }
    if (ch === "{") {
      const end = readBalanced(text, i);
      if (!silent) {
        handleExpression(text.slice(i + 1, end - 1), ctx, state);
      }
      i = end;
      continue;
    }
    i += 1;
  }
  return i;
}

function parseElement(text, i, ctx, state, silent) {
  let cursor = i + 1;
  if (text[cursor] === ">") {
    // Fragment open: <> ... </>
    return { end: walkChildren(text, cursor + 1, "", ctx, state, silent) };
  }
  if (!isNameStart(text[cursor])) {
    return null;
  }
  let start = cursor;
  while (cursor < text.length && (isNameChar(text[cursor]) || text[cursor] === "-")) {
    cursor += 1;
  }
  const tag = text.slice(start, cursor);
  const { attrs, close, end } = parseAttributes(text, cursor);
  const tagKey = tag.toLowerCase();

  if (close === "self") {
    if (!silent) {
      handleElement(tagKey, attrs, ctx, state);
    }
    return { end };
  }
  if (close !== "open") {
    return { end };
  }

  if (SKIP_TAGS.has(tagKey) || IGNORED_PAINT_TAGS.has(tagKey)) {
    return { end: walkChildren(text, end, tagKey, ctx, state, true) };
  }

  const childCtx = contextForElement(attrs, ctx, state);
  const childEnd = walkChildren(text, end, tagKey, childCtx, state, silent);
  if (!silent) {
    handleElement(tagKey, attrs, ctx, state);
  }
  return { end: childEnd };
}

/** Applies the entries of an object literal (used for `{...spread}` attributes). */
function applyObjectEntries(text, target, state) {
  const entries = parseObjectEntries(text);
  if (!entries) {
    return;
  }
  for (const entry of entries) {
    if (entry.spread) {
      const spreadDef = state.defs.get(entry.spread);
      if (spreadDef && spreadDef.rhs.trim().startsWith("{")) {
        applyObjectEntries(spreadDef.rhs, target, state);
      }
      continue;
    }
    target[normalizeAttrName(entry.key)] = resolveValue({ expr: entry.valueText }, state.defs, state.bindings);
  }
}

/** Builds the attribute context for an element's children. */
function contextForElement(attrs, ctx, state) {
  const own = {};
  for (const attr of attrs) {
    if (attr.name.startsWith("...")) {
      const name = attr.name.slice(3).trim();
      const def = state.defs.get(name);
      if (def && def.rhs.trim().startsWith("{")) {
        applyObjectEntries(def.rhs, own, state);
      } else {
        state.warnings.push(`could not resolve the spread attribute {...${name}}`);
      }
      continue;
    }
    own[normalizeAttrName(attr.name)] = resolveValue(attr.value, state.defs, state.bindings);
  }

  const merged = { ...ctx.attrs };
  for (const key of INHERITED_ATTRIBUTES) {
    if (own[key] !== undefined) {
      merged[key] = own[key];
    }
  }

  for (const [key, message] of [
    ["mask", "a mask attribute is ignored, so masked geometry is drawn unmasked"],
    ["clippath", "a clipPath attribute is ignored, so clipping is not applied"],
  ]) {
    const value = own[key];
    if (!value || (value.kind === "string" && value.value.trim().toLowerCase() === "none")) {
      continue;
    }
    if (!state.warnings.includes(message)) {
      state.warnings.push(message);
    }
  }

  let matrix = ctx.matrix;
  const transformRaw = own.transform;
  if (transformRaw && transformRaw.kind !== "missing") {
    let transformText =
      transformRaw.kind === "string" ? transformRaw.value : transformRaw.value ?? "";
    // `flip ? "A" : "B"` (arrowhead previews): take the default (flip = false) branch.
    const ternary = /^\s*[A-Za-z_$][\w$]*\s*\?\s*(?:"[^"]*"|'[^']*')\s*:\s*("[^"]*"|'[^']*')\s*$/.exec(transformText);
    if (ternary) {
      transformText = ternary[1].slice(1, -1);
    }
    const parsed = parseTransform(transformText);
    if (!parsed.ok) {
      state.warnings.push(`transform "${transformText}" is not supported; affected shapes were skipped`);
      matrix = null;
    } else {
      matrix = multiplyMatrices(ctx.matrix ?? [1, 0, 0, 1, 0, 0], parsed.matrix);
    }
  }

  return { attrs: merged, matrix, viewBox: ctx.viewBox };
}

function handleElement(tagKey, attrs, ctx, state) {
  if (SKIP_TAGS.has(tagKey) || IGNORED_PAINT_TAGS.has(tagKey)) {
    return;
  }
  if (tagKey === "text") {
    state.warnings.push("a <text> element inside an icon cannot be represented as path data");
    return;
  }
  if (!SHAPE_TAGS.has(tagKey)) {
    return;
  }
  const elementCtx = contextForElement(attrs, ctx, state);
  if (elementCtx.matrix === null) {
    return;
  }
  emitShape(tagKey, attrs, elementCtx, state);
}

function attributeText(attrs, name, state) {
  const normalized = normalizeAttrName(name);
  for (const attr of attrs) {
    if (normalizeAttrName(attr.name) === normalized) {
      return resolveValue(attr.value, state.defs, state.bindings);
    }
  }
  return null;
}

function emitShape(tagKey, attrs, ctx, state) {
  const defs = state.defs;
  const geometryNumber = (name, fallback = 0) =>
    toNumber(attributeText(attrs, name, state), fallback);

  let commands = null;
  if (tagKey === "path") {
    const d = attributeText(attrs, "d", state);
    if (!d || d.kind === "missing") {
      return;
    }
    const dText = d.kind === "string" ? d.value : d.kind === "unknown" ? null : String(d.value);
    if (dText === null) {
      state.warnings.push("path with a non-literal `d` attribute was skipped");
      return;
    }
    commands = parsePathData(dText);
  } else if (tagKey === "rect") {
    const width = geometryNumber("width");
    const height = geometryNumber("height");
    if (width <= 0 || height <= 0) {
      state.warnings.push("rect without a positive width/height was skipped");
      return;
    }
    let rx = toNumber(attributeText(attrs, "rx", state), null);
    let ry = toNumber(attributeText(attrs, "ry", state), null);
    if (rx === null && ry === null) {
      rx = 0;
      ry = 0;
    } else if (rx === null) {
      rx = ry;
    } else if (ry === null) {
      ry = rx;
    }
    commands = roundedRectCommands(geometryNumber("x"), geometryNumber("y"), width, height, rx, ry);
  } else if (tagKey === "circle") {
    const r = geometryNumber("r");
    if (r <= 0) {
      state.warnings.push("circle without a positive radius was skipped");
      return;
    }
    commands = ellipseCommands(geometryNumber("cx"), geometryNumber("cy"), r, r);
  } else if (tagKey === "ellipse") {
    const rx = geometryNumber("rx");
    const ry = geometryNumber("ry");
    if (rx <= 0 || ry <= 0) {
      state.warnings.push("ellipse without positive radii was skipped");
      return;
    }
    commands = ellipseCommands(geometryNumber("cx"), geometryNumber("cy"), rx, ry);
  } else if (tagKey === "line") {
    commands = [
      { kind: "M", pts: [geometryNumber("x1"), geometryNumber("y1")] },
      { kind: "L", pts: [geometryNumber("x2"), geometryNumber("y2")] },
    ];
  } else if (tagKey === "polyline" || tagKey === "polygon") {
    const points = attributeText(attrs, "points", state);
    const pointsText = points && points.kind === "string" ? points.value : null;
    if (pointsText === null) {
      state.warnings.push(`${tagKey} with a non-literal points attribute was skipped`);
      return;
    }
    commands = pointsToCommands(pointsText, tagKey === "polygon");
    if (!commands) {
      state.warnings.push(`${tagKey} with fewer than two points was skipped`);
      return;
    }
  }

  if (!commands || commands.length === 0) {
    return;
  }

  // Paint resolution: this element's own attributes on top of the inherited ones.
  const own = {};
  for (const attr of attrs) {
    if (!attr.name.startsWith("...")) {
      own[normalizeAttrName(attr.name)] = resolveValue(attr.value, defs, state.bindings);
    }
  }
  const fillValue = own.fill ?? ctx.attrs.fill;
  const strokeValue = own.stroke ?? ctx.attrs.stroke;
  const strokeWidthValue = own.strokewidth ?? ctx.attrs.strokewidth;
  const filled = isPaintVisible(fillValue, true);
  const strokeVisible = isPaintVisible(strokeValue, false);
  const strokeWidth = strokeWidthValue ? toNumber(strokeWidthValue, null) : null;
  const stroked = strokeVisible && (strokeWidth ?? DEFAULT_STROKE_WIDTH) > 0;

  if (!filled && !stroked) {
    // Stroke and fill are both `none`: the element paints nothing (for example the
    // invisible 24x24 bounding box path tabler ships with most icons).
    return;
  }

  const matrix = fitMatrix(ctx.matrix, ctx.viewBox);
  const d = commandsToPathData(commands, matrix);
  if (d === null) {
    state.warnings.push(`${tagKey} produced no usable geometry`);
    return;
  }

  const determinant = matrix[0] * matrix[3] - matrix[1] * matrix[2];
  const scaleFactor = Math.sqrt(Math.abs(determinant));

  if (filled) {
    // handlerColor(theme) is the editor background (white / #1e1e1e): a knockout fill.
    const knockout = fillValue.kind === "string" && fillValue.value === "var(--handler-color)";
    state.shapes.push(
      knockout ? { d, filled: true, strokeWidth: 0, knockout: true } : { d, filled: true, strokeWidth: 0 },
    );
  }
  if (stroked) {
    const width = strokeWidth === null ? DEFAULT_STROKE_WIDTH : strokeWidth * scaleFactor;
    state.shapes.push({ d, filled: false, strokeWidth: round(width) });
  }
}

function round(value) {
  const rounded = Math.round(value * 1000) / 1000;
  return Object.is(rounded, -0) ? 0 : rounded;
}

function formatNumber(value) {
  const rounded = round(value);
  if (Number.isInteger(rounded)) {
    return String(rounded);
  }
  return String(rounded);
}

function commandsToPathData(commands, matrix) {
  const parts = [];
  for (const command of commands) {
    if (command.kind === "Z") {
      parts.push("Z");
      continue;
    }
    const points = [];
    for (let i = 0; i + 1 < command.pts.length; i += 2) {
      const [x, y] = applyMatrix(matrix, command.pts[i], command.pts[i + 1]);
      points.push(`${formatNumber(x)} ${formatNumber(y)}`);
    }
    parts.push(`${command.kind}${points.join(" ")}`);
  }
  const d = parts.join("");
  return d.includes("M") ? d : null;
}

/** Handles `{ ... }` inside JSX: comments, conditionals, and `.map` over string arrays. */
function handleExpression(expr, ctx, state) {
  const trimmed = expr.trim();
  if (trimmed.length === 0 || trimmed.startsWith("/*")) {
    return;
  }
  const mapMatch = /^([A-Za-z_$][\w$]*)\s*\.map\s*\(\s*\(?\s*([A-Za-z_$][\w$]*)?/.exec(trimmed);
  if (mapMatch) {
    const arrayName = mapMatch[1];
    const parameter = mapMatch[2];
    const arrayDef = state.defs.get(arrayName);
    const values = arrayDef ? parseStringArray(arrayDef.rhs) : null;
    const elementStart = trimmed.indexOf("<");
    if (!arrayDef || values === null || elementStart < 0 || !parameter) {
      state.warnings.push(`could not expand ${arrayName}.map(...)`);
      return;
    }
    const previous = state.bindings.get(parameter);
    for (const value of values) {
      state.bindings.set(parameter, value);
      // Walk from the element that `.map` returns, ignoring the surrounding JS.
      walkChildren(trimmed, elementStart, null, ctx, state);
    }
    if (previous === undefined) {
      state.bindings.delete(parameter);
    } else {
      state.bindings.set(parameter, previous);
    }
    return;
  }
  if (trimmed.includes("<")) {
    // Conditional JSX such as `{cond && <path ... />}` or a ternary: walk the JSX inside.
    walkChildren(trimmed, trimmed.indexOf("<"), null, ctx, state);
  }
}

function parseStringArray(rhsText) {
  const text = rhsText.trim();
  const open = text.indexOf("[");
  if (open < 0) {
    return null;
  }
  const close = readBalanced(text, open);
  const inner = text.slice(open + 1, close - 1);
  const values = [];
  for (const part of splitTopLevel(inner)) {
    const str = readString(part, 0);
    if (str && str.end === part.length) {
      values.push(str.value);
    } else {
      return null;
    }
  }
  return values;
}

// ---------------------------------------------------------------------------
// Icon resolution
// ---------------------------------------------------------------------------

function createResolver(defs) {
  const resolvedCache = new Map();

  function defFor(name) {
    return defs.get(name) ?? null;
  }

  function sourceFor(name, seen = new Set()) {
    if (seen.has(name)) {
      return null;
    }
    seen.add(name);
    const def = defFor(name);
    if (!def) {
      return null;
    }
    const text = def.rhs.trim();
    if (/^[A-Za-z_$][\w$]*$/.test(text)) {
      return sourceFor(text, seen);
    }
    const callOpen = findCallOpen(text, "createIcon");
    if (callOpen >= 0) {
      const callEnd = readBalanced(text, callOpen);
      const args = splitTopLevel(text.slice(callOpen + 1, callEnd - 1));
      return {
        arg0: args[0] ?? null,
        arg1: args[1] ?? null,
      };
    }
    if (text.startsWith("<") || (text.startsWith("(") && text.slice(1).trimStart().startsWith("<"))) {
      return { arg0: text.slice(text.indexOf("<")), arg1: null };
    }
    if (/^["'`]/.test(text)) {
      return { arg0: text, arg1: null };
    }
    return null;
  }

  function resolveSource(arg0, seen = new Set()) {
    if (arg0 === null || arg0 === undefined) {
      return null;
    }
    const text = arg0.trim();
    if (text.startsWith("<") || text.startsWith("(") || text.startsWith("[")) {
      return { kind: "jsx", jsx: text.slice(text.indexOf("<") >= 0 ? text.indexOf("<") : 0) };
    }
    if (/^["'`]/.test(text)) {
      const str = readString(text, 0);
      if (str) {
        return { kind: "d", d: str.value };
      }
      return null;
    }
    if (/^[A-Za-z_$][\w$]*$/.test(text)) {
      if (seen.has(text)) {
        return null;
      }
      seen.add(text);
      const def = defFor(text);
      if (!def) {
        return null;
      }
      const defText = def.rhs.trim();
      if (/^[A-Za-z_$][\w$]*$/.test(defText)) {
        return resolveSource(defText, seen);
      }
      if (defText.startsWith("<") || defText.startsWith("(")) {
        return { kind: "jsx", jsx: defText.slice(defText.indexOf("<") >= 0 ? defText.indexOf("<") : 0) };
      }
      if (/^["'`]/.test(defText)) {
        const str = readString(defText, 0);
        return str ? { kind: "d", d: str.value } : null;
      }
    }
    return null;
  }

  /** Resolves a createIcon options argument into viewBox + inherited attributes. */
  function resolveOptions(arg1) {
    const result = {
      width: BOX,
      height: BOX,
      attrs: { fill: { kind: "string", value: "black" } },
    };
    if (!arg1) {
      return result;
    }
    const text = arg1.trim();
    if (/^[0-9.]+$/.test(text)) {
      const size = Number(text);
      result.width = size;
      result.height = size;
      return result;
    }
    let entries = null;
    if (text.startsWith("{")) {
      entries = parseObjectEntries(text);
    } else if (/^[A-Za-z_$][\w$]*$/.test(text)) {
      const def = defFor(text);
      if (def && def.rhs.trim().startsWith("{")) {
        entries = parseObjectEntries(def.rhs);
      }
    }
    if (!entries) {
      return result;
    }
    let explicitHeight = false;
    const applyEntry = (entry) => {
      if (entry.spread) {
        const spreadDef = defFor(entry.spread);
        if (spreadDef && spreadDef.rhs.trim().startsWith("{")) {
          const spreadEntries = parseObjectEntries(spreadDef.rhs);
          if (spreadEntries) {
            spreadEntries.forEach(applyEntry);
          }
        }
        return;
      }
      const key = normalizeAttrName(entry.key);
      const value = resolveValue({ expr: entry.valueText }, defs);
      if (key === "width") {
        const width = toNumber(value, null);
        if (width !== null) {
          result.width = width;
        }
        return;
      }
      if (key === "height") {
        const height = toNumber(value, null);
        if (height !== null) {
          result.height = height;
          explicitHeight = true;
        }
        return;
      }
      if (key === "style" && /rotate\(\s*180deg\s*\)/.test(entry.valueText)) {
        result.rotate180 = true;
        return;
      }
      if (key === "mirror" || key === "style" || key === "classname") {
        return;
      }
      if (INHERITED_ATTRIBUTES.has(key)) {
        result.attrs[key] = value;
      }
    };
    entries.forEach(applyEntry);
    if (!explicitHeight) {
      // createIcon: height defaults to width.
      result.height = result.width;
    }
    return result;
  }

  function iconShapes(name) {
    if (resolvedCache.has(name)) {
      return resolvedCache.get(name);
    }
    const shapes = [];
    const warnings = [];
    const source = sourceFor(name);
    if (!source) {
      const result = { shapes, warnings: [`no createIcon(...) definition found for ${name}`] };
      resolvedCache.set(name, result);
      return result;
    }
    const resolved = resolveSource(source.arg0);
    const options = resolveOptions(source.arg1);
    const state = { shapes, warnings, defs, bindings: new Map() };

    if (!resolved) {
      warnings.push(`could not resolve the JSX for ${name}`);
      const result = { shapes, warnings };
      resolvedCache.set(name, result);
      return result;
    }

    if (resolved.kind === "d") {
      // createIcon("M...", opts) renders a single filled <path fill="currentColor">.
      const d = commandsToPathData(parsePathData(resolved.d), fitMatrix([1, 0, 0, 1, 0, 0], options));
      if (d === null) {
        warnings.push("the string path data could not be converted");
      } else {
        shapes.push({ d, filled: true, strokeWidth: 0 });
      }
      const result = { shapes, warnings };
      resolvedCache.set(name, result);
      return result;
    }

    const ctx = { attrs: options.attrs, matrix: [1, 0, 0, 1, 0, 0], viewBox: { width: options.width, height: options.height } };
    walkChildren(resolved.jsx, 0, null, ctx, state);
    if (options.rotate180) {
      // style={{ transform: "rotate(180deg)" }} on the <svg>: x -> 512 - x, y -> 512 - y.
      for (const shape of shapes) {
        let index = 0;
        shape.d = shape.d.replace(/-?\d*\.?\d+(?:e-?\d+)?/g, (num) => {
          index += 1;
          return String(Math.round((BOX - Number(num)) * 1000) / 1000);
        });
      }
    }

    const result = { shapes, warnings };
    resolvedCache.set(name, result);
    return result;
  }

  return { iconShapes, defFor, resolveOptions };
}

function fitMatrix(matrix, options) {
  const scale = BOX / Math.max(options.width, options.height);
  return multiplyMatrices(
    [
      scale,
      0,
      0,
      scale,
      (BOX - options.width * scale) / 2,
      (BOX - options.height * scale) / 2,
    ],
    matrix,
  );
}

// ---------------------------------------------------------------------------
// Swift generation
// ---------------------------------------------------------------------------

function swiftString(text) {
  return `"${text.replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`;
}

function swiftDouble(value) {
  if (Number.isInteger(value)) {
    return `${value}.0`;
  }
  return String(value);
}

function generateSwift(icons, commit) {
  const lines = [];
  // Path data lines are far longer than any hand-written line limit, so the whole
  // file opts out of formatting. Regenerate rather than reformat by hand.
  lines.push("// swift-format-ignore-file");
  lines.push("// Generated by scripts/port/extract-icons.mjs. Do not edit by hand.");
  lines.push("//");
  lines.push("// Source: excalidraw/packages/excalidraw/components/icons.tsx");
  lines.push("// Icons are derived from https://fontawesome.com/icons (Font Awesome license) and");
  lines.push("// tabler-icons, matching upstream attribution in the source file.");
  lines.push(`// Excalidraw commit: ${commit}`);
  lines.push("//");
  lines.push(`// Geometry is normalised into a ${BOX}x${BOX} box: every path uses only absolute`);
  lines.push("// M, L, C and Z commands, and stroke widths are already expressed in that box.");
  lines.push("");
  lines.push("/// One filled or stroked shape inside an icon, in the icon's own 512x512 coordinate space.");
  lines.push("public struct IconShape: Sendable, Equatable {");
  lines.push("  /// Absolute path data. Only uppercase, absolute M, L, C and Z commands may appear.");
  lines.push("  public let d: String");
  lines.push("  /// true means fill with the current colour; false means stroke with it.");
  lines.push("  public let filled: Bool");
  lines.push("  /// Stroke width in the 512 coordinate space. Use 0 when `filled` is true.");
  lines.push("  public let strokeWidth: Double");
  lines.push("  /// true means the fill is the editor background colour (Excalidraw's handlerColor):");
  lines.push("  /// draw it by clearing what is beneath, not with the icon colour.");
  lines.push("  public let knockout: Bool");
  lines.push("");
  lines.push("  public init(d: String, filled: Bool, strokeWidth: Double, knockout: Bool = false) {");
  lines.push("    self.d = d");
  lines.push("    self.filled = filled");
  lines.push("    self.strokeWidth = strokeWidth");
  lines.push("    self.knockout = knockout");
  lines.push("  }");
  lines.push("}");
  lines.push("");
  lines.push("public struct PortIcon: Sendable, Equatable {");
  lines.push("  public let name: String");
  lines.push("  public let shapes: [IconShape]");
  lines.push("");
  lines.push("  public init(name: String, shapes: [IconShape]) {");
  lines.push("    self.name = name");
  lines.push("    self.shapes = shapes");
  lines.push("  }");
  lines.push("}");
  lines.push("");
  lines.push("public enum PortIcons {");
  lines.push(`  /// The excalidraw repo commit the icons were extracted from, written by the script.`);
  lines.push(`  public static let repoCommit: String = ${swiftString(commit)}`);
  lines.push("");
  lines.push("  /// Icon name (lowercase, e.g. \"rectangle\", \"freedraw\", \"undo\") to icon.");
  lines.push("  public static let all: [String: PortIcon] = [");
  for (const key of Object.keys(icons).sort()) {
    const icon = icons[key];
    lines.push(`    ${swiftString(key)}: PortIcon(`);
    lines.push(`      name: ${swiftString(key)},`);
    lines.push("      shapes: [");
    icon.shapes.forEach((shape, index) => {
      const comma = index === icon.shapes.length - 1 ? "" : ",";
      lines.push(
        `        IconShape(d: ${swiftString(shape.d)}, filled: ${shape.filled}, strokeWidth: ${swiftDouble(
          shape.strokeWidth,
        )}${shape.knockout ? ", knockout: true" : ""})${comma}`,
      );
    });
    lines.push("      ]");
    lines.push("    ),");
  }
  lines.push("  ]");
  lines.push("");
  lines.push("  public static func icon(_ name: String) -> PortIcon? {");
  lines.push("    all[name]");
  lines.push("  }");
  lines.push("}");
  lines.push("");
  return lines.join("\n");
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

/**
 * FillCrossHatchIcon paints a filled square through an alpha mask made of hatch strokes.
 * Masks are not supported, so draw the hatch strokes themselves (in place of the fill).
 */
function patchCrossHatch(icon, notes) {
  const hatch =
    "M2.426 15.044 15.044 2.426M7.383 20 20 7.383M0 12.617 12.617 0m-7.98 17.941L17.256 5.324m-2.211 12.25L2.426 4.956M20 12.617 7.383 0m5.234 20L0 7.383m17.941 7.98L5.324 2.745";
  const d = commandsToPathData(parsePathData(hatch), fitMatrix([1, 0, 0, 1, 0, 0], { width: 20, height: 20 }));
  const outline = icon.shapes.find((shape) => !shape.filled);
  if (d && outline) {
    icon.shapes = [outline, { d, filled: false, strokeWidth: (1.25 * BOX) / 20 }];
    notes.push("fillcrosshatch <- FillCrossHatchIcon: mask replaced by its hatch strokes drawn directly");
  }
}

function main() {
  let source;
  try {
    source = readFileSync(ICONS_PATH, "utf8");
  } catch {
    fail(`could not read ${ICONS_PATH}. Set EXCALIDRAW_REPO to your Excalidraw checkout.`);
  }

  let commit;
  try {
    commit = execFileSync("git", ["-C", REPO, "rev-parse", "HEAD"], { encoding: "utf8" }).trim();
  } catch {
    fail(`could not read the git commit of ${REPO}`);
  }

  const defs = collectDefinitions(source);
  const { iconShapes } = createResolver(defs);

  const icons = {};
  const skipped = [];
  const notes = [];

  for (const [key, candidates] of REQUESTED) {
    const component = candidates.find((candidate) => defs.has(candidate));
    if (!component) {
      skipped.push(`${key}: none of ${candidates.join(", ")} exist in icons.tsx`);
      continue;
    }
    let result;
    try {
      result = iconShapes(component);
    } catch (error) {
      skipped.push(`${key}: extracting ${component} failed (${error.message})`);
      continue;
    }
    if (result.shapes.length === 0) {
      const detail = result.warnings.length > 0 ? result.warnings.join("; ") : "no convertible shapes";
      skipped.push(`${key}: ${component} produced no shapes (${detail})`);
      continue;
    }
    icons[key] = { shapes: result.shapes };
    if (component === "FillCrossHatchIcon") {
      patchCrossHatch(icons[key], notes);
    }
    if (REUSE_NOTES[key]) {
      notes.push(`${key} <- ${component}: ${REUSE_NOTES[key]}`);
    }
    for (const warning of result.warnings) {
      notes.push(`${key} <- ${component}: ${warning}`);
    }
  }

  // Every other icon-like export, keyed by lowercased name (trailing "Icon" dropped
  // when that key is free). Existing keys above stay stable.
  const usedComponents = new Set(REQUESTED.flatMap(([, names]) => names));
  for (const [name, def] of defs) {
    if (usedComponents.has(name) || NOT_ICONS.has(name)) {
      continue;
    }
    if (!/createIcon\(|React\.memo\(|^[A-Za-z_$]+$/.test(def.rhs.slice(0, 40))) {
      continue;
    }
    const lower = name.toLowerCase();
    const stripped = lower.endsWith("icon") && lower.length > 4 ? lower.slice(0, -4) : lower;
    const key = [stripped, lower, name].find((k) => !(k in icons));
    if (key === undefined) {
      continue;
    }
    // Skip components already emitted under a requested key with identical geometry.
    let result;
    try {
      result = iconShapes(name);
    } catch (error) {
      skipped.push(`${key}: extracting ${name} failed (${error.message})`);
      continue;
    }
    if (result.shapes.length === 0) {
      skipped.push(`${key}: ${name} produced no shapes (${result.warnings.join("; ") || "no convertible shapes"})`);
      continue;
    }
    const signature = JSON.stringify(result.shapes);
    if (Object.values(icons).some((icon) => JSON.stringify(icon.shapes) === signature)) {
      continue;
    }
    icons[key] = { shapes: result.shapes };
    for (const warning of result.warnings) {
      notes.push(`${key} <- ${name}: ${warning}`);
    }
  }

  const swift = generateSwift(icons, commit);
  mkdirSync(dirname(OUT_PATH), { recursive: true });
  writeFileSync(OUT_PATH, swift, "utf8");

  const count = Object.keys(icons).length;
  console.log(`[extract-icons] source: ${ICONS_PATH}`);
  console.log(`[extract-icons] commit: ${commit}`);
  console.log(`[extract-icons] extracted ${count} of ${REQUESTED.length} requested icons`);
  const shapeCount = Object.values(icons).reduce((total, icon) => total + icon.shapes.length, 0);
  console.log(`[extract-icons] ${shapeCount} shapes written to ${OUT_PATH}`);
  if (skipped.length > 0) {
    console.log(`[extract-icons] skipped requested names (${skipped.length}):`);
    for (const reason of skipped) {
      console.log(`  - ${reason}`);
    }
  } else {
    console.log("[extract-icons] skipped requested names: none");
  }
  if (notes.length > 0) {
    console.log("[extract-icons] notes:");
    for (const note of notes) {
      console.log(`  - ${note}`);
    }
  }
}

main();
