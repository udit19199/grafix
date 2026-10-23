import CoreGraphics
import Foundation
import GrafixCore
import GrafixRender

// grafix-dev: developer utilities.
//   grafix-dev render <file.excalidraw> <out.png> [--frame ID|--first-frame] [--dark] [--width N]
//   grafix-dev bench <file.excalidraw> [--frames N]   time full-scene renders
//   grafix-dev stress <out.excalidraw> <count>        write a large random scene

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data((message + "\n").utf8))
  exit(1)
}

var args = Array(CommandLine.arguments.dropFirst())
@MainActor func flag(_ name: String) -> Bool {
  if let i = args.firstIndex(of: name) {
    args.remove(at: i)
    return true
  }
  return false
}
@MainActor func option(_ name: String) -> String? {
  guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
  let value = args[i + 1]
  args.removeSubrange(i...(i + 1))
  return value
}

guard let command = args.first else { fail("usage: grafix-dev render|bench|stress ...") }
args.removeFirst()

switch command {
case "render":
  let dark = flag("--dark")
  let firstFrame = flag("--first-frame")
  let frame = option("--frame")
  let width = option("--width").flatMap(Double.init) ?? 1708
  guard args.count == 2 else { fail("usage: grafix-dev render <in> <out.png>") }
  let scene = try Scene(data: Data(contentsOf: URL(fileURLWithPath: args[0])))
  let frameID = frame ?? (firstFrame ? scene.slideFrames.first?.id : nil)
  if args[1].hasSuffix(".svg") {
    guard let svg = SVGExporter.svg(scene, frameID: frameID, padding: 20, dark: dark) else { fail("nothing to render") }
    try svg.write(toFile: args[1], atomically: true, encoding: .utf8)
  } else {
    guard let png = SceneRenderer.png(scene, frameID: frameID, maxWidth: width, padding: 20, dark: dark) else {
      fail("nothing to render")
    }
    try png.write(to: URL(fileURLWithPath: args[1]))
  }
  print("wrote \(args[1])")

case "bench":
  let frames = option("--frames").flatMap(Int.init) ?? 30
  guard args.count == 1 else { fail("usage: grafix-dev bench <in>") }
  let scene = try Scene(data: Data(contentsOf: URL(fileURLWithPath: args[0])))
  let bounds = SceneRenderer.exportBounds(scene, frameID: nil, padding: 0) ?? .zero
  let ctx = CGContext(
    data: nil, width: 2560, height: 1600, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  let cache = RenderCache()
  let zoom = min(2560 / max(bounds.width, 1), 1600 / max(bounds.height, 1))
  var options = SceneRenderer.Options()
  options.zoom = zoom
  options.viewport = bounds
  func frame() {
    ctx.saveGState()
    ctx.scaleBy(x: zoom, y: zoom)
    ctx.translateBy(x: -bounds.minX, y: -bounds.minY)
    SceneRenderer.draw(scene, in: ctx, cache: cache, options: options)
    ctx.restoreGState()
  }
  let cold = Date()
  frame()
  let coldMs = Date().timeIntervalSince(cold) * 1000
  let warm = Date()
  for _ in 0..<frames { frame() }
  let warmMs = Date().timeIntervalSince(warm) * 1000 / Double(frames)
  print(String(format: "%d elements: first frame %.1f ms, cached frame %.2f ms", scene.visibleElements.count, coldMs, warmMs))

case "bench-edit":
  // Times the edit paths a drag uses: move 20% of the scene 60 times.
  guard args.count == 1 else { fail("usage: grafix-dev bench-edit <in>") }
  var scene = try Scene(data: Data(contentsOf: URL(fileURLWithPath: args[0])))
  let ids = Set(scene.elements.prefix(scene.elements.count / 5).map(\.id))
  let start = Date()
  for i in 0..<60 { scene.move(ids, by: CGPoint(x: i % 2 == 0 ? 1 : -1, y: 0)) }
  let ms = Date().timeIntervalSince(start) * 1000 / 60
  print(String(format: "move %d of %d elements: %.2f ms per drag event", ids.count, scene.elements.count, ms))
  let p = CGPoint(x: 500, y: 500)
  let hitStart = Date()
  var hits = 0
  for _ in 0..<60 { for e in scene.elements.reversed() where e.hitTest(p, threshold: 10) { hits += 1; break } }
  print(String(format: "hit test sweep: %.2f ms per mouse move", Date().timeIntervalSince(hitStart) * 1000 / 60))

case "stress":
  guard args.count == 2, let count = Int(args[1]) else { fail("usage: grafix-dev stress <out> <count>") }
  var scene = Scene()
  let types: [ElementType] = [.rectangle, .ellipse, .diamond, .arrow, .line, .text, .freedraw]
  var style = ItemStyle()
  for i in 0..<count {
    let x = Double(i % 60) * 220
    let y = Double(i / 60) * 160
    let t = types[i % types.count]
    style.backgroundColor = ["transparent", "#a5d8ff", "#b2f2bb", "#ffec99"][i % 4]
    style.fillStyle = ["hachure", "solid", "cross-hatch"][i % 3]
    switch t {
    case .text:
      scene.elements.append(Element.makeText("Text \(i)", x: x, y: y, style: style))
    case .freedraw:
      var e = Element.make(.freedraw, x: x, y: y, style: style)
      e.points = (0..<40).map { CGPoint(x: Double($0) * 4, y: sin(Double($0) / 4) * 30) }
      e.width = 160
      e.height = 60
      scene.elements.append(e)
    case .arrow, .line:
      var e = Element.make(t, x: x, y: y, width: 160, height: 80, style: style)
      e.points = [.zero, CGPoint(x: 80, y: 60), CGPoint(x: 160, y: 10)]
      scene.elements.append(e)
    default:
      scene.elements.append(Element.make(t, x: x, y: y, width: 180, height: 110, style: style))
    }
  }
  try scene.encoded().write(to: URL(fileURLWithPath: args[0]))
  print("wrote \(count) elements to \(args[0])")

default:
  fail("unknown command \(command)")
}
