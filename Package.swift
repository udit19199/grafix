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
  products: [
    .executable(name: "Grafix", targets: ["GrafixApp"]),
    .executable(name: "grafix-mcp", targets: ["GrafixMCP"]),
    .executable(name: "grafix-dev", targets: ["GrafixDev"]),
  ],
  targets: [
    .target(name: "GrafixCore", resources: [.copy("Resources/Fonts")]),
    .target(name: "GrafixRender", dependencies: ["GrafixCore"]),
    .target(name: "GrafixPort"),
    .executableTarget(
      name: "GrafixApp",
      dependencies: ["GrafixCore", "GrafixRender", "GrafixPort"],
      exclude: ["Resources/AppIcon.icns"]
    ),
    .executableTarget(name: "GrafixMCP", dependencies: ["GrafixCore", "GrafixRender"]),
    // Developer tool: render scenes to PNG, run benchmarks (see AGENTS.md).
    .executableTarget(name: "GrafixDev", dependencies: ["GrafixCore", "GrafixRender"]),
  ]
)
