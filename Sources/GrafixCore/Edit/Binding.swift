import CoreGraphics
import Foundation

/// Arrow-to-shape bindings, simplified from Excalidraw's binding.ts.
///
/// A binding stores a `fixedPoint` ratio inside the target's box. With mode
/// "inside" the arrow end sits exactly on that point; with "orbit" (default) it
/// stops at the target's outline, `gap` pixels away, on the line towards the
/// arrow's other end.
extension Scene {
  public static let bindingGapBase: CGFloat = 5

  /// Global position of a binding's fixed point (getGlobalFixedPointForBindableElement).
  public func focusPoint(_ binding: PointBinding, target: Element) -> CGPoint {
    let f = binding.fixedPoint ?? CGPoint(x: 0.5, y: 0.5)
    let fx = min(max(f.x, 0), 1)
    let fy = min(max(f.y, 0), 1)
    return CGPoint(x: target.x + target.width * fx, y: target.y + target.height * fy)
      .rotated(around: target.center, by: target.angle)
  }

  /// Fixed-point ratio for a global point on/near `target`.
  public static func fixedPoint(for point: CGPoint, on target: Element) -> CGPoint {
    let local = target.toLocal(point)
    let w = max(target.width, 1)
    let h = max(target.height, 1)
    return CGPoint(x: local.x / w, y: local.y / h)
  }

  /// Where the arrow end should sit for `binding`, given the other end at `other`.
  public func boundEndpoint(_ binding: PointBinding, target: Element, other: CGPoint) -> CGPoint {
    let focus = focusPoint(binding, target: target)
    if binding.mode == "inside" || binding.mode == "skip" { return focus }
    let gap = Scene.bindingGapBase + target.strokeWidth / 2
    // `other` may itself be inside the target (overlapping shapes): keep the focus.
    if target.hitTest(other, threshold: gap) && target.hitsInsideForBinding(other) { return focus }
    // Bisect from `other` (outside) towards `focus` (inside) for the expanded outline.
    var lo: CGFloat = 0
    var hi: CGFloat = 1
    for _ in 0..<32 {
      let mid = (lo + hi) / 2
      let p = other + (focus - other) * mid
      if target.containsExpanded(p, gap: gap) { hi = mid } else { lo = mid }
    }
    return other + (focus - other) * hi
  }

  /// Side an elbow arrow leaves `t` from: the side of its fixed point, or the
  /// side facing `other` when bound near the centre.
  func elbowHeading(_ b: PointBinding, _ t: Element, toward other: CGPoint) -> Heading {
    let f = b.fixedPoint ?? CGPoint(x: 0.5, y: 0.5)
    if abs(f.x - 0.5) < 0.25 && abs(f.y - 0.5) < 0.25 {
      let local = t.toLocal(other)
      let dx = (local.x - t.width / 2) / max(t.width, 1)
      let dy = (local.y - t.height / 2) / max(t.height, 1)
      return abs(dx) > abs(dy) ? (dx > 0 ? .right : .left) : (dy > 0 ? .down : .up)
    }
    return Scene.heading(for: f) ?? .right
  }

  /// Elbow arrows attach to the middle of the side nearest their fixed point,
  /// `gap` outside the shape.
  public func elbowAnchor(_ binding: PointBinding, target t: Element, heading: Heading? = nil) -> CGPoint {
    let gap = Scene.bindingGapBase + t.strokeWidth / 2
    let f = binding.fixedPoint ?? CGPoint(x: 0.5, y: 0.5)
    let local: CGPoint
    switch heading ?? Scene.heading(for: f) ?? .right {
    case .left: local = CGPoint(x: -gap, y: t.height * min(max(f.y, 0), 1))
    case .right: local = CGPoint(x: t.width + gap, y: t.height * min(max(f.y, 0), 1))
    case .up: local = CGPoint(x: t.width * min(max(f.x, 0), 1), y: -gap)
    case .down: local = CGPoint(x: t.width * min(max(f.x, 0), 1), y: t.height + gap)
    }
    return t.toScene(local)
  }

  /// Re-attaches every arrow bound to `elementIDs` (after they moved or resized).
  public mutating func updateBoundArrows(of elementIDs: Set<String>) {
    var arrows = Set<String>()
    for e in elements where elementIDs.contains(e.id) {
      for b in e.boundElements ?? [] where b.type == "arrow" { arrows.insert(b.id) }
      if e.type == .arrow { arrows.insert(e.id) }
    }
    for id in arrows { refreshArrow(id) }
  }

  /// Recomputes both bound ends of one arrow.
  public mutating func refreshArrow(_ arrowID: String) {
    guard let ai = indexOf(arrowID), elements[ai].type == .arrow || elements[ai].type == .line,
      elements[ai].points.count >= 2, !elements[ai].isDeleted
    else { return }
    var arrow = elements[ai]
    var global = arrow.points.map { arrow.toScene($0) }
    let startTarget = arrow.startBinding.flatMap { element($0.elementId) }.flatMap { $0.isDeleted ? nil : $0 }
    let endTarget = arrow.endBinding.flatMap { element($0.elementId) }.flatMap { $0.isDeleted ? nil : $0 }
    guard startTarget != nil || endTarget != nil else { return }
    let n = global.count
    // Use the focus points of the other end as the aim for 2-point arrows (like Excalidraw).
    let startAim =
      n == 2 ? (endTarget.map { focusPoint(arrow.endBinding!, target: $0) } ?? global[1]) : global[1]
    let endAim =
      n == 2
      ? (startTarget.map { focusPoint(arrow.startBinding!, target: $0) } ?? global[n - 2])
      : global[n - 2]
    if let t = startTarget, let b = arrow.startBinding {
      global[0] =
        arrow.elbowed
        ? elbowAnchor(b, target: t, heading: elbowHeading(b, t, toward: endTarget?.center ?? global[n - 1]))
        : boundEndpoint(b, target: t, other: startAim)
    }
    if let t = endTarget, let b = arrow.endBinding {
      global[n - 1] =
        arrow.elbowed
        ? elbowAnchor(b, target: t, heading: elbowHeading(b, t, toward: startTarget?.center ?? global[0]))
        : boundEndpoint(b, target: t, other: endAim)
    }
    if arrow.elbowed, let first = global.first, let last = global.last {
      global = Scene.elbowRoute(
        from: first, to: last, startHeading: arrow.startBinding.flatMap { b in startTarget.map { elbowHeading(b, $0, toward: last) } },
        endHeading: arrow.endBinding.flatMap { b in endTarget.map { elbowHeading(b, $0, toward: first) } })
    }
    arrow.setGlobalPoints(global)
    arrow.bump()
    elements[ai] = arrow
    if arrow.boundTextID != nil { layoutLabel(of: arrowID) }
  }

  /// Binds an arrow end to `targetID` at `point` (scene coordinates).
  public mutating func bind(arrowID: String, end: ArrowEnd, to targetID: String, at point: CGPoint, mode: String = "orbit") {
    guard let ai = indexOf(arrowID), let ti = indexOf(targetID) else { return }
    unbind(arrowID: arrowID, end: end)
    let fixed = Scene.fixedPoint(for: point, on: elements[ti])
    let binding = PointBinding(elementId: targetID, fixedPoint: fixed, mode: mode)
    if end == .start { elements[ai].startBinding = binding } else { elements[ai].endBinding = binding }
    var bound = elements[ti].boundElements ?? []
    if !bound.contains(where: { $0.id == arrowID }) {
      bound.append(BoundElement(id: arrowID, type: "arrow"))
      elements[ti].boundElements = bound
      elements[ti].bump()
    }
    elements[ai].bump()
  }

  public mutating func unbind(arrowID: String, end: ArrowEnd) {
    guard let ai = indexOf(arrowID) else { return }
    let old = end == .start ? elements[ai].startBinding : elements[ai].endBinding
    guard let old else { return }
    if end == .start { elements[ai].startBinding = nil } else { elements[ai].endBinding = nil }
    let other = end == .start ? elements[ai].endBinding : elements[ai].startBinding
    if other?.elementId != old.elementId, let ti = indexOf(old.elementId) {
      elements[ti].boundElements?.removeAll { $0.id == arrowID }
      elements[ti].bump()
    }
    elements[ai].bump()
  }

  /// Orthogonal route between two points: horizontal-vertical-horizontal.
  /// A simple stand-in for Excalidraw's A* elbow router.
  public static func elbowRoute(_ points: [CGPoint]) -> [CGPoint] {
    guard let a = points.first, let b = points.last, points.count >= 2 else { return points }
    return elbowRoute(from: a, to: b, startHeading: nil, endHeading: nil)
  }

  public enum Heading: Sendable { case up, down, left, right
    var horizontal: Bool { self == .left || self == .right }
    var vector: CGPoint {
      switch self {
      case .up: CGPoint(x: 0, y: -1)
      case .down: CGPoint(x: 0, y: 1)
      case .left: CGPoint(x: -1, y: 0)
      case .right: CGPoint(x: 1, y: 0)
      }
    }
  }

  /// Which way an arrow leaves a shape when bound at `fixedPoint` (the nearest side).
  public static func heading(for fixedPoint: CGPoint?) -> Heading? {
    guard let f = fixedPoint else { return nil }
    let d = [(Heading.left, f.x), (.right, 1 - f.x), (.up, f.y), (.down, 1 - f.y)]
    return d.min { $0.1 < $1.1 }?.0
  }

  /// Orthogonal route that leaves `a` along `startHeading` and enters `b`
  /// against `endHeading` (Excalidraw's elbow arrows exit perpendicular to the
  /// bound side). Falls back to horizontal-first when headings are unknown.
  public static func elbowRoute(from a: CGPoint, to b: CGPoint, startHeading: Heading?, endHeading: Heading?) -> [CGPoint] {
    let stub: CGFloat = 20
    let dx = b.x - a.x
    let dy = b.y - a.y
    let sh = startHeading ?? (abs(dx) >= abs(dy) ? (dx >= 0 ? .right : .left) : (dy >= 0 ? .down : .up))
    let eh = endHeading ?? (sh.horizontal ? (dx >= 0 ? .left : .right) : (dy >= 0 ? .up : .down))
    // Points just outside the shapes, along the headings.
    let a1 = a + sh.vector * stub
    let b1 = b + eh.vector * stub
    var route: [CGPoint] = [a]
    if sh.horizontal && eh.horizontal {
      let midX = (a1.x + b1.x) / 2
      route += [CGPoint(x: midX, y: a.y), CGPoint(x: midX, y: b.y)]
    } else if !sh.horizontal && !eh.horizontal {
      let midY = (a1.y + b1.y) / 2
      route += [CGPoint(x: a.x, y: midY), CGPoint(x: b.x, y: midY)]
    } else if sh.horizontal {
      route += [CGPoint(x: b.x, y: a.y)]
    } else {
      route += [CGPoint(x: a.x, y: b.y)]
    }
    route.append(b)
    // Drop zero-length and collinear points.
    var clean: [CGPoint] = []
    for p in route {
      if let last = clean.last, last.distance(to: p) < 0.5 { continue }
      if clean.count >= 2 {
        let p0 = clean[clean.count - 2]
        let p1 = clean[clean.count - 1]
        if (abs(p0.x - p1.x) < 0.5 && abs(p1.x - p.x) < 0.5) || (abs(p0.y - p1.y) < 0.5 && abs(p1.y - p.y) < 0.5) {
          clean[clean.count - 1] = p
          continue
        }
      }
      clean.append(p)
    }
    return clean.count >= 2 ? clean : [a, b]
  }
}

public enum ArrowEnd: Sendable { case start, end }

extension Element {
  /// Whether `p` is inside the shape or within `gap` of its outline.
  public func containsExpanded(_ p: CGPoint, gap: CGFloat) -> Bool {
    guard bounds.insetBy(dx: -gap - strokeWidth, dy: -gap - strokeWidth).contains(p) else { return false }
    let local = toLocal(p)
    let outline = localOutline
    if outline.contains(local) { return true }
    return outline.copy(strokingWithWidth: gap * 2, lineCap: .round, lineJoin: .round, miterLimit: 10)
      .contains(local)
  }

  func hitsInsideForBinding(_ p: CGPoint) -> Bool { localOutline.contains(toLocal(p)) }

  /// Sets points from scene coordinates, normalising so points[0] is (0,0)
  /// (as Excalidraw does), and updates x/y/width/height. Rotation is reset to
  /// keep the stored points exact.
  public mutating func setGlobalPoints(_ global: [CGPoint]) {
    guard let first = global.first else { return }
    angle = 0
    x = first.x
    y = first.y
    points = global.map { CGPoint(x: $0.x - first.x, y: $0.y - first.y) }
    let r = CGRect(points: points)
    width = r.width
    height = r.height
  }
}
