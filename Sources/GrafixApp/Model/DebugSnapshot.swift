import AppKit

/// Headless self-check for agents: with GRAFIX_SNAPSHOT=/path.png the app
/// captures its own key window after GRAFIX_SNAPSHOT_DELAY seconds (default 2)
/// and quits. GRAFIX_SNAPSHOT_SCRIPT may name actions to run first
/// (comma-separated: "select-all", "tool:rectangle", "slides", "present", "zoom-fit").
@MainActor
enum DebugSnapshot {
  static func scheduleIfRequested(model: AppModel) {
    let env = ProcessInfo.processInfo.environment
    guard let path = env["GRAFIX_SNAPSHOT"] else { return }
    let delay = Double(env["GRAFIX_SNAPSHOT_DELAY"] ?? "") ?? 2
    let raw = env["GRAFIX_SNAPSHOT_SCRIPT"] ?? ""
    // Steps are separated by ";" (or "," when the script has no ";").
    let script = raw.split(separator: raw.contains(";") ? ";" : ",").map { String($0).trimmingCharacters(in: .whitespaces) }
    for (i, step) in script.enumerated() {
      DispatchQueue.main.asyncAfter(deadline: .now() + 1 + Double(i) * 0.15) { run(step, model: model) }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
      capture(to: path)
      NSApp.terminate(nil)
    }
  }

  static func run(_ step: String, model: AppModel) {
    let doc = model.document
    switch step {
    case "select-all": doc.selectAll()
    case "dark": break  // dark-only now; kept so old scripts still parse
    case "slides": model.rightPanel = "slides"
    case "library": model.rightPanel = "library"
    case "present": model.presenting = true
    case "zoom-fit": doc.zoomToFitAll()
    case "help": model.showHelp = true
    case "chat": model.showChat = true
    case "no-sidebar": model.showWorkspace = false
    case "next-slide": NotificationCenter.default.post(name: .grafixDebugKey, object: 124)
    case "add-slide": doc.addSlide()
    case "focus-slide": if let f = doc.scene.slideFrames.first { doc.focusSlide(f.id) }
    case "notes": NotificationCenter.default.post(name: .grafixDebugKey, object: -1)
    default:
      if step.hasPrefix("tool:"), let t = Tool(rawValue: String(step.dropFirst(5))) { doc.setTool(t) }
      if step.hasPrefix("select:") { doc.select([String(step.dropFirst(7))]) }
      if step.hasPrefix("size:") {  // "size:1400x900" resizes the window (chrome checks)
        let parts = step.dropFirst(5).split(separator: "x").compactMap { Double($0) }
        if parts.count == 2, let w = NSApp.windows.first(where: { $0.isVisible }) { w.setContentSize(NSSize(width: parts[0], height: parts[1])) }
      }
      if step.hasPrefix("style:") { DebugChrome.run(String(step.dropFirst(6)), doc: doc) }
      DebugInteraction.run(step)
    }
  }

  static func capture(to path: String) {
    guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
      let view = window.contentView?.superview ?? window.contentView, let layer = view.layer
    else { return }
    let scale = window.backingScaleFactor
    let size = view.bounds.size
    guard let ctx = CGContext(
      data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8,
      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return }
    ctx.scaleBy(x: scale, y: scale)
    if view.isFlipped || layer.isGeometryFlipped {
      ctx.translateBy(x: 0, y: size.height)
      ctx.scaleBy(x: 1, y: -1)
    }
    layer.render(in: ctx)
    guard let image = ctx.makeImage() else { return }
    try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
  }
}

extension Notification.Name {
  /// Debug: simulate a key press in the presentation (object: key code; -1 = N).
  static let grafixDebugKey = Notification.Name("grafixDebugKey")
}
