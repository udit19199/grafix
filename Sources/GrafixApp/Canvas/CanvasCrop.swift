import AppKit
import GrafixCore
import GrafixRender

/// Image cropping (Excalidraw cropElement.ts, simplified): double-click an
/// image, drag a corner handle, Escape/Enter/click outside to finish.
/// `crop` is stored in the image's natural pixels like Excalidraw:
/// {x, y, width, height, naturalWidth, naturalHeight}.
extension CanvasView {
  struct CropState {
    var id: String
    /// Element and crop at gesture start.
    var original: Element
    var corner: Int?
  }

  func naturalSize(of e: Element) -> CGSize? {
    guard let id = e.fileId, let img = overlayCache.image(fileID: id, files: document.scene.files) else { return nil }
    return CGSize(width: img.width, height: img.height)
  }

  /// Crop rect in natural pixels (whole image when uncropped).
  func cropRect(of e: Element) -> CGRect? {
    if let c = e.crop?.object, let x = c["x"]?.number, let y = c["y"]?.number, let w = c["width"]?.number,
      let h = c["height"]?.number
    {
      return CGRect(x: x, y: y, width: w, height: h)
    }
    guard let n = naturalSize(of: e) else { return nil }
    return CGRect(origin: .zero, size: n)
  }

  func beginCrop(_ id: String) {
    guard let e = document.scene.element(id), e.type == .image, naturalSize(of: e) != nil else { return }
    cropState = CropState(id: id, original: e, corner: nil)
    document.select([id])
    overlayLayer.setNeedsDisplay()
  }

  func endCrop() {
    cropState = nil
    overlayLayer.setNeedsDisplay()
  }

  /// Corner handle (0 nw, 1 ne, 2 se, 3 sw) under a scene point.
  func cropCorner(at p: CGPoint) -> Int? {
    guard let s = cropState, let e = document.scene.element(s.id) else { return nil }
    let local = e.toLocal(p)
    let corners = [CGPoint.zero, CGPoint(x: e.width, y: 0), CGPoint(x: e.width, y: e.height), CGPoint(x: 0, y: e.height)]
    return corners.firstIndex { $0.distance(to: local) <= 14 / zoom }
  }

  func cropMouseDown(at p: CGPoint) -> Bool {
    guard var s = cropState else { return false }
    guard let corner = cropCorner(at: p), let e = document.scene.element(s.id) else {
      endCrop()
      return false
    }
    s.corner = corner
    s.original = e
    cropState = s
    document.beginInteraction()
    return true
  }

  func cropDragged(to p: CGPoint) {
    guard let s = cropState, let corner = s.corner, let natural = naturalSize(of: s.original),
      let crop0 = cropRect(of: s.original)
    else { return }
    let e0 = s.original
    // Element pixels per natural pixel stays constant while cropping.
    let k = e0.width / max(crop0.width, 1)
    let local = e0.toLocal(p)
    // Edges of the crop in element-local coordinates, then clamp to the image.
    var x1: CGFloat = 0, y1: CGFloat = 0, x2 = e0.width, y2 = e0.height
    switch corner {
    case 0: x1 = local.x; y1 = local.y
    case 1: x2 = local.x; y1 = local.y
    case 2: x2 = local.x; y2 = local.y
    default: x1 = local.x; y2 = local.y
    }
    let minX = -crop0.minX * k
    let minY = -crop0.minY * k
    let maxX = (natural.width - crop0.minX) * k
    let maxY = (natural.height - crop0.minY) * k
    x1 = min(max(x1, minX), x2 - 10)
    y1 = min(max(y1, minY), y2 - 10)
    x2 = max(min(x2, maxX), x1 + 10)
    y2 = max(min(y2, maxY), y1 + 10)
    let newCrop = CGRect(x: crop0.minX + x1 / k, y: crop0.minY + y1 / k, width: (x2 - x1) / k, height: (y2 - y1) / k)
    let topLeft = e0.toScene(CGPoint(x: x1, y: y1))
    let w = x2 - x1
    let h = y2 - y1
    let id = s.id
    document.updateInteraction { scene in
      scene.update(id) { el in
        // Keep the rotated top-left fixed in scene space.
        el.width = w
        el.height = h
        let center = CGPoint(x: topLeft.x, y: topLeft.y) + CGPoint(x: w / 2, y: h / 2).rotated(around: .zero, by: e0.angle)
        el.x = center.x - w / 2
        el.y = center.y - h / 2
        el.crop = [
          "x": .number(newCrop.minX), "y": .number(newCrop.minY), "width": .number(newCrop.width),
          "height": .number(newCrop.height), "naturalWidth": .number(natural.width), "naturalHeight": .number(natural.height),
        ]
      }
    }
    overlayLayer.setNeedsDisplay()
  }

  func cropMouseUp() {
    guard var s = cropState, s.corner != nil else { return }
    s.corner = nil
    cropState = s
    document.endInteraction()
  }

  /// Faded full image outside the crop plus L-shaped corner handles.
  func drawCrop(_ ctx: CGContext) {
    guard let s = cropState, let e = document.scene.element(s.id), let crop = cropRect(of: e),
      let id = e.fileId, let img = overlayCache.image(fileID: id, files: document.scene.files)
    else { return }
    let k = e.width / max(crop.width, 1)
    ctx.saveGState()
    let c = e.rotationCenter
    ctx.translateBy(x: c.x, y: c.y)
    ctx.rotate(by: e.angle)
    ctx.translateBy(x: -c.x, y: -c.y)
    ctx.translateBy(x: e.x, y: e.y)
    let full = CGRect(x: -crop.minX * k, y: -crop.minY * k, width: CGFloat(img.width) * k, height: CGFloat(img.height) * k)
    ctx.saveGState()
    ctx.setAlpha(0.35)
    ctx.translateBy(x: 0, y: full.maxY + full.minY)
    ctx.scaleBy(x: 1, y: -1)
    ctx.draw(img, in: full)
    ctx.restoreGState()
    ctx.setStrokeColor(selectionColor)
    ctx.setLineWidth(1 / zoom)
    ctx.stroke(CGRect(x: 0, y: 0, width: e.width, height: e.height))
    ctx.setLineWidth(3 / zoom)
    let len = min(20 / zoom, e.width / 3, e.height / 3)
    let corners: [(CGPoint, CGFloat, CGFloat)] = [
      (.zero, 1, 1), (CGPoint(x: e.width, y: 0), -1, 1), (CGPoint(x: e.width, y: e.height), -1, -1),
      (CGPoint(x: 0, y: e.height), 1, -1),
    ]
    for (p, sx, sy) in corners {
      ctx.move(to: CGPoint(x: p.x + sx * len, y: p.y))
      ctx.addLine(to: p)
      ctx.addLine(to: CGPoint(x: p.x, y: p.y + sy * len))
    }
    ctx.strokePath()
    ctx.restoreGState()
  }
}
