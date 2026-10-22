import CoreGraphics
import CoreText
import Foundation
import GrafixCore
import ImageIO
import UniformTypeIdentifiers

/// Draws whole scenes (port of Excalidraw's renderer/staticScene.ts ordering)
/// and exports them as PNG / PDF.
public enum SceneRenderer {
  public struct Options {
    public var dark = false
    public var zoom: CGFloat = 1
    /// Scene-space rect that is visible; elements outside are skipped.
    public var viewport: CGRect? = nil
    /// Clip frame children to their frame (Excalidraw's default).
    public var clipFrames = true
    /// Draw frame outlines and names (off when exporting a single frame).
    public var drawFrames = true
    /// Elements to skip (e.g. the one being edited as text).
    public var hiddenIDs: Set<String> = []
    /// Per-element opacity multiplier (eraser preview, presentation fades).
    public var dimmedIDs: Set<String> = []
    public init() {}
  }

  /// Draws `scene` into a y-down context whose CTM already maps scene
  /// coordinates to device space.
  public static func draw(_ scene: Scene, in ctx: CGContext, cache: RenderCache, options: Options) {
    Fonts.register()
    let positions = scene.positions()
    let elements = scene.elements
    let background = scene.viewBackgroundColor
    let renderOptions = ElementRenderer.Options(
      dark: options.dark, canvasBackground: background, zoom: options.zoom, cache: cache, files: scene.files)
    let viewport = options.viewport?.insetBy(dx: -50 / options.zoom, dy: -50 / options.zoom)

    func frame(of e: Element) -> Element? {
      guard let f = e.frameId, let i = positions[f] else { return nil }
      let frame = elements[i]
      return frame.isDeleted ? nil : frame
    }

    func opacity(_ e: Element) -> CGFloat {
      var o = CGFloat(min(max(e.opacity, 0), 100)) / 100
      if let f = frame(of: e) { o *= CGFloat(min(max(f.opacity, 0), 100)) / 100 }
      if options.dimmedIDs.contains(e.id) { o *= 0.2 }
      return o
    }

    func visible(_ e: Element) -> Bool {
      guard let viewport else { return true }
      let pad = max(e.strokeWidth * 12, e.isText ? e.fontSize : 20)
      return e.bounds.insetBy(dx: -pad, dy: -pad).intersects(viewport)
    }

    func render(_ e: Element) {
      if e.isText, let c = e.containerId, positions[c] != nil { return }  // drawn with container
      if options.hiddenIDs.contains(e.id) { return }
      if e.isFrame && !options.drawFrames { return }
      guard visible(e) else { return }
      ctx.saveGState()
      if options.clipFrames, let f = frame(of: e) {
        ctx.addPath(CGPath(roundedRect: f.rect, cornerWidth: 0, cornerHeight: 0, transform: nil))
        ctx.clip()
      }
      if e.type == .arrow, let tid = e.boundTextID, let ti = positions[tid], !elements[ti].isDeleted,
        !elements[ti].text.isEmpty
      {
        // Excalidraw clears the label's box out of the arrow stroke.
        let label = elements[ti]
        let pad = TextLayout.boundTextPadding
        let hole = CGRect(x: label.x - pad, y: label.y - pad, width: label.width + pad * 2, height: label.height + pad * 2)
        ctx.saveGState()
        let clip = CGMutablePath()
        clip.addRect(e.bounds.union(hole).insetBy(dx: -1000, dy: -1000))
        clip.addRect(hole)
        ctx.addPath(clip)
        ctx.clip(using: .evenOdd)
        ElementRenderer.draw(e, in: ctx, options: renderOptions, opacity: opacity(e))
        ctx.restoreGState()
      } else {
        ElementRenderer.draw(e, in: ctx, options: renderOptions, opacity: opacity(e))
      }
      if !e.isText, e.link != nil, options.drawFrames { drawLinkIcon(e, in: ctx, zoom: options.zoom, dark: options.dark) }
      if let tid = e.boundTextID, let ti = positions[tid], !elements[ti].isDeleted,
        !options.hiddenIDs.contains(tid)
      {
        ElementRenderer.draw(elements[ti], in: ctx, options: renderOptions, opacity: opacity(elements[ti]), container: e)
      }
      ctx.restoreGState()
    }

    for e in elements where !e.isDeleted && e.type != .embeddable && e.type != .iframe { render(e) }
    for e in elements where !e.isDeleted && (e.type == .embeddable || e.type == .iframe) { render(e) }
    if options.drawFrames {
      for e in elements where !e.isDeleted && e.isFrame && visible(e) && !options.hiddenIDs.contains(e.id) {
        drawFrameName(e, in: ctx, zoom: options.zoom, dark: options.dark)
      }
    }
  }

  /// Excalidraw's small link badge at an element's top-right corner.
  public static func drawLinkIcon(_ e: Element, in ctx: CGContext, zoom: CGFloat, dark: Bool) {
    let size = 14 / zoom
    let b = e.bounds
    let r = CGRect(x: b.maxX - size / 2, y: b.minY - size, width: size, height: size)
    ctx.saveGState()
    ctx.setFillColor(dark ? CGColor(gray: 0.15, alpha: 1) : .white)
    ctx.setStrokeColor(CSSColor.cgColor("#6965db"))
    ctx.setLineWidth(1 / zoom)
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: 3 / zoom, cornerHeight: 3 / zoom, transform: nil))
    ctx.drawPath(using: .fillStroke)
    // Two interlocking link loops.
    ctx.setLineWidth(1.4 / zoom)
    let c = CGPoint(x: r.midX, y: r.midY)
    let d = size * 0.18
    for k in [-1.0, 1.0] {
      let loop = CGRect(x: c.x + k * d - size * 0.22, y: c.y - k * d - size * 0.12, width: size * 0.44, height: size * 0.24)
      var t = CGAffineTransform(translationX: loop.midX, y: loop.midY).rotated(by: -.pi / 4).translatedBy(x: -loop.midX, y: -loop.midY)
      ctx.addPath(CGPath(roundedRect: loop, cornerWidth: size * 0.12, cornerHeight: size * 0.12, transform: &t))
    }
    ctx.strokePath()
    ctx.restoreGState()
  }

  /// Frame titles, drawn above the frame at a constant screen size (14px).
  public static func drawFrameName(_ e: Element, in ctx: CGContext, zoom: CGFloat, dark: Bool) {
    let name = e.name ?? (e.type == .magicframe ? "AI Frame" : "Frame")
    let size = 14 / zoom
    let font = CTFontCreateWithName("Helvetica Neue" as CFString, size, nil)
    let color = CGColor(srgbRed: dark ? 0.478 : 0.6, green: dark ? 0.478 : 0.6, blue: dark ? 0.478 : 0.6, alpha: 1)
    let attrs: [NSAttributedString.Key: Any] = [
      NSAttributedString.Key(kCTFontAttributeName as String): font,
      NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
    ]
    var line = CTLineCreateWithAttributedString(NSAttributedString(string: name, attributes: attrs))
    let maxWidth = e.width
    if CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) > maxWidth, maxWidth > 20,
      let ellipsis = Optional(CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attrs))),
      let truncated = CTLineCreateTruncatedLine(line, Double(maxWidth), .end, ellipsis)
    {
      line = truncated
    }
    ctx.saveGState()
    ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
    ctx.textPosition = CGPoint(x: e.x, y: e.y - 3 / zoom - size * 0.25)
    CTLineDraw(line, ctx)
    ctx.restoreGState()
  }

  // MARK: - Export

  /// Scene-space rectangle an export covers.
  public static func exportBounds(_ scene: Scene, frameID: String?, padding: CGFloat) -> CGRect? {
    if let frameID, let f = scene.element(frameID), !f.isDeleted { return f.rect }
    let visible = scene.visibleElements
    guard let first = visible.first else { return nil }
    var r = visible.dropFirst().reduce(first.bounds) { $0.union($1.bounds) }
    // Include frame names.
    if visible.contains(where: \.isFrame) { r = r.union(r.offsetBy(dx: 0, dy: -24)) }
    return r.insetBy(dx: -padding, dy: -padding)
  }

  /// Renders to a bitmap context and returns a CGImage.
  public static func image(
    _ scene: Scene, frameID: String? = nil, scale: CGFloat = 2, maxWidth: CGFloat? = nil, maxHeight: CGFloat? = nil,
    padding: CGFloat = 20, dark: Bool = false, background: Bool = true
  ) -> CGImage? {
    guard let bounds = exportBounds(scene, frameID: frameID, padding: padding) else { return nil }
    var s = scale
    if let maxWidth, bounds.width * s > maxWidth { s = maxWidth / bounds.width }
    if let maxHeight, bounds.height * s > maxHeight { s = maxHeight / bounds.height }
    let w = max(1, Int((bounds.width * s).rounded(.up)))
    let h = max(1, Int((bounds.height * s).rounded(.up)))
    guard let ctx = CGContext(
      data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    // Flip to y-down, then map scene -> pixels.
    ctx.translateBy(x: 0, y: CGFloat(h))
    ctx.scaleBy(x: 1, y: -1)
    if background {
      ctx.setFillColor(CSSColor.cgColor(scene.viewBackgroundColor, dark: dark))
      ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    }
    ctx.scaleBy(x: s, y: s)
    ctx.translateBy(x: -bounds.minX, y: -bounds.minY)
    var options = Options()
    options.dark = dark
    options.zoom = 1
    options.drawFrames = frameID == nil
    if frameID != nil {
      ctx.clip(to: bounds)
    }
    draw(scene, in: ctx, cache: RenderCache(), options: options)
    return ctx.makeImage()
  }

  /// PNG of the scene (or one frame, clipped to it), scaled so width <= maxWidth.
  public static func png(_ scene: Scene, frameID: String?, maxWidth: CGFloat, padding: CGFloat, dark: Bool) -> Data? {
    guard let img = image(scene, frameID: frameID, scale: 2, maxWidth: maxWidth, maxHeight: 1080 * 2, padding: padding, dark: dark)
    else { return nil }
    return pngData(img)
  }

  public static func pngData(_ image: CGImage) -> Data? {
    let data = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { return nil }
    return data as Data
  }

  /// A PDF with one page per slide (frame), or one page for the whole scene.
  public static func pdf(_ scene: Scene, frameIDs: [String]?, dark: Bool = false) -> Data? {
    let data = NSMutableData()
    guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return nil }
    var mediaBox = CGRect(x: 0, y: 0, width: 854, height: 480)
    guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }
    let pages: [CGRect] =
      frameIDs.map { ids in ids.compactMap { scene.element($0)?.rect } }
      ?? [exportBounds(scene, frameID: nil, padding: 20)].compactMap { $0 }
    let cache = RenderCache()
    for rect in pages {
      var box = CGRect(origin: .zero, size: rect.size)
      ctx.beginPage(mediaBox: &box)
      ctx.saveGState()
      ctx.translateBy(x: 0, y: rect.height)
      ctx.scaleBy(x: 1, y: -1)
      ctx.setFillColor(CSSColor.cgColor(scene.viewBackgroundColor, dark: dark))
      ctx.fill(box)
      ctx.translateBy(x: -rect.minX, y: -rect.minY)
      ctx.clip(to: rect)
      var options = Options()
      options.dark = dark
      options.drawFrames = frameIDs == nil
      draw(scene, in: ctx, cache: cache, options: options)
      ctx.restoreGState()
      ctx.endPage()
    }
    ctx.closePDF()
    return data as Data
  }
}
