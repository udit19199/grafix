# Grafix

A native macOS whiteboard that looks and works like Excalidraw, and replaces Excalidraw+ for
single-user work. It is pure Swift (AppKit + SwiftUI) with no web view. Files are standard
`.excalidraw` JSON, so they open in excalidraw.com, and Excalidraw+ decks (frames with
`customData.slidesOrder`) present here as-is.

- **Excalidraw's look:** line-by-line ports of Rough.js 4.6.4 and perfect-freehand 1.2.0 (golden-tested against the JS libraries), Excalidraw's `shape.ts`, its fonts (Excalifont, Nunito, Lilita One, Comic Shanns, Virgil, Cascadia), palette, icons and theme tokens.
- **Editing:** every Excalidraw tool (selection, lasso, rectangle, diamond, ellipse, arrow, line, freedraw, text, image, eraser, frame, embed, laser, hand), labels in shapes and on arrows, arrows that bind to shapes, groups, alignment, z-order, lock, flip, copy and paste, styles, grid, zen and view mode, dark-only UI, links, and PNG/PDF/.excalidraw export.
- **Excalidraw+ features:** collections and scenes in a sidebar, presentations (one frame per slide, presenter notes, full-screen presenting with a laser pointer, PDF export) and multiple windows.
- **Built for AI:** a built-in chat runs Claude Code against Grafix's MCP server, so the agent edits the open scene live. `grafix-mcp` exposes tools modelled on the Excalidraw+ MCP to any agent. [AGENTS.md](AGENTS.md) explains the codebase to coding agents.

## Run

You need macOS 14 or later and Xcode 16 or a Swift 6 toolchain.

```sh
swift run Grafix
```

To build an app bundle that includes the MCP server:

```sh
./scripts/build-app.sh
open .build/Grafix.app
```

Drawings live in `~/Documents/Grafix/<Collection>/<Scene>.excalidraw`. Set `GRAFIX_ROOT` to use
another folder.

## Connect an agent (MCP)

```sh
swift build -c release --product grafix-mcp
```

```json
{
  "mcpServers": {
    "grafix": { "command": "/path/to/grafix/.build/release/grafix-mcp" }
  }
}
```

Tools include `list_collections`, `list_scenes`, `create_scene`, `get_scene_content`,
`search_scene_content`, `edit_scene_content` (add, update, delete and z-order, with tempIds,
labels and bindings), `create_slide`, `list_slides`, `update_slide`, `add_image`,
`take_screenshot`, `get_editor_state` (what the app has open and selected) and format guides.
Agent edits show up in the open app within half a second and can be undone with Cmd+Z.

## Develop

```sh
swift test                     # model, rendering golden tests, ported data
python3 scripts/mcp-smoke.py   # MCP end to end
swift run grafix-dev render scene.excalidraw out.png
```

See [AGENTS.md](AGENTS.md) for the architecture, invariants and recipes. See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for licences.
