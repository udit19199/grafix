import Foundation
import GrafixCore
import GrafixRender

// grafix-mcp: stdio MCP server, plus a `render` helper for agents and tests.
//
//   grafix-mcp [--root PATH]                       serve MCP on stdin/stdout
//   grafix-mcp [--root PATH] render <sceneId|file.excalidraw> <out.png> [--frame ID] [--dark]

/// Removes `--root PATH` from the arguments and returns the workspace.
func parseWorkspace(_ args: inout [String]) -> Workspace {
  if let i = args.firstIndex(of: "--root"), i + 1 < args.count {
    let path = NSString(string: args[i + 1]).expandingTildeInPath
    args.removeSubrange(i...(i + 1))
    return Workspace(root: URL(fileURLWithPath: path, isDirectory: true))
  }
  return Workspace()
}

/// `render` subcommand. Returns the process exit code.
func runRender(_ args: [String], workspace: Workspace) -> Int32 {
  var rest = args
  var frame: String?
  var dark = false
  if let i = rest.firstIndex(of: "--frame"), i + 1 < rest.count {
    frame = rest[i + 1]
    rest.removeSubrange(i...(i + 1))
  }
  if let i = rest.firstIndex(of: "--dark") {
    dark = true
    rest.remove(at: i)
  }
  guard rest.count == 2 else {
    log("usage: grafix-mcp render <sceneId|path.excalidraw> <out.png> [--frame ID] [--dark]")
    return 2
  }
  do {
    let scene: Scene
    if rest[0].hasSuffix(".excalidraw"), FileManager.default.fileExists(atPath: rest[0]) {
      scene = try Scene(data: Data(contentsOf: URL(fileURLWithPath: rest[0])))
    } else {
      scene = try workspace.loadScene(rest[0])
    }
    guard let png = renderPNG(scene, frameID: frame, maxWidth: 1280, padding: 20, dark: dark) else {
      log("nothing to render")
      return 1
    }
    try png.write(to: URL(fileURLWithPath: rest[1]))
    print("wrote \(rest[1])")
    return 0
  } catch {
    log("error: \(error.localizedDescription)")
    return 1
  }
}

var arguments = Array(CommandLine.arguments.dropFirst())
let workspace = parseWorkspace(&arguments)
if arguments.first == "render" {
  exit(runRender(Array(arguments.dropFirst()), workspace: workspace))
}
log("grafix-mcp serving workspace \(workspace.root.path)")
Server(workspace: workspace).serve()
