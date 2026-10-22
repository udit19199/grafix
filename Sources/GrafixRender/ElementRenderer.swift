import CoreGraphics
import CoreText
import Foundation
import GrafixCore
import ImageIO

/// A Rough.js drawable converted to ready-to-draw CGPaths (built once, cached).
public struct PreparedShape: @unchecked Sendable {
  enum Kind { case stroke, fill(evenOdd: Bool), sketch }
  struct Op {
    var kind: Kind
    var path: CGPath
    var color: CGColor
    var lineWidth: CGFloat
    var dash: [CGFloat]?
  }
  var ops: [Op] = []
  /// Filled freedraw outline.
  var freedraw: CGPath?
  var freedrawColor: CGColor?

  init(drawables: [Drawable], freedraw: CGPath?, freedrawColor: CGColor?) {
    self.freedraw = freedraw
    self.freedrawColor = freedrawColor
    for d in drawables {
      let o = d.options
      for set in d.sets {
        let path = d.cgPath(set)
        switch set.type {
        case .path:
          guard o.stroke != "none" else { continue }
          ops.append(Op(kind: .stroke, path: path, color: CSSColor.cgColor(o.stroke), lineWidth: o.strokeWidth,
                        dash: o.strokeLineDash?.map { CGFloat($0) }))
        case .fillPath:
          let evenOdd = d.shape == "curve" || d.shape == "polygon" || d.shape == "path"
          ops.append(Op(kind: .fill(evenOdd: evenOdd), path: path, color: CSSColor.cgColor(o.fill ?? "transparent"),
                        lineWidth: 0, dash: nil))
        case .fillSketch:
          let w = o.fillWeight < 0 ? o.strokeWidth / 2 : o.fillWeight
          ops.append(Op(kind: .sketch, path: path, color: CSSColor.cgColor(o.fill ?? "transparent"), lineWidth: w, dash: nil))
        }
      }
    }
  }

  func draw(in ctx: CGContext) {
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    if let freedraw, let freedrawColor {
      // Background fill (rough curve) comes first, then the stroke outline.
      for op in ops { drawOp(op, ctx) }
      ctx.setFillColor(freedrawColor)
      ctx.addPath(freedraw)
      ctx.fillPath()
      return
    }
    for op in ops { drawOp(op, ctx) }
  }

  private func drawOp(_ op: Op, _ ctx: CGContext) {
    switch op.kind {
    case .stroke, .sketch:
      ctx.setStrokeColor(op.color)
      ctx.setLineWidth(op.lineWidth)
      if let dash = op.dash, !dash.isEmpty { ctx.setLineDash(phase: 0, lengths: dash) } else { ctx.setLineDash(phase: 0, lengths: []) }
      ctx.addPath(op.path)
      ctx.strokePath()
    case .fill(let evenOdd):
      ctx.setFillColor(op.color)
      ctx.addPath(op.path)
      ctx.fillPath(using: evenOdd ? .evenOdd : .winding)
    }
  }
}

/// Caches generated shapes, text lines and decoded images, keyed by element
/// id + version. One instance per canvas (or per export).
public final class RenderCache: @unchecked Sendable {
  struct ShapeEntry {
    var key: Element
    var dark: Bool
    var background: String
    var shape: PreparedShape
  }
  struct TextEntry {
    var key: Element
    var dark: Bool
    var lines: [(line: CTLine, width: CGFloat)]
  }

  /// The element with every field that does not affect its local geometry
  /// reset, so moving/re-indexing/binding an element keeps its cached shape.
  static func shapeKey(_ e: Element) -> Element {
    var k = e
    k.x = 0
    k.y = 0
    k.angle = 0
    k.opacity = 100
    k.version = 0
    k.versionNonce = 0
    k.updated = 0
    k.created = nil
    k.index = nil
    k.frameId = nil
    k.groupIds = []
    k.boundElements = nil
    k.link = nil
    k.locked = false
    k.customData = nil
    k.startBinding = nil
    k.endBinding = nil
    k.containerId = nil
    return k
  }
  private var shapes: [String: ShapeEntry] = [:]
  private var texts: [String: TextEntry] = [:]
  private var images: [String: CGImage] = [:]
  private var missingImages: Set<String> = []
  private let lock = NSLock()

  public init() {}

  func shape(for e: Element, dark: Bool, background: String) -> PreparedShape {
    let key = RenderCache.shapeKey(e)
    lock.lock()
    if let hit = shapes[e.id], hit.dark == dark, hit.background == background, hit.key == key {
      lock.unlock()
      return hit.shape
    }
    lock.unlock()
    let (drawables, freedraw) = ShapeGenerator.shape(for: e, dark: dark, canvasBackground: background)
    let fdColor = freedraw != nil ? CSSColor.cgColor(e.strokeColor, dark: dark) : nil
    let prepared = PreparedShape(drawables: drawables, freedraw: freedraw, freedrawColor: fdColor)
    lock.lock()
    shapes[e.id] = ShapeEntry(key: key, dark: dark, background: background, shape: prepared)
    lock.unlock()
    return prepared
  }

  func textLines(for e: Element, dark: Bool) -> [(line: CTLine, width: CGFloat)] {
    let key = RenderCache.shapeKey(e)
    lock.lock()
    if let hit = texts[e.id], hit.dark == dark, hit.key == key {
      lock.unlock()
      return hit.lines
    }
    lock.unlock()
    let font = Fonts.font(family: e.fontFamily, size: e.fontSize)
    let color = CSSColor.cgColor(e.strokeColor, dark: dark)
    let attrs: [NSAttributedString.Key: Any] = [
      NSAttributedString.Key(kCTFontAttributeName as String): font,
      NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
    ]
    let lines = TextLayout.lines(e.text).map { s -> (CTLine, CGFloat) in
      let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: attrs))
      return (line, CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)))
    }
    lock.lock()
    texts[e.id] = TextEntry(key: key, dark: dark, lines: lines)
    lock.unlock()
    return lines
  }

  /// Decoded image for a file id from the scene's `files`.
  public func image(fileID: String, files: [String: JSONValue]) -> CGImage? {
    lock.lock()
    if let img = images[fileID] {
      lock.unlock()
      return img
    }
    if missingImages.contains(fileID) {
      lock.unlock()
      return nil
    }
    lock.unlock()
    var decoded: CGImage?
    if let url = files[fileID]?["dataURL"]?.string, let comma = url.firstIndex(of: ",") {
      let payload = String(url[url.index(after: comma)...])
      let data: Data? =
        url[..<comma].contains(";base64")
        ? Data(base64Encoded: payload, options: .ignoreUnknownCharacters)
        : payload.removingPercentEncoding.map { Data($0.utf8) }
      if let data, let src = CGImageSourceCreateWithData(data as CFData, nil) {
        decoded = CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
      }
    }
    lock.lock()
    if let decoded { images[fileID] = decoded } else { missingImages.insert(fileID) }
    lock.unlock()
    return decoded
  }

  /// Drops entries for elements no longer present (call occasionally).
  public func prune(keeping ids: Set<String>) {
    lock.lock()
    shapes = shapes.filter { ids.contains($0.key) }
    texts = texts.filter { ids.contains($0.key) }
    lock.unlock()
  }
}

/// Draws single elements into a y-down CGContext in scene coordinates.
public enum ElementRenderer {
  public struct Options {
    public var dark: Bool
    public var canvasBackground: String
    /// Current zoom, for zoom-independent strokes (frames).
    public var zoom: CGFloat
    public var cache: RenderCache
    public var files: [String: JSONValue]
    public init(dark: Bool, canvasBackground: String, zoom: CGFloat, cache: RenderCache, files: [String: JSONValue]) {
      self.dark = dark
      self.canvasBackground = canvasBackground
      self.zoom = zoom
      self.cache = cache
      self.files = files
    }
  }

  /// Draws `e`. `opacity` is the combined element*frame opacity (0...1).
  /// `container` is the text's container when drawing a bound label.
  public static func draw(_ e: Element, in ctx: CGContext, options o: Options, opacity: CGFloat, container: Element? = nil) {
    guard opacity > 0 else { return }
    ctx.saveGState()
    defer { ctx.restoreGState() }
    let angle = e.isText && container?.type == .arrow ? 0 : e.angle
    if angle != 0 {
      let c = e.rotationCenter
      ctx.translateBy(x: c.x, y: c.y)
      ctx.rotate(by: angle)
      ctx.translateBy(x: -c.x, y: -c.y)
    }
    ctx.translateBy(x: e.x, y: e.y)
    let layered = opacity < 1 && e.type != .frame
    if layered {
      ctx.setAlpha(opacity)
      ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    }
    switch e.type {
    case .text:
      drawText(e, ctx, o)
    case .image:
      drawImage(e, ctx, o)
    case .frame, .magicframe:
      drawFrame(e, ctx, o)
    case .embeddable, .iframe:
      o.cache.shape(for: e, dark: o.dark, background: o.canvasBackground).draw(in: ctx)
      drawEmbedPlaceholder(e, ctx, o)
    case .stickynote:
      drawStickyNote(e, ctx, o)
    case .selection:
      break
    default:
      o.cache.shape(for: e, dark: o.dark, background: o.canvasBackground).draw(in: ctx)
    }
    if layered { ctx.endTransparencyLayer() }
  }

  static func drawText(_ e: Element, _ ctx: CGContext, _ o: Options) {
    let lines = o.cache.textLines(for: e, dark: o.dark)
    let lineHeightPx = e.fontSize * e.lineHeight
    let baseline = TextLayout.baselineOffset(family: e.fontFamily, size: e.fontSize, lineHeightPx: lineHeightPx)
    ctx.saveGState()
    ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
    for (i, item) in lines.enumerated() {
      let x: CGFloat
      switch e.textAlign {
      case .left: x = 0
      case .center: x = e.width / 2 - item.width / 2
      case .right: x = e.width - item.width
      }
      ctx.textPosition = CGPoint(x: x, y: CGFloat(i) * lineHeightPx + baseline)
      CTLineDraw(item.line, ctx)
    }
    ctx.restoreGState()
  }

  static func drawImage(_ e: Element, _ ctx: CGContext, _ o: Options) {
    guard let id = e.fileId, let img = o.cache.image(fileID: id, files: o.files) else {
      // drawImagePlaceholder
      ctx.setFillColor(CSSColor.cgColor("#E7E7E7", dark: o.dark))
      ctx.fill(CGRect(x: 0, y: 0, width: e.width, height: e.height))
      return
    }
    ctx.saveGState()
    if e.roundness != nil {
      let r = e.cornerRadius(min(e.width, e.height))
      ctx.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: e.width, height: e.height), cornerWidth: r, cornerHeight: r, transform: nil))
      ctx.clip()
    }
    let sx = e.scale.first ?? 1
    let sy = e.scale.count > 1 ? e.scale[1] : 1
    ctx.translateBy(x: sx < 0 ? e.width : 0, y: sy < 0 ? 0 : e.height)
    ctx.scaleBy(x: sx < 0 ? -1 : 1, y: sy < 0 ? 1 : -1)
    var source = img
    if let crop = e.crop?.object, let cx = crop["x"]?.number, let cy = crop["y"]?.number,
      let cw = crop["width"]?.number, let ch = crop["height"]?.number,
      let nw = crop["naturalWidth"]?.number, nw > 0
    {
      let k = Double(img.width) / nw
      if let c = img.cropping(to: CGRect(x: cx * k, y: cy * k, width: cw * k, height: ch * k)) { source = c }
    }
    ctx.interpolationQuality = .high
    ctx.draw(source, in: CGRect(x: 0, y: 0, width: e.width, height: e.height))
    ctx.restoreGState()
  }

  static func drawFrame(_ e: Element, _ ctx: CGContext, _ o: Options) {
    // Excalidraw draws frames with a fixed screen-space style (FRAME_STYLE).
    ctx.setLineWidth(2 / o.zoom)
    ctx.setStrokeColor(CSSColor.cgColor(e.type == .magicframe ? "#7affd7" : "#bbb", dark: o.dark))
    let r = min(8 / o.zoom, min(e.width, e.height) / 2)
    ctx.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: max(e.width, 0.1), height: max(e.height, 0.1)), cornerWidth: r, cornerHeight: r, transform: nil))
    ctx.strokePath()
  }

  static func drawEmbedPlaceholder(_ e: Element, _ ctx: CGContext, _ o: Options) {
    guard e.width > 40, e.height > 20 else { return }
    let text = e.link ?? "Empty Web-Embed"
    var label = Element.make(.text, x: 0, y: 0)
    label.text = text
    label.originalText = text
    label.fontSize = min(20, max(10, e.width / 30))
    label.fontFamily = 6
    label.strokeColor = "#1e1e1e"
    label.textAlign = .center
    label.width = e.width
    let size = TextLayout.measure(text, family: 6, size: label.fontSize, lineHeight: 1.25)
    ctx.saveGState()
    ctx.translateBy(x: 0, y: e.height / 2 - size.height / 2)
    drawText(label, ctx, o)
    ctx.restoreGState()
  }

  static func drawStickyNote(_ e: Element, _ ctx: CGContext, _ o: Options) {
    let rect = CGRect(x: 0, y: 0, width: e.width, height: e.height)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 3), blur: 8, color: CGColor(gray: 0, alpha: 0.15))
    ctx.setFillColor(CSSColor.cgColor(e.backgroundColor == "transparent" ? "#fff9db" : e.backgroundColor, dark: o.dark))
    ctx.fill(rect)
    ctx.restoreGState()
  }
}
