import CoreGraphics
import Foundation

// MARK: - Point math

extension CGPoint {
  public static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
  public static func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
  public static func * (a: CGPoint, s: CGFloat) -> CGPoint { CGPoint(x: a.x * s, y: a.y * s) }
  public var length: CGFloat { hypot(x, y) }
  public func distance(to p: CGPoint) -> CGFloat { hypot(x - p.x, y - p.y) }

  /// Rotates around `center` by `angle` radians (clockwise in y-down space).
  public func rotated(around center: CGPoint, by angle: CGFloat) -> CGPoint {
    guard angle != 0 else { return self }
    let c = cos(angle)
    let s = sin(angle)
    let dx = x - center.x
    let dy = y - center.y
    return CGPoint(x: center.x + dx * c - dy * s, y: center.y + dx * s + dy * c)
  }
}

extension CGRect {
  public init(points: [CGPoint]) {
    guard let first = points.first else {
      self = .null
      return
    }
    var minX = first.x
    var minY = first.y
    var maxX = first.x
    var maxY = first.y
    for p in points.dropFirst() {
      minX = min(minX, p.x)
      minY = min(minY, p.y)
      maxX = max(maxX, p.x)
      maxY = max(maxY, p.y)
    }
    self.init(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
  }
  public var center: CGPoint { CGPoint(x: midX, y: midY) }
}

/// Distance from `p` to segment `a`-`b`.
public func distanceToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
  let ab = b - a
  let lenSq = ab.x * ab.x + ab.y * ab.y
  guard lenSq > 0 else { return p.distance(to: a) }
  let t = max(0, min(1, ((p.x - a.x) * ab.x + (p.y - a.y) * ab.y) / lenSq))
  return p.distance(to: a + ab * t)
}

// MARK: - Element geometry

extension Element {
  /// Unrotated box in scene coordinates: (x1, y1, x2, y2). For linear elements
  /// this is the bounding box of the points, which may extend left/up of x/y.
  public var absoluteCoords: CGRect {
    if (isLinear || type == .freedraw), !points.isEmpty {
      let r = CGRect(points: points)
      return r.offsetBy(dx: x, dy: y)
    }
    return CGRect(x: x, y: y, width: width, height: height).standardized
  }

  /// Centre used for rotation (centre of `absoluteCoords`, as in Excalidraw).
  public var rotationCenter: CGPoint { absoluteCoords.center }

  /// Axis-aligned bounds including rotation. Used for culling and selection boxes.
  public var bounds: CGRect {
    let r = absoluteCoords
    guard angle != 0 else { return r }
    let c = r.center
    if isLinear || type == .freedraw {
      return CGRect(points: points.map { CGPoint(x: x + $0.x, y: y + $0.y).rotated(around: c, by: angle) })
    }
    let corners = [
      CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
      CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY),
    ]
    return CGRect(points: corners.map { $0.rotated(around: c, by: angle) })
  }

  /// Corner radius for rounded rectangles (Excalidraw getCornerRadius).
  public func cornerRadius(_ side: CGFloat) -> CGFloat {
    guard let r = roundness else { return 0 }
    if r.type == 1 || r.type == 2 { return side * 0.25 }
    if r.type == 3 {
      let fixed = r.value ?? 32
      return side <= fixed / 0.25 ? side * 0.25 : fixed
    }
    return 0
  }

  /// Diamond vertices relative to x/y: top, right, bottom, left (getDiamondPoints).
  public var diamondPoints: [CGPoint] {
    let topX = (width / 2).rounded(.down)
    let leftY = (height / 2).rounded(.down)
    return [
      CGPoint(x: topX, y: 0), CGPoint(x: width, y: leftY), CGPoint(x: topX, y: height),
      CGPoint(x: 0, y: leftY),
    ]
  }

  /// Whether the path is closed (Excalidraw isPathALoop: ends within 8px, scaled by zoom 1).
  public var isLoop: Bool {
    guard points.count >= 3, let a = points.first, let b = points.last else { return false }
    return a.distance(to: b) <= 8
  }

  /// Excalidraw shouldTestInside: whether clicking inside (not just the outline) hits.
  public var hitsInside: Bool {
    if type == .arrow { return false }
    let filled = backgroundColor != "transparent" && !backgroundColor.isEmpty
    let inside = filled || boundTextID != nil || type == .text || type == .embeddable
      || type == .iframe
    if type == .line || type == .freedraw { return inside && (isLoop || polygon) }
    return inside || type == .image || type == .stickynote
  }

  /// Geometric outline in element-local coordinates (origin at x/y, unrotated).
  /// This is the clean shape, not the sketchy one; used for hit tests and clipping.
  public var localOutline: CGPath {
    let path = CGMutablePath()
    switch type {
    case .ellipse:
      path.addEllipse(in: CGRect(x: 0, y: 0, width: width, height: height))
    case .diamond:
      path.addLines(between: diamondPoints)
      path.closeSubpath()
    case .line, .arrow, .freedraw:
      let ps = points.isEmpty ? [.zero] : points
      if roundness != nil, ps.count > 2, type != .freedraw, !elbowed {
        addCurve(through: ps, to: path)
      } else {
        path.addLines(between: ps)
      }
      if polygon || (type == .freedraw && isLoop) { path.closeSubpath() }
    case .rectangle, .embeddable, .iframe, .image, .stickynote:
      let r = cornerRadius(min(width, height))
      let rect = CGRect(x: 0, y: 0, width: width, height: height).standardized
      if r > 0, rect.width >= 2 * r, rect.height >= 2 * r {
        path.addRoundedRect(in: rect, cornerWidth: r, cornerHeight: r)
      } else {
        path.addRect(rect)
      }
    default:
      path.addRect(CGRect(x: 0, y: 0, width: width, height: height).standardized)
    }
    return path
  }

  /// Converts a scene point to element-local, unrotated coordinates.
  public func toLocal(_ p: CGPoint) -> CGPoint {
    let unrotated = p.rotated(around: rotationCenter, by: -angle)
    return CGPoint(x: unrotated.x - x, y: unrotated.y - y)
  }

  /// Converts an element-local point to scene coordinates (applying rotation).
  public func toScene(_ p: CGPoint) -> CGPoint {
    CGPoint(x: x + p.x, y: y + p.y).rotated(around: rotationCenter, by: angle)
  }

  /// Whether `point` (scene coordinates) hits this element. `threshold` is in scene units.
  public func hitTest(_ point: CGPoint, threshold: CGFloat) -> Bool {
    // Cheap reject first: most elements are nowhere near the pointer.
    let slack = threshold + strokeWidth
    guard bounds.insetBy(dx: -slack, dy: -slack).contains(point) else { return false }
    let local = toLocal(point)
    let outline = localOutline
    if type == .text || isFrame {
      return CGRect(x: 0, y: 0, width: width, height: height).insetBy(dx: -threshold, dy: -threshold)
        .contains(local)
    }
    if hitsInside, outline.contains(local) { return true }
    let stroke = outline.copy(
      strokingWithWidth: max(threshold * 2, strokeWidth + threshold), lineCap: .round,
      lineJoin: .round, miterLimit: 10)
    return stroke.contains(local)
  }
}

/// Smooth curve through points, matching Rough.js `curve` with roughness 0
/// (Catmull-Rom style cubic segments, curveTightness 0).
public func addCurve(through input: [CGPoint], to path: CGMutablePath) {
  guard input.count > 1 else {
    if let p = input.first { path.move(to: p) }
    return
  }
  var ps = [input[0]] + input + [input[input.count - 1]]
  if ps.count == 4 {  // two input points: straight line
    path.move(to: input[0])
    path.addLine(to: input[1])
    return
  }
  ps = Array(ps)
  path.move(to: ps[1])
  var i = 1
  while i + 2 < ps.count {
    let p0 = ps[i - 1]
    let p1 = ps[i]
    let p2 = ps[i + 1]
    let p3 = ps[i + 2]
    let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
    let c2 = CGPoint(x: p2.x + (p1.x - p3.x) / 6, y: p2.y + (p1.y - p3.y) / 6)
    path.addCurve(to: p2, control1: c1, control2: c2)
    i += 1
  }
}
