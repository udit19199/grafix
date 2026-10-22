// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Grafix",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "Grafix", targets: ["GrafixApp"]),
    .executable(name: "grafix-mcp", targets: ["GrafixMCP"]),
  ],
  targets: [
    .target(name: "GrafixCore"),
    .target(name: "GrafixPort"),
    .executableTarget(
      name: "GrafixApp",
      dependencies: ["GrafixCore", "GrafixPort"]
    ),
    .executableTarget(name: "GrafixMCP", dependencies: ["GrafixCore"]),
    .testTarget(name: "GrafixCoreTests", dependencies: ["GrafixCore"]),
    .testTarget(name: "GrafixPortTests", dependencies: ["GrafixPort"]),
  ]
)
