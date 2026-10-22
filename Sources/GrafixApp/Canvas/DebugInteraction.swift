import AppKit

/// Synthetic input for headless interaction tests (used by DebugSnapshot).
/// Steps (view coordinates in points, origin top-left):
///   draw:<tool>:x1,y1,x2,y2   select tool and drag
///   drag:x1,y1,x2,y2          drag with the current tool
///   click:x,y  dclick:x,y  rclick-skip
///   type:<text>               type into the focused text editor
///   key:escape|return|delete
@MainActor
enum DebugInteraction {
  static func run(_ step: String) {
    guard let canvas = CanvasView.current else { return }
    let parts = step.split(separator: ":", maxSplits: 2).map(String.init)
    func nums(_ s: String) -> [CGFloat] { s.split(separator: ",").compactMap { Double($0).map { CGFloat($0) } } }
    switch parts.first {
    case "image" where parts.count >= 2:
      // image:/path/to/file.png — inserted centred at view point (400, 400)
      let path = parts.dropFirst().joined(separator: ":")
      if let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
        canvas.document.insertImage(data: data, mimeType: "image/png", at: canvas.document.sceneCoordinates(CGPoint(x: 400, y: 400)))
      }
    case "cropdrag" where parts.count == 2:
      // Drag the top-left crop handle of the image being cropped by dx,dy (view points).
      let n = nums(parts[1])
      if n.count == 2, let id = canvas.cropState?.id, let e = canvas.document.scene.element(id) {
        let a = canvas.document.screenCoordinates(CGPoint(x: e.x, y: e.y))
        drag(canvas, from: a, to: CGPoint(x: a.x + n[0], y: a.y + n[1]))
      }
    case "undo": canvas.document.undo()
    case "redo": canvas.document.redo()
    case "style" where parts.count == 3:
      // style:arrowType:elbow, style:backgroundColor:#a5d8ff, style:fillStyle:solid
      switch parts[1] {
      case "arrowType": canvas.document.style.arrowType = parts[2]
      case "backgroundColor": canvas.document.style.backgroundColor = parts[2]
      case "fillStyle": canvas.document.style.fillStyle = parts[2]
      case "strokeColor": canvas.document.style.strokeColor = parts[2]
      default: break
      }
    case "draw" where parts.count == 3:
      if let tool = Tool(rawValue: parts[1]) { canvas.document.setTool(tool) }
      let n = nums(parts[2])
      if n.count == 4 { drag(canvas, from: CGPoint(x: n[0], y: n[1]), to: CGPoint(x: n[2], y: n[3])) }
    case "drag" where parts.count == 2:
      let n = nums(parts[1])
      if n.count == 4 { drag(canvas, from: CGPoint(x: n[0], y: n[1]), to: CGPoint(x: n[2], y: n[3])) }
    case "click" where parts.count == 2:
      let n = nums(parts[1])
      if n.count == 2 { click(canvas, CGPoint(x: n[0], y: n[1]), count: 1) }
    case "dclick" where parts.count == 2:
      let n = nums(parts[1])
      if n.count == 2 {
        click(canvas, CGPoint(x: n[0], y: n[1]), count: 1)
        click(canvas, CGPoint(x: n[0], y: n[1]), count: 2)
      }
    case "type" where parts.count >= 2:
      let text = parts.dropFirst().joined(separator: ":")
      canvas.textEditor?.textView.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
    case "key" where parts.count == 2:
      let codes: [String: UInt16] = ["escape": 53, "return": 36, "delete": 51]
      if let code = codes[parts[1]], let e = keyEvent(canvas, code) {
        if let editor = canvas.textEditor, parts[1] == "escape" { editor.commit() } else { canvas.keyDown(with: e) }
      }
    default:
      break
    }
  }

  static func mouse(_ canvas: CanvasView, _ type: NSEvent.EventType, _ p: CGPoint, count: Int = 1) -> NSEvent? {
    let w = canvas.convert(p, to: nil)
    return NSEvent.mouseEvent(
      with: type, location: w, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
      windowNumber: canvas.window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: count, pressure: 1)
  }

  static func click(_ canvas: CanvasView, _ p: CGPoint, count: Int) {
    if let d = mouse(canvas, .leftMouseDown, p, count: count) { canvas.mouseDown(with: d) }
    if let u = mouse(canvas, .leftMouseUp, p, count: count) { canvas.mouseUp(with: u) }
  }

  static func drag(_ canvas: CanvasView, from a: CGPoint, to b: CGPoint) {
    if let d = mouse(canvas, .leftMouseDown, a) { canvas.mouseDown(with: d) }
    for i in 1...12 {
      let t = CGFloat(i) / 12
      let p = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
      if let e = mouse(canvas, .leftMouseDragged, p) { canvas.mouseDragged(with: e) }
    }
    if let u = mouse(canvas, .leftMouseUp, b) { canvas.mouseUp(with: u) }
  }

  static func keyEvent(_ canvas: CanvasView, _ code: UInt16) -> NSEvent? {
    NSEvent.keyEvent(
      with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
      windowNumber: canvas.window?.windowNumber ?? 0, context: nil, characters: "", charactersIgnoringModifiers: "",
      isARepeat: false, keyCode: code)
  }
}
