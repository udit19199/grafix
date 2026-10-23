# Brief for agents building Grafix UI

Grafix is a native macOS (Swift 6, SwiftUI + AppKit, macOS 14) clone of Excalidraw / Excalidraw+, at
/Users/uditagarwal19199/Workspace/grafix. The goal is that it LOOKS AND FEELS EXACTLY LIKE EXCALIDRAW.
Excalidraw's source is at ~/Workspace/oss/excalidraw (packages/excalidraw/components/*.tsx + *.scss,
css/theme.scss, css/variables.module.scss). Read the matching component and its .scss before building:
copy sizes, paddings, radii, colours, fonts, hover/active states, shadows.

## Architecture you build against (read these files)
- Sources/GrafixApp/Model/EditorDocument.swift — the open scene. `doc.scene` (GrafixCore.Scene),
  `doc.revision` (observe this to react to scene changes), `doc.selection: Set<String>`,
  `doc.selectedElements`, `doc.singleSelection`, `doc.view` (tool, zoom, dark, grid, zen, viewMode,
  toolLocked...), `doc.style` (ItemStyle for new elements), `doc.setStyle(_:element:labels:)`,
  `doc.commit { scene in ... }` (one undo step), `doc.undo()/redo()`, `doc.canUndo/canRedo`,
  `doc.setTool(_:)`, zoom helpers.
- Sources/GrafixApp/Model/EditorActions.swift — actions (delete, duplicate, group, reorder, align,
  distribute, lock, flip, copy/paste, insertImage, zoomIn/Out/reset/fit...).
- Sources/GrafixApp/Model/AppModel.swift — per-window state: workspace collections/scenes, open/new/
  rename/move/trash scenes & collections, `showWorkspace`, `rightPanel` ("slides"), `showChat`,
  `showHelp`, `presenting`, `presentingSlide`.
- Sources/GrafixApp/Model/ExportActions.swift — PNG/PDF/.excalidraw export.
- Sources/GrafixApp/UI/EditorRootView.swift — window layout (who owns which panel). Don't restructure
  it; small additions are OK if you need them (tell the lead).
- GrafixCore (Sources/GrafixCore): Element, Scene, ItemStyle, Presentation (slides = frames,
  `scene.slides`, `addSlide`, `moveSlide`, `setSlideOrder`, element.presenterNotes / slidesOrder),
  Workspace. GrafixRender: `SceneRenderer.image(scene, frameID:scale:maxWidth:...)` for thumbnails,
  `RenderCache`, `CSSColor`.
- GrafixPort (Sources/GrafixPort): `PortIconView(name:size:color:)` draws Excalidraw icons by key
  (205 icons; keys listed in Sources/GrafixPort/Generated/PortIcons.swift, e.g. "rectangle",
  "fillhachure", "strokewidthbold", "edgeround", "arrowheadtriangle", "sendtoback", "hamburger",
  "trash", "zoomin", "undo", "present", "library"...), `PortMetrics.load(dark:)` (Excalidraw sizes and
  colours from theme.scss), `PortIsland` (the floating white panel with Excalidraw's shadow),
  `PortPalette.families` (colour palette), `PortStrings.text("key")` (Excalidraw's English copy),
  `PortTheme.color("token", dark:)` (CSS variables), `PortTools`, `PortShortcuts`, `PortHelpDialog`.
  Use these rather than hard-coding where they fit.

## Rules
- Only edit the files you are assigned. Other agents edit other UI files at the same time.
- Performance: views must not depend on `doc.scene` in hot paths. Read `doc.revision` to re-evaluate.
  Never do expensive work (rendering thumbnails) in `body` synchronously — cache, and render off-main.
- Dark mode: the app is dark-only. Always use the dark tokens and appearance; there is no theme toggle.
- Build ONLY with your own scratch path, e.g.
  `swift build --product Grafix --scratch-path /Users/uditagarwal19199/Workspace/grafix/.build-<yourname>`.
  If the build breaks in a file you don't own, wait a minute and retry (someone is mid-edit).
- Verify visually: the app can screenshot itself headlessly:
  ```
  GRAFIX_ROOT=<a temp workspace dir with a Collection/Scene.excalidraw> \
  GRAFIX_SNAPSHOT=/tmp/x.png GRAFIX_SNAPSHOT_DELAY=3 GRAFIX_SNAPSHOT_SCRIPT="select-all,slides" \
  /Users/uditagarwal19199/Workspace/grafix/.build-<yourname>/debug/Grafix
  ```
  (script steps in Sources/GrafixApp/Model/DebugSnapshot.swift; you may ADD steps there for your
  panel — append cases only). Then view the PNG with the Read tool and compare with Excalidraw.
  NEVER point GRAFIX_ROOT at ~/Documents/Grafix (the user's real drawings). A sample scene:
  Tests/GrafixRenderTests/Fixtures/scenes/plus-probe.excalidraw.
- Don't use computer-use / screen control. Don't commit.
- Code style: 2-space indent, small views, a doc comment per type naming the Excalidraw component it
  ports. Keep files under ~500 lines (split into a subfolder if needed).
