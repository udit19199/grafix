import Foundation

/// Headless-snapshot hooks for the chrome: `GRAFIX_SNAPSHOT_SCRIPT=style:zen`
/// toggles view state, `GRAFIX_CHROME_OPEN=menu|extra|stroke|background|font|
/// start-arrowhead|end-arrowhead|export|bg-picker` opens a popover on launch.
@MainActor
enum DebugChrome {
  static var open: String? { ProcessInfo.processInfo.environment["GRAFIX_CHROME_OPEN"] }

  static func run(_ step: String, doc: EditorDocument) {
    switch step {
    case "zen": doc.view.zen = true
    case "view": doc.view.viewMode = true
    case "grid": doc.view.grid = true
    case "lock": doc.view.toolLocked = true
    default: break
    }
  }
}
