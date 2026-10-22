# Grafix

A native macOS drawing app in Swift, starting from Excalidraw's document format and interaction model. No web view. This repository is an early working port, not yet a replacement for Excalidraw+.

## Run

Requires macOS 14 or later and a Swift 6 toolchain.

```sh
swift run Grafix
```

Build a local app bundle:

```sh
./scripts/build-app.sh
open .build/Grafix.app
```

Drawings live under `~/Documents/Grafix/`, with a folder per collection. No account or hosted storage is required. Keep backups of important drawings while the port is under development.

## First-draft requirements

These are required outcomes, not optional follow-ups:

- Native canvas with Excalidraw's hand-drawn appearance.
- Collections and presentations.
- Built-in AI chat that can work on the open drawing.
- MCP/API access for external agents.
- Full Excalidraw round-trip compatibility, including properties the editor does not yet understand.

The implementation starts with JSON property preservation, native drawing tools, a local MCP process, and a Codex chat panel. Preserving JSON does not establish rendering or editing compatibility. Exact sketch rendering, typography, bound-element geometry, all element types, and live agent coordination need independent verification before the compatibility requirement is complete.

## Built-in chat

The chat panel uses an installed and authenticated `codex` CLI. It sends the current drawing and your message to Codex, then offers a proposed canvas update. Applying it uses the editor's undo path. AI inference still requires your existing subscription or provider access; local storage does not make inference free.

## Checks

```sh
swift test
xcrun swift-format lint --strict --recursive Package.swift Sources Tests
```

The Swift tests cover document preservation and safe saves. Excalidraw's JavaScript test suite cannot verify the native UI unchanged. A native interaction check and ported geometry/rendering cases are still required.

## Development status

No cloud deployment, GitHub repository, or release publication is configured. The local Git repository is the working source.

### What is implemented now

- SwiftUI app shell and AppKit canvas, without a browser or web view.
- Shapes, text, arrows, freehand strokes, images from imported files, selection, dragging, resizing, and undo.
- Folder-based collections, atomic autosave, stale-save rejection, and recovery copies.
- Frame presentations in a sheet.
- Built-in Codex chat with explicit proposal application and stale-proposal rejection.
- Stdio MCP tools `list_drawings`, `read_scene`, `create_scene`, and `patch_elements`.

### What is not complete

- Seeded line primitives are ported from Rough.js and checked against upstream coordinates. Rectangles, diamonds, lines, and arrows use those primitives. Ellipses and other rendering still use approximations; this is not complete Rough.js parity.
- Moving or resizing imported shapes does not yet reposition bound arrows or bound text.
- Rotation/alignment controls, complete font/layout fidelity, and all element-specific rendering are missing.
- Presentations are not yet fullscreen and have no PDF/PowerPoint export.
- MCP edits reload through the file store. They are not yet live editor commands with a shared transaction history, selection control, or rendered-scene feedback.
- There is no HTTP API or public link hosting yet.
- Chat requires the installed Codex CLI. Claude and other providers are not wired yet.

### Connect an MCP client

Build with `swift build --product grafix-mcp`, then use this server definition in your client's MCP configuration. Other collections can be selected by changing `--directory`.

```json
{
  "mcpServers": {
    "grafix": {
      "command": "/Users/uditagarwal19199/Workspace/grafix/.build/debug/grafix-mcp",
      "args": ["--directory", "/Users/uditagarwal19199/Documents/Grafix/Personal"]
    }
  }
}
```

Run the MCP transport and storage smoke check with `python3 scripts/mcp-smoke.py`. It uses a temporary drawing library, not your real drawings.

Native UI verification was attempted on 2026-10-18. The app bundle built and the macOS launch command succeeded, but Computer Use failed twice with `Sky Computer Use native pipe startup failed`. Canvas interactions, rendered appearance, and the complete in-app chat/apply flow remain unverified.

## UI reference

Use Excalidraw's existing design, not a new Grafix visual identity. The native UI follows its canvas-first layout and floating control panels. Primary references are [LayerUI](https://github.com/excalidraw/excalidraw/blob/master/packages/excalidraw/components/LayerUI.tsx) and [theme.scss](https://github.com/excalidraw/excalidraw/blob/master/packages/excalidraw/css/theme.scss). The light theme uses white islands, `#6965db` primary, `#e0dfff` selection backgrounds, and 8-point panel corners.

The user's open Excalidraw Plus tab could not be inspected: two integrated-browser snapshots and a direct page read timed out; the fallback in-app browser reported unavailable. Therefore this UI pass uses the public editor source, not a verified reproduction of the private Plus workspace.
