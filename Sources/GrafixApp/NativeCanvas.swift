import AppKit
import GrafixCore
import SwiftUI

struct NativeCanvas: NSViewRepresentable {
  @ObservedObject var model: EditorModel
  var presentation = false
  func makeNSView(context: Context) -> DrawingView {
    let view = DrawingView()
    view.model = model
    return view
  }
  func updateNSView(_ view: DrawingView, context: Context) {
    view.model = model
    view.presentation = presentation
    view.zoom = model.zoom
    view.needsDisplay = true
  }
}

@MainActor final class DrawingView: NSView {
  weak var model: EditorModel?
  var presentation = false
  var start = CGPoint.zero
  var original: SceneDocument?
  var draft: [String: JSONValue]?
  var resizing = false
  var zoom: CGFloat = 1
  var offset = CGPoint(x: 60, y: 60)
  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { true }
  func number(_ e: [String: JSONValue], _ key: String, _ fallback: Double = 0) -> CGFloat {
    CGFloat(e[key]?.doubleValue ?? fallback)
  }
  func rect(_ e: [String: JSONValue]) -> CGRect {
    CGRect(
      x: number(e, "x"), y: number(e, "y"), width: max(1, number(e, "width")),
      height: max(1, number(e, "height")))
  }
  func world(_ event: NSEvent) -> CGPoint {
    let p = convert(event.locationInWindow, from: nil)
    return CGPoint(x: (p.x - offset.x) / zoom, y: (p.y - offset.y) / zoom)
  }
  override func draw(_ dirtyRect: NSRect) {
    NSColor.white.setFill()
    bounds.fill()
    guard let model, let ctx = NSGraphicsContext.current?.cgContext else { return }
    ctx.saveGState()
    if presentation, !model.frames.isEmpty {
      let frame = rect(model.frames[min(model.slide, model.frames.count - 1)])
      let scale = min(bounds.width / frame.width, bounds.height / frame.height) * 0.9
      ctx.translateBy(
        x: (bounds.width - frame.width * scale) / 2, y: (bounds.height - frame.height * scale) / 2)
      ctx.scaleBy(x: scale, y: scale)
      ctx.translateBy(x: -frame.minX, y: -frame.minY)
    } else {
      ctx.translateBy(x: offset.x, y: offset.y)
      ctx.scaleBy(x: zoom, y: zoom)
    }
    for element in model.scene.elements + (draft.map { [$0] } ?? [])
    where element["isDeleted"]?.boolValue != true { drawElement(element, context: ctx) }
    if !presentation, let selected = model.selected,
      let e = model.scene.elements.first(where: { $0["id"]?.stringValue == selected })
    {
      ctx.setStrokeColor(NSColor.systemBlue.cgColor)
      ctx.setLineDash(phase: 0, lengths: [5, 3])
      ctx.stroke(rect(e).insetBy(dx: -5, dy: -5))
      ctx.setLineDash(phase: 0, lengths: [])
      ctx.setFillColor(NSColor.systemBlue.cgColor)
      let r = rect(e)
      ctx.fill(CGRect(x: r.maxX - 4, y: r.maxY - 4, width: 8, height: 8))
    }
    ctx.restoreGState()
  }
  func drawElement(_ e: [String: JSONValue], context ctx: CGContext) {
    let type = e["type"]?.stringValue ?? "rectangle"
    let r = rect(e)
    ctx.saveGState()
    defer { ctx.restoreGState() }
    ctx.translateBy(x: r.midX, y: r.midY)
    ctx.rotate(by: number(e, "angle"))
    ctx.translateBy(x: -r.midX, y: -r.midY)
    let color = NSColor(hex: e["strokeColor"]?.stringValue ?? "#1e1e1e")
    ctx.setStrokeColor(color.cgColor)
    ctx.setLineWidth(max(1, number(e, "strokeWidth", 2)))
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setAlpha(number(e, "opacity", 100) / 100)
    if type == "text" {
      let style = NSMutableParagraphStyle()
      style.alignment = e["textAlign"]?.stringValue == "center" ? .center : .left
      let font =
        NSFont(name: "Chalkboard", size: number(e, "fontSize", 24))
        ?? .systemFont(ofSize: number(e, "fontSize", 24))
      (e["text"]?.stringValue ?? "Text").draw(
        in: r, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
      return
    }
    let points = e["points"]?.arrayValue?.compactMap { item -> CGPoint? in
      guard let a = item.arrayValue, a.count >= 2 else { return nil }
      return CGPoint(
        x: r.minX + CGFloat(a[0].doubleValue ?? 0), y: r.minY + CGFloat(a[1].doubleValue ?? 0))
    }
    let path = CGMutablePath()
    switch type {
    case "ellipse": path.addEllipse(in: r)
    case "diamond":
      path.move(to: CGPoint(x: r.midX, y: r.minY))
      path.addLines(between: [
        CGPoint(x: r.maxX, y: r.midY), CGPoint(x: r.midX, y: r.maxY), CGPoint(x: r.minX, y: r.midY),
      ])
      path.closeSubpath()
    case "line", "arrow", "freedraw":
      if let points, !points.isEmpty {
        path.addLines(between: points)
      } else {
        path.move(to: r.origin)
        path.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
      }
    case "frame":
      ctx.setLineDash(phase: 0, lengths: [8, 5])
      path.addRect(r)
    case "image":
      if let fileID = e["fileId"]?.stringValue,
        let encoded = model?.scene.root["files"]?.objectValue?[fileID]?.objectValue?["dataURL"]?
          .stringValue, let comma = encoded.firstIndex(of: ","),
        let data = Data(base64Encoded: String(encoded[encoded.index(after: comma)...])),
        let image = NSImage(data: data)
      {
        image.draw(
          in: r, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        return
      }
      ctx.setFillColor(NSColor.gray.withAlphaComponent(0.1).cgColor)
      ctx.fill(r)
      path.addRect(r)
      "Image (preserved)".draw(
        in: r.insetBy(dx: 8, dy: 8),
        withAttributes: [
          .font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.secondaryLabelColor,
        ])
    default: path.addRect(r)
    }
    if let fill = e["backgroundColor"]?.stringValue, fill != "transparent",
      !["line", "arrow", "freedraw"].contains(type)
    {
      ctx.addPath(path)
      ctx.setFillColor(NSColor(hex: fill).cgColor)
      ctx.fillPath()
    }
    let roughness = Double(number(e, "roughness", 1))
    var vertices: [CGPoint] = []
    switch type {
    case "rectangle":
      vertices = [
        r.origin, CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.maxX, y: r.maxY),
        CGPoint(x: r.minX, y: r.maxY), r.origin,
      ]
    case "diamond":
      vertices = [
        CGPoint(x: r.midX, y: r.minY), CGPoint(x: r.maxX, y: r.midY), CGPoint(x: r.midX, y: r.maxY),
        CGPoint(x: r.minX, y: r.midY), CGPoint(x: r.midX, y: r.minY),
      ]
    case "line", "arrow": vertices = points ?? [r.origin, CGPoint(x: r.maxX, y: r.maxY)]
    default: break
    }
    if roughness > 0, vertices.count > 1 {
      let rawSeed = e["seed"]?.doubleValue ?? 1
      let seed = UInt32(
        truncatingIfNeeded: Int64(
          rawSeed.isFinite && abs(rawSeed) < Double(Int64.max) ? rawSeed : 1))
      var generator = RoughLineGenerator(options: .init(seed: seed, roughness: roughness))
      let sketch = CGMutablePath()
      for index in 1..<vertices.count {
        let a = vertices[index - 1]
        let b = vertices[index]
        for operation in generator.line(x1: a.x, y1: a.y, x2: b.x, y2: b.y) {
          let data = operation.data
          switch operation.kind {
          case .move: sketch.move(to: CGPoint(x: data[0], y: data[1]))
          case .bcurveTo:
            sketch.addCurve(
              to: CGPoint(x: data[4], y: data[5]), control1: CGPoint(x: data[0], y: data[1]),
              control2: CGPoint(x: data[2], y: data[3]))
          }
        }
      }
      ctx.addPath(sketch)
      ctx.strokePath()
    } else {
      ctx.addPath(path)
      ctx.strokePath()
    }
    // Ellipse/freehand sketch rendering remains approximate until their Rough.js primitives are ported.
    if roughness > 0, vertices.isEmpty, type != "frame" {
      let seed = number(e, "seed", 1)
      let shift = sin(seed) * 0.85
      ctx.translateBy(x: shift, y: cos(seed) * 0.85)
      ctx.setAlpha(0.55)
      ctx.setLineWidth(max(0.7, number(e, "strokeWidth", 2) * 0.65))
      ctx.addPath(path)
      ctx.strokePath()
    }
    if type == "arrow" {
      let ps = points ?? [r.origin, CGPoint(x: r.maxX, y: r.maxY)]
      if ps.count >= 2 {
        let a = ps[ps.count - 2]
        let b = ps.last!
        let angle = atan2(b.y - a.y, b.x - a.x)
        ctx.move(to: CGPoint(x: b.x - 14 * cos(angle - 0.45), y: b.y - 14 * sin(angle - 0.45)))
        ctx.addLine(to: b)
        ctx.addLine(to: CGPoint(x: b.x - 14 * cos(angle + 0.45), y: b.y - 14 * sin(angle + 0.45)))
        ctx.strokePath()
      }
    }
  }
  override func mouseDown(with event: NSEvent) {
    guard !presentation, let model else { return }
    window?.makeFirstResponder(self)
    start = world(event)
    original = model.scene
    model.interacting = true
    resizing = false
    if model.tool == "selection" {
      if let id = model.selected,
        let e = model.scene.elements.first(where: { $0["id"]?.stringValue == id }),
        CGRect(x: rect(e).maxX - 10, y: rect(e).maxY - 10, width: 20, height: 20).contains(start)
      {
        resizing = true
        return
      }
      model.selected =
        model.scene.elements.reversed().first(where: {
          $0["isDeleted"]?.boolValue != true && rect($0).insetBy(dx: -8, dy: -8).contains(start)
        })?["id"]?.stringValue
      if let id = model.selected,
        let selected = model.scene.elements.first(where: { $0["id"]?.stringValue == id })
      {
        model.strokeColor = selected["strokeColor"]?.stringValue ?? "#1e1e1e"
        model.backgroundColor = selected["backgroundColor"]?.stringValue ?? "transparent"
        model.strokeWidth = selected["strokeWidth"]?.doubleValue ?? 2
        model.roughness = selected["roughness"]?.doubleValue ?? 1
        model.opacity = selected["opacity"]?.doubleValue ?? 100
      }
      needsDisplay = true
      return
    }
    if model.tool == "text" {
      defer {
        model.interacting = false
        original = nil
      }
      let alert = NSAlert()
      alert.messageText = "Add text"
      let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 60))
      alert.accessoryView = field
      alert.addButton(withTitle: "Add")
      alert.addButton(withTitle: "Cancel")
      if alert.runModal() == .alertFirstButtonReturn {
        var e = element("text", at: start)
        e["text"] = .string(field.stringValue)
        e["originalText"] = .string(field.stringValue)
        e["width"] = .number(Double(max(100, field.stringValue.count * 15)))
        e["height"] = .number(40)
        model.change { $0.elements.append(e) }
      }
      return
    }
    draft = element(model.tool, at: start)
  }
  func element(_ type: String, at p: CGPoint) -> [String: JSONValue] {
    [
      "id": .string(UUID().uuidString), "type": .string(type), "x": .number(p.x), "y": .number(p.y),
      "width": .number(1), "height": .number(1), "angle": .number(0),
      "strokeColor": .string(model?.strokeColor ?? "#1e1e1e"),
      "backgroundColor": .string(model?.backgroundColor ?? "transparent"),
      "fillStyle": .string("hachure"), "strokeWidth": .number(model?.strokeWidth ?? 2),
      "strokeStyle": .string("solid"),
      "roughness": .number(model?.roughness ?? 1), "opacity": .number(model?.opacity ?? 100),
      "seed": .number(Double(Int.random(in: 1...1_000_000))), "version": .number(1),
      "versionNonce": .number(1), "isDeleted": .bool(false), "boundElements": .null,
      "updated": .number(Date().timeIntervalSince1970 * 1000), "link": .null,
      "locked": .bool(false), "fontSize": .number(24), "fontFamily": .number(1),
      "textAlign": .string("left"), "verticalAlign": .string("top"), "containerId": .null,
      "lineHeight": .number(1.25),
    ]
  }
  override func mouseDragged(with event: NSEvent) {
    guard let model, !presentation else { return }
    let p = world(event)
    if model.tool == "selection", let id = model.selected, let original {
      var elements = original.elements
      if let i = elements.firstIndex(where: { $0["id"]?.stringValue == id }) {
        if resizing {
          elements[i]["width"] = .number(
            Double(max(10, number(elements[i], "width") + p.x - start.x)))
          elements[i]["height"] = .number(
            Double(max(10, number(elements[i], "height") + p.y - start.y)))
        } else {
          elements[i]["x"] = .number(Double(number(elements[i], "x") + p.x - start.x))
          elements[i]["y"] = .number(Double(number(elements[i], "y") + p.y - start.y))
        }
        model.scene.elements = elements
      }
      return
    }
    guard var d = draft else { return }
    let type = d["type"]?.stringValue
    if ["arrow", "line", "freedraw"].contains(type) {
      var ps = d["points"]?.arrayValue ?? [.array([.number(0), .number(0)])]
      let point: JSONValue = .array([.number(p.x - start.x), .number(p.y - start.y)])
      if type == "freedraw" { ps.append(point) } else { ps = [ps[0], point] }
      d["points"] = .array(ps)
      d["width"] = .number(abs(p.x - start.x))
      d["height"] = .number(abs(p.y - start.y))
      if type == "arrow" {
        d["endArrowhead"] = .string("arrow")
        d["startArrowhead"] = .null
      }
    } else {
      d["x"] = .number(min(start.x, p.x))
      d["y"] = .number(min(start.y, p.y))
      d["width"] = .number(abs(p.x - start.x))
      d["height"] = .number(abs(p.y - start.y))
    }
    draft = d
    needsDisplay = true
  }
  override func mouseUp(with event: NSEvent) {
    guard let model, !presentation else { return }
    if let draft {
      model.change { $0.elements.append(draft) }
      self.draft = nil
    } else if let original, (try? original.encoded()) != (try? model.scene.encoded()) {
      model.history.append(original)
      model.future = []
      model.save()
    }
    original = nil
    model.interacting = false
    needsDisplay = true
  }
  override func scrollWheel(with event: NSEvent) {
    offset.x -= event.scrollingDeltaX
    offset.y -= event.scrollingDeltaY
    needsDisplay = true
  }
  override func magnify(with event: NSEvent) {
    zoom = min(5, max(0.15, zoom * (1 + event.magnification)))
    model?.zoom = zoom
    needsDisplay = true
  }
  override func keyDown(with event: NSEvent) {
    if event.keyCode == 53, model?.showingHelp == true {  // Escape closes the dialog.
      model?.showingHelp = false
      return
    }
    // "?" opens the shortcuts dialog. The web editor listens for it on the
    // canvas rather than as a menu key, and so does this app: a menu key
    // equivalent for a plain character would swallow it in text fields.
    if event.characters == "?", !event.modifierFlags.contains(.command) {
      model?.showingHelp.toggle()
      return
    }
    if event.keyCode == 51, let model, let id = model.selected {
      model.change { scene in
        var es = scene.elements
        if let i = es.firstIndex(where: { $0["id"]?.stringValue == id }) {
          es[i]["isDeleted"] = .bool(true)
        }
        scene.elements = es
      }
      model.selected = nil
    } else {
      super.keyDown(with: event)
    }
  }
}

extension NSColor {
  convenience init(hex: String) {
    var value: UInt64 = 0
    Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))).scanHexInt64(
      &value)
    self.init(
      calibratedRed: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255,
      blue: CGFloat(value & 255) / 255, alpha: 1)
  }
}
