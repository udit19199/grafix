# Grafix — guide for coding agents

Grafix is a native macOS (Swift 6, AppKit + SwiftUI, macOS 14+) replacement for Excalidraw+,
for one user, without collaboration. It must look and behave like Excalidraw. Files are plain
`.excalidraw` JSON, so drawings open in excalidraw.com and vice versa.

**Rule zero: when unsure how something should behave, read Excalidraw's source and copy it.**
The repo is cloned at `~/Workspace/oss/excalidraw`, at the commit the port follows. If it is
missing, clone `https://github.com/excalidraw/excalidraw` there. Look in
`packages/element/src` for element logic and `packages/excalidraw/components` for UI.

## Module map

| Module | What lives there | Depends on |
| --- | --- | --- |
| `Sources/GrafixCore` | Scene model, JSON coding, geometry, text layout, fonts, edits, workspace files, agent edit API. No UI. | Foundation, CoreGraphics, CoreText |
| `Sources/GrafixRender` | Rough.js port, perfect-freehand port, shape generation (`shape.ts` port), CoreGraphics rendering, PNG/PDF export. No UI. | GrafixCore |
| `Sources/GrafixPort` | Data generated from the Excalidraw repo: 205 icons, palette, theme tokens, strings, shortcuts, the help dialog. Regenerate with `scripts/port/*.mjs`. | SwiftUI |
| `Sources/GrafixApp` | The app: `Model/` (document, actions, export), `Canvas/` (NSView canvas, input, overlay, text editing), `UI/` (SwiftUI panels). | all |
| `Sources/GrafixMCP` | `grafix-mcp`, a stdio MCP server whose tools mirror the Excalidraw+ MCP. | Core, Render |
| `Sources/GrafixDev` | `grafix-dev`: render a scene to PNG, benchmark, generate stress scenes. | Core, Render |

### Where to change what

- **Element fields and JSON:** `GrafixCore/Model/Element.swift` and `ElementCoding.swift`. A new field must be added to `modelledKeys`, `init(json:)` and `json`.
- **What an element looks like:** `GrafixRender/ShapeGenerator.swift` (port of `shape.ts`) and `ElementRenderer.swift` (text, images, frames).
- **Edits:** `GrafixCore/Edit/Mutations.swift` covers move, delete, duplicate, group, z-order, align and frames. `Binding.swift` covers arrows bound to shapes. `Text.swift` covers label layout.
- **Agent API:** `GrafixCore/Agent/EditOps.swift` (`Scene.apply(EditRequest)`) and `GrafixMCP/*Tools.swift`.
- **Slides:** `GrafixCore/Model/Presentation.swift`. Slide order and notes go in frame `customData.slidesOrder` / `customData.presenterNotes`, in the same format as Excalidraw+.
- **Canvas input:** `GrafixApp/Canvas/CanvasPointer.swift` (pointer state machine), `CanvasTransform.swift` (resize and rotate), `CanvasView.swift` (keys, scroll, zoom), `TextEditorOverlay.swift`.
- **Selection UI and handles:** `GrafixApp/Canvas/CanvasOverlay.swift`.
- **Menus and shortcuts:** `GrafixApp/AppCommands.swift` (Command-key shortcuts) and `CanvasView.handleKey` (plain keys).
- **Panels:** one file each in `GrafixApp/UI/`. `EditorRootView.swift` decides the layout.

## Invariants (break these and things go subtly wrong)

1. **Every change to an element bumps its version.** Use `element.bump()`, or `scene.update(id) { … }`, which bumps for you. Caches, merging of agent edits and undo all depend on it.
2. **App edits go through `EditorDocument`.** Use `commit { scene in … }` for one undo step, or `beginInteraction` / `updateInteraction` / `endInteraction` for a drag. Never assign to `document.scene` directly.
3. **Labels are separate text elements.** The text has `containerId`, and the container lists it in `boundElements` with type `"text"`. After changing a container's size or text, call `scene.layoutLabel(of: containerID)`.
4. **Arrows bound to shapes:** the arrow has `startBinding` / `endBinding`, and the shape lists the arrow in `boundElements`. After moving or resizing shapes, call `scene.updateBoundArrows(of:)`. `Scene.move` already does this.
5. **`points[0]` of a line or arrow is always (0, 0).** Use `setGlobalPoints` to rewrite points.
6. **Deletion is soft** (`isDeleted = true`). Rendering skips deleted elements and saving keeps them, as Excalidraw does.
7. **Array order is z-order.** `index` is a fractional key that `Scene.encoded()` re-syncs. Frames sit below their children.
8. **Main thread:** `EditorDocument` and the canvas are `@MainActor`. Rendering into the static layer happens off the main thread on a copy of the scene, which is a value type.
9. **Never write to `~/Documents/Grafix` in experiments or scripts.** Set `GRAFIX_ROOT` to a temporary directory.

## Performance model

- The static scene renders off the main thread into a bitmap (`Canvas/StaticSceneLayer.swift`). Pan and zoom transform the old bitmap instantly while a new one renders.
- Elements being dragged, resized or drawn are hidden from the static layer and drawn every frame by the overlay (`liveIDs`). A drag therefore costs only a few elements per frame.
- `RenderCache` caches Rough.js geometry per element, keyed by shape-relevant fields only. Moving an element never regenerates its shape.
- SwiftUI panels observe `document.revision`, never the scene. Keep SwiftUI `body` cheap.
- Benchmark: `swift run -c release grafix-dev stress /tmp/s.excalidraw 5000 && swift run -c release grafix-dev bench /tmp/s.excalidraw`.

## Checks

```sh
swift build                       # everything
python3 scripts/mcp-smoke.py      # MCP end-to-end against a temp workspace
./scripts/build-app.sh            # .build/Grafix.app (release) with grafix-mcp inside
```

**There is no test target, on purpose.** Agents maintain this repo, and tests written and rewritten
by the same agents just mirror the code. Do not add a `Tests/` directory or a test target, and do
not claim `swift test` passes. Verify with `swift build`, `scripts/mcp-smoke.py` and the headless
snapshot below. The owner will add a few hand-written tests later; keep those and don't rewrite them.

Rendering parity: `scripts/port/rough-golden.mjs` and `freehand-golden.mjs` generate reference
output from the JS libraries. Compare ours against it by hand when you touch the Rough.js or
perfect-freehand ports.

### Seeing the app without screen control

The app can screenshot itself headlessly and run scripted input
(`GrafixApp/Model/DebugSnapshot.swift`, `Canvas/DebugInteraction.swift`):

```sh
GRAFIX_ROOT=/tmp/ws GRAFIX_SNAPSHOT=/tmp/shot.png GRAFIX_SNAPSHOT_DELAY=5 \
GRAFIX_SNAPSHOT_SCRIPT="no-sidebar;draw:rectangle:200,300,400,420;dclick:300,360;type:Hello;key:escape" \
.build/debug/Grafix
```

Steps are separated by `;`. Available steps: `select-all`, `select:<id>`, `tool:<tool>`, `dark`,
`slides`, `present`, `help`, `chat`, `no-sidebar`, `zoom-fit`, `draw:<tool>:x1,y1,x2,y2`,
`drag:x1,y1,x2,y2`, `click:x,y`, `dclick:x,y`, `type:<text>`, `key:escape|return|delete`.
Coordinates are view points. Afterwards, open the PNG and read the saved `.excalidraw` file to
check the result.

## Recipes

- **Port an Excalidraw behaviour:** find it in `~/Workspace/oss/excalidraw`, port it line by line into the matching file above, and cite the source function in a doc comment.
- **Add a tool:** add a case to `Tool` (in `EditorDocument.swift`), handle it in `CanvasView.mouseDown` and its helpers in `CanvasPointer.swift`, then add it to the toolbar.
- **Add an MCP tool:** add the tool to `GrafixMCP/*Tools.swift`, with a schema, a description that includes an example, and errors that say what to do next. Extend `scripts/mcp-smoke.py`.
- **Add an element property to the UI:** read and write it in `UI/PropertiesPanel.swift` with `document.setStyle(…)`.
- **Regenerate icons, palette or strings** after updating the Excalidraw repo: run `node scripts/port/extract-icons.mjs`, `node scripts/port/extract-ui.mjs`, and `uv run --with fonttools --with brotli scripts/port/merge-fonts.py` for fonts.

## Storage layout (also what agents edit)

```
~/Documents/Grafix/               (override with GRAFIX_ROOT)
  <Collection>/<Scene>.excalidraw
  .grafix/editor.json             open scene id, selection, viewport (written by the app)
  .grafix/lock                    flock taken by every writer (app autosave, MCP)
```

The app autosaves 350 ms after an edit. It polls the open file every 0.5 s and merges external
edits by element version, so agents and the app can edit the same scene at the same time.
