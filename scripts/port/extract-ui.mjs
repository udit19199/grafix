#!/usr/bin/env node
// Generates Grafix's Swift UI definitions from the open-source Excalidraw repo.
// The repo is the single source of truth: tool order, shortcut keys, theme
// tokens, colour palette, and UI copy are all read from it, never retyped.
//
// Usage:
//   node scripts/port/extract-ui.mjs            # write the generated files
//   node scripts/port/extract-ui.mjs --check    # fail if they are out of date
//
// The repo location comes from EXCALIDRAW_REPO, defaulting to
// ~/Workspace/oss/excalidraw.

import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const PACKAGE_ROOT = resolve(HERE, "..", "..");
const OUT_DIR = join(PACKAGE_ROOT, "Sources", "GrafixPort", "Generated");

const REPO = resolve(
  process.env.EXCALIDRAW_REPO ?? join(homedir(), "Workspace", "oss", "excalidraw"),
);
const EDITOR = join(REPO, "packages", "excalidraw");
const COMMON = join(REPO, "packages", "common", "src");

const check = process.argv.includes("--check");

function fail(message) {
  console.error(`extract-ui: ${message}`);
  process.exit(1);
}

if (!existsSync(EDITOR)) {
  fail(
    `the Excalidraw repo is not at ${REPO}.\n` +
      `Clone it with: git clone https://github.com/excalidraw/excalidraw.git ${REPO}\n` +
      `Or point EXCALIDRAW_REPO at an existing checkout.`,
  );
}

const read = (...parts) => readFileSync(join(...parts), "utf8");

const COMMIT = execFileSync("git", ["-C", REPO, "rev-parse", "HEAD"], {
  encoding: "utf8",
}).trim();

const en = JSON.parse(read(EDITOR, "locales", "en.json"));
/** Look up a dotted key in the repo's English strings, e.g. "toolBar.lasso". */
const t = (key) => {
  const value = key
    .split(".")
    .reduce((node, part) => (node == null ? node : node[part]), en);
  return typeof value === "string" ? value : key;
};

const capitalize = (s) => (s ? s[0].toUpperCase() + s.slice(1) : s);

// ---------------------------------------------------------------------------
// Tools: packages/excalidraw/components/Tools.tsx
// ---------------------------------------------------------------------------

const toolsSource = read(EDITOR, "components", "Tools.tsx");

function sliceBlock(source, opener, closer = "}") {
  const start = source.indexOf(opener);
  if (start < 0) {
    return null;
  }
  let depth = 0;
  for (let i = start; i < source.length; i += 1) {
    const ch = source[i];
    if (ch === "{") {
      depth += 1;
    } else if (ch === "}") {
      depth -= 1;
      if (depth === 0) {
        return source.slice(start, i + 1);
      }
    }
  }
  return null;
}

/** Replaces string bodies with spaces so punctuation inside them is ignored. */
function maskStrings(source) {
  return source.replace(/(["'`])(?:\\.|(?!\1)[\s\S])*\1/g, (s) =>
    // Keep the quotes so the result still has the same shape.
    s[0] + " ".repeat(Math.max(0, s.length - 2)) + s[s.length - 1],
  );
}

/** Index of the bracket that closes the one at `open`, or -1. */
function matchingBracket(source, open, opener = "[", closer = "]") {
  const masked = maskStrings(source);
  let depth = 0;
  for (let i = open; i < masked.length; i += 1) {
    const ch = masked[i];
    if (ch === opener) {
      depth += 1;
    } else if (ch === closer) {
      depth -= 1;
      if (depth === 0) {
        return i;
      }
    }
  }
  return -1;
}

/**
 * Picks the branch the repo's macOS build takes when an entry branches by
 * platform. A "?" inside a string literal (getShortcutKey("?")) is not a
 * ternary, so string bodies are masked out before the search.
 */
function macBranch(inner) {
  const masked = maskStrings(inner);
  const question = masked.indexOf("?");
  if (question < 0) {
    return inner;
  }
  const colon = masked.indexOf(":", question);
  return colon < 0 ? inner.slice(question + 1) : inner.slice(question + 1, colon);
}

const toolsBlock = sliceBlock(toolsSource, "export const TOOLS = defineTools({");
if (!toolsBlock) {
  fail("could not find the TOOLS block in components/Tools.tsx");
}

// Component name (as imported in Tools.tsx) to the icon key shared with
// scripts/port/extract-icons.mjs. These are the repo's own component names.
const ICON_BY_COMPONENT = {
  handIcon: "hand",
  SelectionIcon: "selection",
  LassoIcon: "lasso",
  RectangleIcon: "rectangle",
  DiamondIcon: "diamond",
  EllipseIcon: "ellipse",
  ArrowIcon: "arrow",
  LineIcon: "line",
  FreedrawIcon: "freedraw",
  drawShapeToolIcon: "autoshape",
  TextIcon: "text",
  stickyNoteToolIcon: "stickynote",
  ImageIcon: "image",
  EraserIcon: "eraser",
  frameToolIcon: "frame",
  EmbedIcon: "embeddable",
  laserPointerToolIcon: "laser",
  bucketFillIcon: "bucketfill",
};

const TOOLBAR_BUTTONS = {
  HandToolButton: "hand",
  SelectionToolButton: "selection",
  LassoToolButton: "lasso",
  RectangleToolButton: "rectangle",
  DiamondToolButton: "diamond",
  EllipseToolButton: "ellipse",
  ArrowToolButton: "arrow",
  LineToolButton: "line",
  FreedrawToolButton: "freedraw",
  TextToolButton: "text",
  StickyNoteToolButton: "stickynote",
  EraserToolButton: "eraser",
};

const keysSource = read(COMMON, "keys.ts");
// Only the KEYS object is read. CODES holds the physical key codes and appears
// first in the file, so matching against the whole file would pick those up.
const keysBlock = keysSource.slice(
  keysSource.indexOf("export const KEYS = {"),
  keysSource.indexOf("export type Key = keyof typeof KEYS"),
);
const keyFor = (name) => {
  const keyEntry = new RegExp(`(?:^|\\s)${name}:\\s*"([^"]+)"`, "m").exec(keysBlock);
  return keyEntry ? keyEntry[1] : name.toLowerCase();
};

/** Splits the TOOLS block into `id` plus its declaration lines. */
function parseToolEntries(block) {
  const entries = [];
  let current = null;
  for (const line of block.split("\n")) {
    const open = /^  ([A-Za-z]+):\s*\{\s*$/.exec(line);
    if (open) {
      current = { id: open[1], lines: [] };
      entries.push(current);
      continue;
    }
    if (/^  \},?\s*$/.test(line)) {
      current = null;
      continue;
    }
    if (current) {
      current.lines.push(line);
    }
  }
  return entries;
}

const tools = [];
for (const { id, lines: toolLines } of parseToolEntries(toolsBlock)) {
  const body = toolLines.join("\n");
  const icon = /icon:\s*([A-Za-z]+)/.exec(body);
  const shift = /shiftKey:\s*true/.test(body);
  const letterMath = /letterKey:\s*(\[[^\]]+\]|KEYS\.[A-Z0-9_]+)/.exec(body);
  const numeric = /numericKey:\s*KEYS\["(\d)"\]/.exec(body);
  const letters = [];
  if (letterMath) {
    for (const part of letterMath[1].matchAll(/KEYS\.([A-Z0-9_]+)/g)) {
      letters.push(keyFor(part[1]));
    }
  }
  if (!icon) {
    continue;
  }
  const iconName = ICON_BY_COMPONENT[icon[1]];
  if (!iconName) {
    fail(`no icon key known for tool "${id}" (component ${icon[1]})`);
  }
  const label = capitalize(t(`toolBar.${id}`));
  const shownLetter = letters.length
    ? shift
      ? `Shift+${capitalize(letters[0])}`
      : capitalize(letters[0])
    : null;
  const numericKey = numeric ? numeric[1] : null;
  tools.push({
    id,
    label,
    iconName,
    letters,
    shiftRequired: shift,
    numericKey,
    fillable: /fillable:\s*true/.test(body),
    toggle: /toggle:\s*true/.test(body),
    keyBindingLabel: shownLetter ?? numericKey,
    shortcutHint:
      shownLetter && numericKey
        ? `${shownLetter} ${t("helpDialog.or")} ${numericKey}`
        : `${shownLetter ?? numericKey ?? ""}`,
  });
}

if (tools.length < 15) {
  fail(`parsed only ${tools.length} tools from Tools.tsx; the source shape changed`);
}

// Toolbar layout: components/Toolbar.tsx composes the buttons by hand, so the
// rendered order is read from there rather than from the TOOLS block.
const toolbarSource = read(EDITOR, "components", "Toolbar.tsx");
// Read the rendered row from the toolbar component's own JSX. The file also
// imports the button components alphabetically at the top, so the search has to
// start at the first rendered button.
const rowStart = toolbarSource.indexOf("<HandToolButton");
const rowEnd = toolbarSource.indexOf("</Stack.Row>", rowStart);
const rowSource =
  rowStart < 0 ? "" : toolbarSource.slice(rowStart, rowEnd > rowStart ? rowEnd : undefined);
const primaryRow = [];
for (const match of rowSource.matchAll(/\b([A-Za-z]+ToolButton)\b/g)) {
  const id = TOOLBAR_BUTTONS[match[1]];
  if (id && !primaryRow.includes(id)) {
    primaryRow.push(id);
  }
}
if (primaryRow.length < 8) {
  fail("could not read the toolbar order from components/Toolbar.tsx");
}
// The toolbar shows the selection tool or the lasso, never both: lasso takes
// the selection slot when the user prefers it. Selection is the default.
const selectionSlot = ["selection", "lasso"].filter((id) => primaryRow.includes(id));
const mainRow = primaryRow.filter((id) => id !== "lasso");

const extraToolsStart = toolbarSource.indexOf("const ExtraToolsDropdown");
const extraToolsEnd = toolbarSource.indexOf("</DropdownMenu.Content>", extraToolsStart);
const extraBlock =
  extraToolsStart < 0
    ? null
    : toolbarSource.slice(
        extraToolsStart,
        extraToolsEnd > extraToolsStart ? extraToolsEnd : undefined,
      );
const extraRow = [];
const extraSkipped = [];
if (extraBlock) {
  for (const match of extraBlock.matchAll(/isToolButtonDisabled\(app,\s*"([a-z]+)"\)/g)) {
    const id = match[1];
    if (extraRow.includes(id) || extraSkipped.includes(id)) {
      continue;
    }
    // The toolbar offers a few entries the editor's TOOLS block does not
    // define (the AI wireframe tool, for example). Grafix has no such feature
    // yet, so they are recorded as skipped rather than dropped silently.
    if (tools.some((tool) => tool.id === id)) {
      extraRow.push(id);
    } else {
      extraSkipped.push(id);
    }
  }
}
if (extraRow.length < 5) {
  fail("could not read the extra tools from components/Toolbar.tsx");
}

// ---------------------------------------------------------------------------
// Shortcuts: packages/excalidraw/actions/shortcuts.ts
// ---------------------------------------------------------------------------

const shortcutSource = read(EDITOR, "actions", "shortcuts.ts");
const shortcutBlock =
  sliceBlock(shortcutSource, "const shortcutMap: Record<ShortcutName, string[]> = {") ??
  fail("could not find shortcutMap in actions/shortcuts.ts");

/** Mirrors getShortcutKey() from packages/excalidraw/shortcut.ts on macOS. */
function renderShortcutKey(spec) {
  return spec
    .replace(/\b(Opt(?:ion)?|Alt)\b/gi, t("keys.option"))
    .replace(/\bShift\b/gi, t("keys.shift"))
    .replace(/\b(Enter|Return)\b/gi, t("keys.enter"))
    .replace(/\b(Ctrl|Cmd|Command|CtrlOrCmd)\b/gi, t("keys.cmd"))
    .replace(/\b(Esc(?:ape)?)\b/gi, t("keys.escape"))
    .replace(/\b(Space(?:bar)?)\b/gi, t("keys.spacebar"))
    .replace(/\b(Del(?:ete)?)\b/gi, t("keys.delete"));
}

const shortcuts = [];
{
  // Each entry is `name: [ ... ]`, and the array can span lines and contain a
  // macOS/other platform ternary (the repo writes the macOS branch first).
  const entryPattern = /\n {2}([A-Za-z]+):\s*\[/g;
  let match = entryPattern.exec(shortcutBlock);
  while (match) {
    const name = match[1];
    const open = shortcutBlock.indexOf("[", match.index);
    const close = matchingBracket(shortcutBlock, open);
    if (close < 0) {
      fail(`unbalanced shortcut list for ${name}`);
    }
    const inner = shortcutBlock.slice(open + 1, close);
    // Keep the branch getShortcutFromShortcutName(name, 0) would use: the first
    // one listed, which is the macOS one wherever the repo branches.
    const branch = macBranch(inner);
    const specs = [...branch.matchAll(/getShortcutKey\(\s*(?:"([^"]*)"|'([^']*)'|`([^`]*)`)/g)].map(
      (spec) => spec[1] ?? spec[2] ?? spec[3],
    );
    if (specs.length === 0 && branch.trim().length > 0) {
      fail(`could not read the shortcut keys for ${name}: ${branch.trim()}`);
    }
    // The repo listens for every binding an action declares, so the native app
    // records them all rather than only the first.
    const glyphs = specs.map((spec) =>
      renderShortcutKey(spec.replace(/\$\{t\("([^"]+)"\)\}/g, (_, key) => t(key))),
    );
    shortcuts.push({ name, glyphs });
    entryPattern.lastIndex = close;
    match = entryPattern.exec(shortcutBlock);
  }
}
if (shortcuts.length === 0) {
  fail("no shortcuts were read from actions/shortcuts.ts");
}
const shortcutByName = new Map(shortcuts.map((entry) => [entry.name, entry.glyphs]));

// The help dialog names keys through the repo's KEYS map, so read that map too
// rather than retyping its letters and numerals.
const KEYS = (() => {
  const source = read(COMMON, "keys.ts");
  const declaration = source.indexOf("export const KEYS = {");
  if (declaration < 0) {
    return fail("could not find KEYS in packages/common/src/keys.ts");
  }
  const open = source.indexOf("{", declaration);
  const close = matchingBracket(source, open, "{", "}");
  if (close < 0) {
    return fail("the KEYS literal in packages/common/src/keys.ts is never closed");
  }
  // KEYS branches on isDarwin for one entry; Grafix is macOS only.
  return Function("isDarwin", `return (${source.slice(open, close + 1)});`)(true);
})();

// ---------------------------------------------------------------------------
// Help dialog: packages/excalidraw/components/HelpDialog.tsx
// ---------------------------------------------------------------------------

// The native app is macOS only, so the platform constants the dialog branches
// on are fixed. Grafix can also put a PNG on the clipboard, so the clipboard
// capability the dialog tests for is true here.
const HELP_CONDITIONS = {
  isDarwin: true,
  isWindows: false,
  isFirefox: false,
  probablySupportsClipboardBlob: true,
};

/** Evaluates a boolean expression from HelpDialog.tsx, or fails loudly. */
function evalHelpCondition(text) {
  const names = Object.keys(HELP_CONDITIONS);
  const values = names.map((name) => HELP_CONDITIONS[name]);
  const expression = maskStrings(text).replace(
    /actionManager\.isActionEnabled\(actionToggleTheme\)/g,
    "__toggleTheme",
  );
  try {
    // The expression comes from the trusted upstream repo and uses only the
    // identifiers bound below.
    return Boolean(Function(...names, "__toggleTheme", `return (${expression});`)(...values, true));
  } catch {
    return fail(`could not evaluate the help-dialog condition ${text.trim()}`);
  }
}

// The dialog hides two rows behind a `condition && (<Shortcut … />)` wrapper.
// Resolve those first, so what is left is a flat list of elements.
let helpSource = read(EDITOR, "components", "HelpDialog.tsx");
helpSource = helpSource.replace(
  /\{\s*\(?([^(){}]*(?:\([^()]*\))?[^(){}]*?)\)?\s*&&\s*\(\s*(<Shortcut[\s\S]*?\/>)\s*\)\s*\}/g,
  (whole, condition, element) => (evalHelpCondition(condition) ? element : ""),
);
const helpMasked = maskStrings(helpSource);
if (/\&\&\s*\(\s*<Shortcut/.test(helpMasked)) {
  fail("a HelpDialog shortcut is still wrapped in a condition the parser cannot read");
}

/** Reads a JSX element's text, from `<` to its closing `/>` or `</tag>`. */
function readJsxElement(source, masked, start) {
  let depth = 0;
  for (let i = start; i < masked.length; i += 1) {
    const ch = masked[i];
    if (ch === "{") {
      depth += 1;
    } else if (ch === "}") {
      depth -= 1;
    } else if (depth === 0 && ch === "/" && masked[i + 1] === ">") {
      return source.slice(start, i + 2);
    }
  }
  return fail(`unterminated JSX element in HelpDialog.tsx near ${source.slice(start, start + 40)}`);
}

/** Splits on a single-character separator, ignoring brackets and literals. */
function splitTopLevel(source, separator) {
  const masked = maskStrings(source);
  const parts = [];
  let depth = 0;
  let start = 0;
  for (let i = 0; i < masked.length; i += 1) {
    const ch = masked[i];
    if (ch === "(" || ch === "[" || ch === "{") {
      depth += 1;
    } else if (ch === ")" || ch === "]" || ch === "}") {
      depth -= 1;
    } else if (depth === 0 && ch === separator) {
      parts.push(source.slice(start, i));
      start = i + 1;
    }
  }
  parts.push(source.slice(start));
  return parts;
}

/** Splits `condition ? a : b` at top level, or returns null. */
function splitTopLevelTernary(source) {
  const masked = maskStrings(source);
  let depth = 0;
  let question = -1;
  let nested = 0;
  for (let i = 0; i < masked.length; i += 1) {
    const ch = masked[i];
    if (ch === "(" || ch === "[" || ch === "{") {
      depth += 1;
    } else if (ch === ")" || ch === "]" || ch === "}") {
      depth -= 1;
    } else if (depth === 0 && ch === "?") {
      if (question < 0) {
        question = i;
      }
      nested += 1;
    } else if (depth === 0 && ch === ":" && question >= 0) {
      nested -= 1;
      if (nested === 0) {
        return {
          condition: source.slice(0, question).trim(),
          then: source.slice(question + 1, i).trim(),
          otherwise: source.slice(i + 1).trim(),
        };
      }
    }
  }
  return null;
}

/** The text of a string or template literal, with ${t(...)} substituted. */
function helpLiteralText(expression) {
  const template = /^`([\s\S]*)`$/.exec(expression);
  if (template) {
    return template[1].replace(/\$\{t\("([^"]+)"\)\}/g, (_, key) => t(key));
  }
  const double = /^"([^"]*)"$/.exec(expression);
  if (double) {
    return double[1];
  }
  const single = /^'([^']*)'$/.exec(expression);
  if (single) {
    return single[1];
  }
  return null;
}

// The dialog displays a lone lower-case letter as a capital, exactly as its
// upperCaseSingleChars() helper does.
const upperCaseSingleChars = (text) => text.replace(/\b[a-z]\b/, (c) => c.toUpperCase());

/**
 * The key chips the dialog draws for one binding, using HelpDialog's own split
 * rule: components around "+", except that a binding ending in "++" ends with a
 * literal "+" key.
 */
function helpChips(binding) {
  const keys = binding.endsWith("++")
    ? [...binding.slice(0, -2).split("+"), "+"]
    : binding.split("+");
  return keys.map(upperCaseSingleChars);
}

/** Resolves one entry of a shortcut list to the key text the dialog shows. */
function evalHelpItem(item) {
  const expression = item.trim();
  const ternary = splitTopLevelTernary(expression);
  if (ternary) {
    if (!(ternary.condition in HELP_CONDITIONS)) {
      fail(`unhandled help-dialog condition ${ternary.condition}`);
    }
    return evalHelpItem(HELP_CONDITIONS[ternary.condition] ? ternary.then : ternary.otherwise);
  }
  const fromName = /^getShortcutFromShortcutName\("([^"]+)"(?:\s*,\s*(\d+))?\)$/.exec(expression);
  if (fromName) {
    const glyphs = shortcutByName.get(fromName[1]);
    if (!glyphs || glyphs.length === 0) {
      fail(`the help dialog refers to the unknown shortcut ${fromName[1]}`);
    }
    return glyphs[Number(fromName[2] ?? 0)] ?? glyphs[0];
  }
  const getKey = /^getShortcutKey\(([\s\S]*)\)$/.exec(expression);
  if (getKey) {
    const text = helpLiteralText(getKey[1].trim());
    if (text === null) {
      return fail(`could not read the key in ${expression}`);
    }
    return renderShortcutKey(text);
  }
  const translated = /^t\("([^"]+)"\)$/.exec(expression);
  if (translated) {
    return upperCaseSingleChars(t(translated[1]));
  }
  const keyRef =
    /^KEYS\.([A-Za-z_0-9]+)$/.exec(expression) ??
    /^KEYS\["([^"]+)"\]$/.exec(expression) ??
    /^KEYS\[(\d+)\]$/.exec(expression);
  if (keyRef) {
    const name = keyRef[1];
    if (!(name in KEYS)) {
      fail(`the help dialog refers to the unknown key KEYS.${name}`);
    }
    return upperCaseSingleChars(KEYS[name]);
  }
  const literal = helpLiteralText(expression);
  if (literal !== null) {
    return upperCaseSingleChars(literal);
  }
  return fail(`could not read a help-dialog key from: ${expression}`);
}

/** Resolves a `[ … ]` shortcut list, or a ternary that yields one. */
function evalHelpKeys(expression) {
  const trimmed = expression.trim();
  if (!trimmed.startsWith("[")) {
    const ternary = splitTopLevelTernary(trimmed);
    if (ternary) {
      if (!(ternary.condition in HELP_CONDITIONS)) {
        fail(`unhandled help-dialog condition ${ternary.condition}`);
      }
      return evalHelpKeys(HELP_CONDITIONS[ternary.condition] ? ternary.then : ternary.otherwise);
    }
    return fail(`could not read the shortcut list ${trimmed}`);
  }
  if (!trimmed.endsWith("]")) {
    return fail(`unbalanced shortcut list ${trimmed}`);
  }
  const inner = trimmed.slice(1, -1);
  if (inner.trim().length === 0) {
    return [];
  }
  return splitTopLevel(inner, ",")
    .map((item) => item.trim())
    .filter((item) => item.length > 0)
    .map(evalHelpItem);
}

const helpLinks = [];
// The dialog's header links each carry an icon from icons.tsx; the extractor's
// key names are lower-cased component names.
const HELP_LINK_ICONS = {
  ExternalLinkIcon: "externallink",
  GithubIcon: "github",
  youtubeIcon: "youtube",
};
{
  const start = helpSource.indexOf("const Header =");
  const end = helpSource.indexOf("const Section =");
  if (start < 0 || end < start) {
    fail("could not find the Header component in components/HelpDialog.tsx");
  }
  for (const anchor of helpSource.slice(start, end).matchAll(/<a\b[\s\S]*?<\/a>/g)) {
    const href = /href="([^"]+)"/.exec(anchor[0]);
    if (!href) {
      fail(`a HelpDialog header link has no href: ${anchor[0].slice(0, 60)}`);
    }
    const translated = /\{t\("([^"]+)"\)\}/.exec(anchor[0]);
    const literal = />\s*([A-Za-z0-9!?+ ]+?)\s*<\/a>/.exec(anchor[0]);
    const label = translated ? translated[1] : literal?.[1];
    if (!label) {
      fail(`could not read the label of the HelpDialog link to ${href[1]}`);
    }
    const icon = /\{(ExternalLinkIcon|GithubIcon|youtubeIcon)\}/.exec(anchor[0]);
    if (!icon) {
      fail(`the HelpDialog link to ${href[1]} has no icon`);
    }
    helpLinks.push({
      label,
      labelKey: translated ? label : null,
      iconName: HELP_LINK_ICONS[icon[1]],
      url: href[1],
    });
  }
  if (helpLinks.length === 0) {
    fail("no links were read from the HelpDialog header");
  }
}

const helpIslands = [];
{
  const starts = [...helpMasked.matchAll(/<ShortcutIsland\b/g)].map((match) => match.index);
  if (starts.length === 0) {
    fail("could not find any ShortcutIsland in components/HelpDialog.tsx");
  }
  for (const start of starts) {
    const tagEnd = helpMasked.indexOf(">", start);
    const tag = helpSource.slice(start, tagEnd + 1);
    const caption = /caption=\{t\("([^"]+)"\)\}/.exec(tag);
    if (!caption) {
      fail(`a ShortcutIsland has no caption: ${tag.slice(0, 60)}`);
    }
    const bodyEnd = helpMasked.indexOf("</ShortcutIsland>", tagEnd);
    if (bodyEnd < 0) {
      fail(`the ${caption[1]} island is never closed`);
    }
    const body = helpSource.slice(tagEnd + 1, bodyEnd);
    const maskedBody = helpMasked.slice(tagEnd + 1, bodyEnd);
    const rows = [];
    let cursor = 0;
    while (true) {
      const elementStart = maskedBody.indexOf("<Shortcut", cursor);
      if (elementStart < 0) {
        break;
      }
      const element = readJsxElement(body, maskedBody, elementStart);
      const label = /label=\{t\("([^"]+)"\)\}/.exec(element);
      if (!label) {
        fail(`a Shortcut in the ${caption[1]} island has no t(...) label: ${element.slice(0, 60)}`);
      }
      const keysProp = /shortcuts=\{/.exec(element);
      if (!keysProp) {
        fail(`the ${label[1]} shortcut has no shortcuts prop`);
      }
      const open = element.indexOf("{", keysProp.index);
      const close = matchingBracket(element, open, "{", "}");
      if (close < 0) {
        fail(`unbalanced shortcuts prop for ${label[1]}`);
      }
      rows.push({
        label: label[1],
        keys: evalHelpKeys(element.slice(open + 1, close)).map(helpChips),
        isOr: !/isOr=\{false\}/.test(element),
      });
      cursor = elementStart + element.length;
    }
    if (rows.length === 0) {
      fail(`no shortcuts were read from the ${caption[1]} island`);
    }
    helpIslands.push({ caption: caption[1], rows });
  }
}
const helpRowCount = helpIslands.reduce((total, island) => total + island.rows.length, 0);

// ---------------------------------------------------------------------------
// Palette: packages/common/src/colors.ts
// ---------------------------------------------------------------------------

const colorsSource = read(COMMON, "colors.ts");

/** Evaluates a literal block from colors.ts against a small prepared scope. */
function evalLiteral(declaration, scope) {
  const start = colorsSource.indexOf(declaration);
  if (start < 0) {
    fail(`could not find ${declaration} in packages/common/src/colors.ts`);
  }
  const tail = colorsSource.slice(start);
  const body = tail.slice(tail.indexOf("=") + 1);
  // Cut at the end of the literal's own brackets rather than at a blank line,
  // so comments and spacing inside the literal survive.
  const open = body.search(/[[{]/);
  if (open < 0) {
    fail(`${declaration} does not start a literal`);
  }
  const openers = { "{": "}", "[": "]" };
  const stack = [];
  let end = -1;
  for (let i = open; i < body.length; i += 1) {
    const ch = body[i];
    if (ch === "{" || ch === "[") {
      stack.push(openers[ch]);
    } else if (ch === "}" || ch === "]") {
      if (stack.pop() !== ch) {
        fail(`${declaration} has unbalanced brackets`);
      }
      if (stack.length === 0) {
        end = i + 1;
        break;
      }
    }
  }
  if (end < 0) {
    fail(`${declaration} was never closed`);
  }
  const literal = body.slice(open, end);
  const names = Object.keys(scope);
  const values = names.map((name) => scope[name]);
  // The literal comes from the trusted upstream repo.
  return Function(...names, `return (${literal});`)(...values);
}

const colorPalette = evalLiteral("export const COLOR_PALETTE =", {});
const shadeKeys = [
  "cyan",
  "blue",
  "violet",
  "grape",
  "pink",
  "green",
  "teal",
  "yellow",
  "orange",
  "red",
];
const stickyNoteBackground =
  /export const DEFAULT_STICKY_NOTE_BG = "([^"]+)"/.exec(colorsSource)?.[1] ??
  fail("could not find DEFAULT_STICKY_NOTE_BG in packages/common/src/colors.ts");

const scope = {
  COLOR_PALETTE: colorPalette,
  COMMON_ELEMENT_SHADES: Object.fromEntries(
    shadeKeys.map((key) => [key, colorPalette[key]]),
  ),
  DEFAULT_ELEMENT_STROKE_COLOR_INDEX: 4,
  DEFAULT_ELEMENT_BACKGROUND_COLOR_INDEX: 1,
  DEFAULT_STICKY_NOTE_BG: stickyNoteBackground,
};
const canvasPicks = evalLiteral(
  "export const DEFAULT_CANVAS_BACKGROUND_PICKS =",
  { COLOR_PALETTE: colorPalette },
);

const palette = {
  families: Object.entries(colorPalette).map(([name, value]) => ({
    name,
    shades: Array.isArray(value) ? value : [value],
  })),
  strokePicks: evalLiteral("export const DEFAULT_ELEMENT_STROKE_PICKS =", scope),
  backgroundPicks: evalLiteral(
    "export const DEFAULT_ELEMENT_BACKGROUND_PICKS =",
    scope,
  ),
  bucketFillPicks: evalLiteral(
    "export const BUCKET_FILL_BACKGROUND_PICKS =",
    scope,
  ),
  stickyNoteBackgroundPicks: evalLiteral(
    "export const STICKY_NOTE_BACKGROUND_PICKS =",
    scope,
  ),
  canvasBackgroundPicks: canvasPicks,
  stickyNoteBackground,
  strokePalette: evalLiteral(
    "export const DEFAULT_ELEMENT_STROKE_COLOR_PALETTE =",
    scope,
  ),
  backgroundPalette: evalLiteral(
    "export const DEFAULT_ELEMENT_BACKGROUND_COLOR_PALETTE =",
    scope,
  ),
  constants: {
    colorsPerRow: Number(
      /export const COLORS_PER_ROW = (\d+)/.exec(colorsSource)?.[1] ?? 5,
    ),
    maxCustomColorsInCanvas: Number(
      /export const MAX_CUSTOM_COLORS_USED_IN_CANVAS = (\d+)/.exec(
        colorsSource,
      )?.[1] ?? 5,
    ),
    topPicksSlots: Number(
      /export const COLOR_TOP_PICKS_SLOTS = (\d+)/.exec(colorsSource)?.[1] ?? 5,
    ),
    defaultStrokeColorIndex: 4,
    defaultBackgroundColorIndex: 1,
  },
};

// ---------------------------------------------------------------------------
// Theme tokens: packages/excalidraw/css/theme.scss
// ---------------------------------------------------------------------------

const variablesSource = read(EDITOR, "css", "variables.module.scss");
const scssVariables = new Map();
for (const match of variablesSource.matchAll(/^\$([\w-]+):\s*([^;]+);/gm)) {
  scssVariables.set(match[1], match[2].trim());
}

const themeSource = read(EDITOR, "css", "theme.scss");

function parseThemeTokens(source) {
  const tokens = { light: {}, dark: {} };
  // Only the `.excalidraw` block carries tokens; the rest of the file is
  // selectors for states that are not ported yet.
  const start = source.indexOf("  --theme-filter:");
  if (start < 0) {
    fail("could not find the token block in css/theme.scss");
  }
  const end = source.indexOf("\n}\n", start);
  if (end < 0) {
    fail("could not find the end of the token block in css/theme.scss");
  }
  const body = source.slice(start, end);
  const lines = body.split("\n");
  // A stack of nesting contexts. Blocks that only restate a breakpoint or a
  // mixin must not overwrite the base values, so they are marked "skip".
  const stack = ["light"];
  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index];
    const trimmed = line.trim();
    const opens = trimmed.endsWith("{");
    if (opens) {
      const selector = trimmed.slice(0, -1).trim();
      const parent = stack[stack.length - 1];
      if (selector.startsWith("@")) {
        stack.push("skip");
      } else if (selector.includes("theme--dark")) {
        stack.push("dark");
      } else {
        stack.push(parent);
      }
      continue;
    }
    if (trimmed.startsWith("}")) {
      if (stack.length > 1) {
        stack.pop();
      }
      continue;
    }
    const context = stack[stack.length - 1];
    if (context === "skip") {
      continue;
    }
    const start_of = /^\s*--([\w-]+):\s*(.*)$/.exec(line);
    if (!start_of) {
      continue;
    }
    // Box shadows and a few other values are written across several lines.
    let text = start_of[2];
    while (!/;\s*$/.test(text) && index + 1 < lines.length) {
      index += 1;
      text += ` ${lines[index].trim()}`;
    }
    let value = text.replace(/;\s*$/, "").trim().replace(/\s+/g, " ");
    value = value.replace(/#\{\$([\w-]+)\}/g, (whole, name) =>
      scssVariables.get(name) ?? whole,
    );
    if (/#\{/.test(value)) {
      continue; // unresolved SCSS expression; skipped on purpose
    }
    tokens[stack[stack.length - 1] === "dark" ? "dark" : "light"][
      `--${start_of[1]}`
    ] = value;
  }
  return tokens;
}

const themeTokens = parseThemeTokens(themeSource);

// ---------------------------------------------------------------------------
// UI copy: the repo's English strings, so the native UI says the same words
// ---------------------------------------------------------------------------

const STRING_NAMESPACES = [
  "labels",
  "buttons",
  "toolBar",
  "helpDialog",
  "keys",
  "headings",
  "alerts",
  "stats",
  "colorPicker",
  "shortcuts",
  "toast",
  "search",
  "mermaid",
  "elementCanvasButtons",
  "hints",
  "commandPalette",
];

const strings = {};
for (const namespace of STRING_NAMESPACES) {
  const group = en[namespace];
  if (!group || typeof group !== "object") {
    continue;
  }
  for (const [key, value] of Object.entries(group)) {
    if (typeof value === "string") {
      strings[`${namespace}.${key}`] = value;
    }
  }
}

// ---------------------------------------------------------------------------
// Swift emission
// ---------------------------------------------------------------------------

const swiftString = (value) =>
  `"${String(value)
    .replace(/\\/g, "\\\\")
    .replace(/"/g, '\\"')
    .replace(/\n/g, "\\n")}"`;

const header = (origin) =>
  `// swift-format-ignore-file\n` +
  `// Generated by scripts/port/extract-ui.mjs from ${origin}@${COMMIT.slice(0, 12)}.\n` +
  `// Do not edit by hand. Run \`node scripts/port/extract-ui.mjs\` to refresh.\n\n` +
  `import Foundation\n\n`;

const bool = (value) => (value ? "true" : "false");

const stringArray = (values, indent) =>
  values.length
    ? `[\n${values.map((v) => `${indent}  ${swiftString(v)},`).join("\n")}\n${indent}]`
    : "[]";

const stringArrayArray = (values, indent) =>
  values.length
    ? `[\n${values
        .map((inner) => `${indent}  ${stringArray(inner, `${indent}  `)},`)
        .join("\n")}\n${indent}]`
    : "[]";

const toolsSwift =
  header("excalidraw") +
  `/// One tool button, exactly as the Excalidraw toolbar defines it.
public struct PortTool: Sendable, Equatable {
  public let id: String
  public let label: String
  public let iconName: String
  /// Letter keys that activate the tool, lowercased, in priority order.
  public let letters: [String]
  /// Whether the letter key needs Shift held.
  public let shiftRequired: Bool
  public let numericKey: String?
  /// Shapes drawn with this tool can take a background colour.
  public let fillable: Bool
  /// Pressing the shortcut again while the tool is active goes back to the previous tool.
  public let toggle: Bool
  /// The letter shown in the button's corner, e.g. "Shift+X" or "9".
  public let keyBindingLabel: String?
  /// The tooltip hint, e.g. "R or 2".
  public let shortcutHint: String
}

public enum PortTools {
  public static let repoCommit = ${swiftString(COMMIT)}

  /// Every tool the editor knows, in the order the repo declares them.
  public static let all: [PortTool] = [
${tools
  .map(
    (tool) => `    PortTool(
      id: ${swiftString(tool.id)},
      label: ${swiftString(tool.label)},
      iconName: ${swiftString(tool.iconName)},
      letters: ${stringArray(tool.letters, "      ")},
      shiftRequired: ${bool(tool.shiftRequired)},
      numericKey: ${tool.numericKey ? swiftString(tool.numericKey) : "nil"},
      fillable: ${bool(tool.fillable)},
      toggle: ${bool(tool.toggle)},
      keyBindingLabel: ${
        tool.keyBindingLabel ? swiftString(tool.keyBindingLabel) : "nil"
      },
      shortcutHint: ${swiftString(tool.shortcutHint)}
    ),`,
  )
  .join("\n")}
  ]

  /// The tool buttons the toolbar shows in its main row, in rendered order.
  /// The "selection" entry is drawn as whichever of \`selectionTools\` the user prefers.
  public static let toolbarRow: [String] = ${stringArray(mainRow, "  ")}

  /// The two tools that can occupy the selection slot, first one by default.
  public static let selectionTools: [String] = ${stringArray(
    selectionSlot.length ? selectionSlot : ["selection", "lasso"],
    "  ",
  )}

  /// The tools behind the toolbar's "more tools" menu, in rendered order.
  public static let extraTools: [String] = ${stringArray(extraRow, "  ")}

  /// Toolbar entries the repo offers that have no editor tool behind them yet,
  /// recorded so a missing button is never a silent omission.
  public static let unportedToolbarEntries: [String] = ${stringArray(
    extraSkipped,
    "  ",
  )}

  public static func tool(_ id: String) -> PortTool? {
    all.first { $0.id == id }
  }

  /// The tool a keypress activates, mirroring findShapeByKey().
  public static func tool(forKey key: String, shift: Bool) -> PortTool? {
    let lower = key.lowercased()
    for tool in all where tool.shiftRequired == shift {
      if tool.numericKey == key || tool.letters.contains(lower) {
        return tool
      }
    }
    return nil
  }
}
`;

const shortcutsSwift =
  header("excalidraw") +
  `/// One keyboard shortcut, keyed by the repo's action name.
public struct PortShortcut: Sendable, Equatable {
  public let name: String
  /// Rendered the same way the web editor renders it on macOS, e.g. "Cmd+Shift+E".
  public let glyphs: [String]
}

public enum PortShortcuts {
  public static let repoCommit = ${swiftString(COMMIT)}

  public static let all: [PortShortcut] = [
${shortcuts
  .map(
    (shortcut) => `    PortShortcut(
      name: ${swiftString(shortcut.name)},
      glyphs: ${stringArray(shortcut.glyphs, "      ")}
    ),`,
  )
  .join("\n")}
  ]

  public static func glyphs(for action: String) -> [String] {
    all.first { $0.name == action }?.glyphs ?? []
  }

  public static func first(_ action: String) -> String? {
    glyphs(for: action).first
  }
}
`;

const helpSwift =
  header("excalidraw") +
  `/// One row of the shortcuts dialog: what the action is called and the keys it
/// answers to, exactly as the web editor lists them.
public struct PortHelpRow: Sendable, Equatable {
  /// The repo's own string key for the label, for PortStrings.text(_:).
  public let labelKey: String
  /// One entry per binding the row lists. Each entry holds the key chips the
  /// dialog draws, already split the way the web editor splits them.
  public let keys: [[String]]
  /// True when the bindings are alternatives, which the repo joins with "or".
  public let isOr: Bool

  /// One binding as text, e.g. "Cmd+Shift+E", for matching against the keys the
  /// native editor answers.
  public var bindings: [String] { keys.map { $0.joined(separator: "+") } }
}

/// One group of rows inside the shortcuts dialog ("Tools", "View", "Editor").
public struct PortHelpIsland: Sendable, Equatable {
  /// The repo's own string key for the caption.
  public let captionKey: String
  public let rows: [PortHelpRow]
}

/// A link in the dialog's header, such as the documentation site.
public struct PortHelpLink: Sendable, Equatable {
  /// The repo's own string key when the label comes from t(...), else nil.
  public let labelKey: String?
  /// The literal label when the repo writes it directly, e.g. "YouTube".
  public let label: String
  /// The extractor's key for the link's icon, from icons.tsx.
  public let iconName: String
  public let url: String

  /// The label to draw, preferring the repo's own copy.
  public var text: String { labelKey.map(PortStrings.text) ?? label }
}

/// The shortcuts dialog from components/HelpDialog.tsx.
public enum PortHelp {
  public static let repoCommit = ${swiftString(COMMIT)}

  /// The dialog title, from PortStrings ("helpDialog.title").
  public static let titleKey = ${swiftString("helpDialog.title")}
  /// The section heading above the shortcut islands.
  public static let shortcutsKey = ${swiftString("helpDialog.shortcuts")}
  /// The word the repo puts between alternative bindings.
  public static let orKey = ${swiftString("helpDialog.or")}

  public static let links: [PortHelpLink] = [
${helpLinks
  .map(
    (link) => `    PortHelpLink(
      labelKey: ${link.labelKey ? swiftString(link.labelKey) : "nil"},
      label: ${swiftString(link.labelKey ? "" : link.label)},
      iconName: ${swiftString(link.iconName)},
      url: ${swiftString(link.url)}
    ),`,
  )
  .join("\n")}
  ]

  public static let islands: [PortHelpIsland] = [
${helpIslands
  .map(
    (island) => `    PortHelpIsland(
      captionKey: ${swiftString(island.caption)},
      rows: [
${island.rows
  .map(
    (row) => `        PortHelpRow(
          labelKey: ${swiftString(row.label)},
          keys: ${stringArrayArray(row.keys, "          ")},
          isOr: ${bool(row.isOr)}
        ),`,
  )
  .join("\n")}
      ]
    ),`,
  )
  .join("\n")}
  ]
}
`;

const familiesSwift = palette.families
  .map(
    (family) => `    PortColorFamily(
      name: ${swiftString(family.name)},
      shades: ${stringArray(family.shades, "      ")}
    ),`,
  )
  .join("\n");

const paletteSwift =
  header("excalidraw") +
  `/// A named colour family from the repo's palette, e.g. "blue" with five shades.
public struct PortColorFamily: Sendable, Equatable {
  public let name: String
  public let shades: [String]
}

public enum PortPalette {
  public static let repoCommit = ${swiftString(COMMIT)}

  public static let families: [PortColorFamily] = [
${familiesSwift}
  ]

  /// The five swatches the stroke picker shows above the full grid.
  public static let strokePicks: [String] = ${stringArray(palette.strokePicks, "  ")}

  /// The five swatches the background picker shows above the full grid.
  public static let backgroundPicks: [String] = ${stringArray(palette.backgroundPicks, "  ")}

  /// The bucket tool's quick picks. Same as the background picks with white in place of transparent.
  public static let bucketFillPicks: [String] = ${stringArray(palette.bucketFillPicks, "  ")}

  /// Sticky notes are their own colour domain.
  public static let stickyNotePicks: [String] = ${stringArray(palette.stickyNoteBackgroundPicks, "  ")}

  /// The canvas background picker's quick picks.
  public static let canvasBackgroundPicks: [String] = ${stringArray(
    palette.canvasBackgroundPicks,
    "  ",
  )}

  public static let stickyNoteBackground = ${swiftString(palette.stickyNoteBackground)}

  /// The full stroke grid, in the declared order, one entry per column group.
  public static let strokePalette: [PortColorFamily] = [
${Object.entries(palette.strokePalette)
  .map(
    ([name, value]) => `    PortColorFamily(
      name: ${swiftString(name)},
      shades: ${stringArray(Array.isArray(value) ? value : [value], "      ")}
    ),`,
  )
  .join("\n")}
  ]

  public static let backgroundPalette: [PortColorFamily] = [
${Object.entries(palette.backgroundPalette)
  .map(
    ([name, value]) => `    PortColorFamily(
      name: ${swiftString(name)},
      shades: ${stringArray(Array.isArray(value) ? value : [value], "      ")}
    ),`,
  )
  .join("\n")}
  ]

  public static let columnsPerRow = ${palette.constants.colorsPerRow}
  public static let topPickSlots = ${palette.constants.topPicksSlots}
  public static let maxCustomColorsInCanvas = ${palette.constants.maxCustomColorsInCanvas}
  public static let defaultStrokeShadeIndex = ${palette.constants.defaultStrokeColorIndex}
  public static let defaultBackgroundShadeIndex = ${palette.constants.defaultBackgroundColorIndex}
}
`;

const tokenEntries = (map) =>
  Object.entries(map)
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([name, value]) => `      ${swiftString(name)}: ${swiftString(value)},`)
    .join("\n");

const themeSwift =
  header("excalidraw") +
  `/// The repo's CSS custom properties for both themes.
public struct PortThemeTokens: Sendable, Equatable {
  public let light: [String: String]
  public let dark: [String: String]
}

public enum PortTheme {
  public static let repoCommit = ${swiftString(COMMIT)}

  public static let tokens = PortThemeTokens(
    light: [
${tokenEntries(themeTokens.light)}
    ],
    dark: [
${tokenEntries(themeTokens.dark)}
    ]
  )

  /// The value of a CSS custom property, following \`var(--other)\` references the
  /// way a browser does. Returns nil for a token neither theme defines.
  ///
  /// The repo's dark block holds overrides on top of \`:root\`, so a token the
  /// dark theme does not set keeps its light value, exactly as CSS does.
  public static func raw(_ token: String, dark: Bool) -> String? {
    let name = token.hasPrefix("--") ? token : "--\\(token)"
    var value = declared(name, dark: dark)
    var hops = 0
    while let current = value, current.hasPrefix("var("), hops < 8 {
      let inner = current.dropFirst(4).dropLast()
      let reference = inner.split(separator: ",")[0].trimmingCharacters(in: .whitespaces)
      value = declared(reference, dark: dark)
      hops += 1
    }
    return value
  }

  /// The declared value of one token: the dark override where there is one, and
  /// the \`:root\` value otherwise.
  private static func declared(_ name: String, dark: Bool) -> String? {
    if dark, let override = tokens.dark[name] {
      return override
    }
    return tokens.light[name] ?? tokens.dark[name]
  }
}
`;

const stringsSwift =
  header("excalidraw") +
  `/// The repo's English UI copy, keyed the same way the source keys it,
  /// e.g. "toolBar.lasso", so the native UI says what the web editor says.
public enum PortStrings {
  public static let repoCommit = ${swiftString(COMMIT)}

  public static let all: [String: String] = [
${Object.entries(strings)
  .sort(([a], [b]) => a.localeCompare(b))
  .map(([key, value]) => `    ${swiftString(key)}: ${swiftString(value)},`)
  .join("\n")}
  ]

  public static func text(_ key: String) -> String {
    all[key] ?? key
  }
}
`;

const outputs = {
  "PortTools.swift": toolsSwift,
  "PortShortcuts.swift": shortcutsSwift,
  "PortHelp.swift": helpSwift,
  "PortPalette.swift": paletteSwift,
  "PortTheme.swift": themeSwift,
  "PortStrings.swift": stringsSwift,
};

mkdirSync(OUT_DIR, { recursive: true });
let stale = [];
for (const [name, contents] of Object.entries(outputs)) {
  const path = join(OUT_DIR, name);
  const existing = existsSync(path) ? readFileSync(path, "utf8") : null;
  if (check) {
    if (existing !== contents) {
      stale.push(name);
    }
    continue;
  }
  writeFileSync(path, contents);
}

if (check && stale.length) {
  fail(
    `generated Swift is out of date: ${stale.join(", ")}.\n` +
      `Run: node scripts/port/extract-ui.mjs`,
  );
}

console.log(
  `extract-ui: excalidraw@${COMMIT.slice(0, 12)}\n` +
    `  tools        ${tools.length} (toolbar ${mainRow.length}, more tools ${extraRow.length})\n` +
    `  skipped      ${extraSkipped.join(", ") || "none"}\n` +
    `  shortcuts    ${shortcuts.length}\n` +
    `  help         ${helpRowCount} rows in ${helpIslands.length} islands\n` +
    `  palette      ${palette.families.length} families\n` +
    `  theme        ${Object.keys(themeTokens.light).length} light, ${
      Object.keys(themeTokens.dark).length
    } dark tokens\n` +
    `  strings      ${Object.keys(strings).length}\n` +
    (check ? "  check        up to date" : `  wrote        ${OUT_DIR}`),
);
