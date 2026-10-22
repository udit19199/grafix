// swift-tools-version: 6.0
import PackageDescription

// Module map (see AGENTS.md):
//   GrafixCore   - scene model, geometry, text layout, workspace storage, agent edit ops. No UI.
//   GrafixRender - Rough.js / perfect-freehand ports and CoreGraphics scene rendering. No UI.
//   GrafixPort   - data extracted from the Excalidraw repo (icons, palette, strings, theme).
//   GrafixApp    - the macOS app (AppKit canvas + SwiftUI chrome).
//   GrafixMCP    - `grafix-mcp`, stdio MCP server for agents.
let package = Package(
  name: "Grafix",
  platforms: [.macOS(.v14)],
  products: [],
  targets: [
    .target(name: "GrafixCore", resources: [.copy("Resources/Fonts")]),
  ]
)
