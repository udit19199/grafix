import AppKit
import GrafixCore
import GrafixRender
import QuartzCore

/// Renders the scene (everything except selection UI) into a bitmap on a
/// background queue and shows it in a CALayer.
///
/// Performance model (why this is fast):
/// - Rendering never blocks the main thread; at most one render is in flight
///   and newer requests coalesce into the next one.
/// - While a render is pending after a pan/zoom, the previous bitmap is
///   transformed to the new viewport, so feedback is immediate.
/// - Elements being dragged/drawn are hidden here and drawn live by the
///   overlay, so a drag does not re-render the whole scene each frame.
final class StaticSceneLayer: CALayer, @unchecked Sendable {
  struct Request {
    var scene: Scene
    var zoom: CGFloat
    var scrollX: CGFloat
    var scrollY: CGFloat
    var size: CGSize
    var scale: CGFloat
    var dark: Bool
    var grid: Bool
    var hidden: Set<String>
    var dimmed: Set<String>
  }

  private let queue = DispatchQueue(label: "grafix.render", qos: .userInteractive)
  private let cache = RenderCache()
  private var inFlight = false
  private var pending: Request?
  /// Viewport of the bitmap currently shown.
  private var shown: (zoom: CGFloat, scrollX: CGFloat, scrollY: CGFloat)?
  private var current: (zoom: CGFloat, scrollX: CGFloat, scrollY: CGFloat)?

  override init() {
    super.init()
    contentsGravity = .topLeft
    actions = ["contents": NSNull(), "transform": NSNull(), "bounds": NSNull(), "position": NSNull()]
    isOpaque = false
  }

  override init(layer: Any) { super.init(layer: layer) }
  required init?(coder: NSCoder) { fatalError() }

  /// Shows the old bitmap at the new viewport immediately, then renders.
  func update(_ request: Request) {
    current = (request.zoom, request.scrollX, request.scrollY)
    applyInterimTransform()
    pending = request
    pump()
  }

  /// Synchronous render (used for the first frame so the window never flashes empty).
  func renderNow(_ request: Request) {
    current = (request.zoom, request.scrollX, request.scrollY)
    let image = Self.render(request, cache: cache)
    show(image, for: request)
  }

  private func pump() {
    guard !inFlight, let request = pending else { return }
    pending = nil
    inFlight = true
    let cache = self.cache
    let ref = WeakLayer(self)
    queue.async {
      let image = UncheckedImage(Self.render(request, cache: cache))
      DispatchQueue.main.async {
        guard let layer = ref.layer else { return }
        layer.inFlight = false
        layer.show(image.image, for: request)
        layer.pump()
      }
    }
  }

  private func show(_ image: CGImage?, for request: Request) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    contents = image
    contentsScale = request.scale
    bounds = CGRect(origin: .zero, size: request.size)
    shown = (request.zoom, request.scrollX, request.scrollY)
    applyInterimTransform()
    CATransaction.commit()
  }

  /// Maps the shown bitmap's viewport onto the current one.
  private func applyInterimTransform() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    defer { CATransaction.commit() }
    guard let shown, let current, shown != current else {
      transform = CATransform3DIdentity
      return
    }
    // screen = (scene + scroll) * zoom. A pixel p in the old image shows scene
    // point p/z0 - s0; in the new viewport that is at (p/z0 - s0 + s1) * z1.
    let k = current.zoom / shown.zoom
    let tx = (current.scrollX - shown.scrollX) * current.zoom
    let ty = (current.scrollY - shown.scrollY) * current.zoom
    // The layer is anchored at its top-left in a flipped host.
    var t = CATransform3DMakeTranslation(tx, ty, 0)
    t = CATransform3DScale(t, k, k, 1)
    transform = t
  }

  static func render(_ r: Request, cache: RenderCache) -> CGImage? {
    let w = Int((r.size.width * r.scale).rounded(.up))
    let h = Int((r.size.height * r.scale).rounded(.up))
    guard w > 0, h > 0,
      let ctx = CGContext(
        data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
    else { return nil }
    ctx.translateBy(x: 0, y: CGFloat(h))
    ctx.scaleBy(x: r.scale, y: -r.scale)
    ctx.setFillColor(CSSColor.cgColor(r.scene.viewBackgroundColor, dark: r.dark))
    ctx.fill(CGRect(origin: .zero, size: r.size))
    ctx.setShouldSmoothFonts(false)
    ctx.scaleBy(x: r.zoom, y: r.zoom)
    ctx.translateBy(x: r.scrollX, y: r.scrollY)
    let viewport = CGRect(x: -r.scrollX, y: -r.scrollY, width: r.size.width / r.zoom, height: r.size.height / r.zoom)
    if r.grid { drawGrid(ctx, viewport: viewport, zoom: r.zoom, dark: r.dark) }
    var options = SceneRenderer.Options()
    options.dark = r.dark
    options.zoom = r.zoom
    options.viewport = viewport
    options.hiddenIDs = r.hidden
    options.dimmedIDs = r.dimmed
    SceneRenderer.draw(r.scene, in: ctx, cache: cache, options: options)
    return ctx.makeImage()
  }

  /// Excalidraw's grid: 20px cells, every 5th line stronger.
  static func drawGrid(_ ctx: CGContext, viewport: CGRect, zoom: CGFloat, dark: Bool) {
    let size: CGFloat = 20
    let step = 5
    // Skip minor lines when they'd be denser than 10px on screen.
    let minor = size * zoom >= 10
    let startX = Int((viewport.minX / size).rounded(.down))
    let endX = Int((viewport.maxX / size).rounded(.up))
    let startY = Int((viewport.minY / size).rounded(.down))
    let endY = Int((viewport.maxY / size).rounded(.up))
    let minorColor = dark ? CGColor(gray: 1, alpha: 0.06) : CGColor(gray: 0, alpha: 0.05)
    let majorColor = dark ? CGColor(gray: 1, alpha: 0.12) : CGColor(gray: 0, alpha: 0.1)
    ctx.setLineWidth(1 / zoom)
    for pass in 0..<2 {
      let major = pass == 1
      if !major && !minor { continue }
      let path = CGMutablePath()
      for i in startX...endX where (i % step == 0) == major {
        let x = CGFloat(i) * size
        path.move(to: CGPoint(x: x, y: viewport.minY))
        path.addLine(to: CGPoint(x: x, y: viewport.maxY))
      }
      for j in startY...endY where (j % step == 0) == major {
        let y = CGFloat(j) * size
        path.move(to: CGPoint(x: viewport.minX, y: y))
        path.addLine(to: CGPoint(x: viewport.maxX, y: y))
      }
      ctx.setStrokeColor(major ? majorColor : minorColor)
      ctx.addPath(path)
      ctx.strokePath()
    }
  }
}

private struct WeakLayer: @unchecked Sendable {
  weak var layer: StaticSceneLayer?
  init(_ layer: StaticSceneLayer) { self.layer = layer }
}

private struct UncheckedImage: @unchecked Sendable {
  let image: CGImage?
  init(_ image: CGImage?) { self.image = image }
}
