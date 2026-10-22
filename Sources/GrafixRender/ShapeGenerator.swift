import CoreGraphics
import Foundation
import GrafixCore

/// Port of Excalidraw's packages/element/src/shape.ts: turns an element into
/// Rough.js drawables in element-local coordinates (origin at element.x/y).
public enum ShapeGenerator {
  nonisolated(unsafe) static let generator = RoughGenerator()  // stateless

  // MARK: - Options (generateRoughOptions)

  static func adjustRoughness(_ e: Element) -> Double {
    let maxSize = max(e.width, e.height)
    let minSize = min(e.width, e.height)
    let canChangeRoundness = [.rectangle, .diamond, .line, .arrow, .embeddable, .iframe, .image, .stickynote].contains(e.type)
    if (minSize >= 20 && maxSize >= 50) || (minSize >= 15 && e.roundness != nil && canChangeRoundness)
      || (e.isLinear && maxSize >= 50)
    {
      return e.roughness
    }
    return min(e.roughness / (maxSize < 10 ? 3 : 2), 2.5)
  }

  static func options(_ e: Element, continuousPath: Bool = false, dark: Bool) -> RoughOptions {
    let o = RoughOptions()
    o.seed = Int32(truncatingIfNeeded: e.seed)
    switch e.strokeStyle {
    case .dashed: o.strokeLineDash = [8, 8 + e.strokeWidth]
    case .dotted: o.strokeLineDash = [1.5, 6 + e.strokeWidth]
    case .solid: o.strokeLineDash = nil
    }
    o.disableMultiStroke = e.strokeStyle != .solid
    o.strokeWidth = e.strokeStyle != .solid ? e.strokeWidth + 0.5 : e.strokeWidth
    o.fillWeight = e.strokeWidth / 2
    o.hachureGap = e.strokeWidth * 4
    o.roughness = adjustRoughness(e)
    o.stroke = color(e.strokeColor, dark)
    o.preserveVertices = continuousPath || e.roughness < 2
    switch e.type {
    case .rectangle, .iframe, .embeddable, .diamond, .ellipse:
      o.fillStyle = e.fillStyle.rawValue
      o.fill = CSSColor.isTransparent(e.backgroundColor) ? nil : color(e.backgroundColor, dark)
      if e.type == .ellipse { o.curveFitting = 1 }
    case .line, .freedraw:
      if e.isLoop || e.polygon {
        o.fillStyle = e.fillStyle.rawValue
        o.fill = e.backgroundColor == "transparent" ? nil : color(e.backgroundColor, dark)
      }
    default:
      break
    }
    return o
  }

  static func color(_ c: String, _ dark: Bool) -> String { dark ? CSSColor.applyDarkModeFilter(c) : c }

  // MARK: - Shapes (_generateElementShape)

  /// Drawables for the element, plus the filled freedraw outline when applicable.
  public static func shape(for e: Element, dark: Bool, canvasBackground: String) -> (drawables: [Drawable], freedraw: CGPath?) {
    switch e.type {
    case .rectangle, .iframe, .embeddable:
      let el = iframeLike(e)
      if el.roundness != nil {
        let w = el.width
        let h = el.height
        let r = el.cornerRadius(min(w, h))
        let d = "M \(r) 0 L \(w - r) 0 Q \(w) 0, \(w) \(r) L \(w) \(h - r) Q \(w) \(h), \(w - r) \(h) L \(r) \(h) Q 0 \(h), 0 \(h - r) L 0 \(r) Q 0 0, \(r) 0"
        return ([generator.path(d, options(el, continuousPath: true, dark: dark))], nil)
      }
      return ([generator.rectangle(0, 0, el.width, el.height, options(el, dark: dark))], nil)
    case .diamond:
      let p = e.diamondPoints
      let (topX, topY, rightX, rightY) = (p[0].x, p[0].y, p[1].x, p[1].y)
      let (bottomX, bottomY, leftX, leftY) = (p[2].x, p[2].y, p[3].x, p[3].y)
      if e.roundness != nil {
        let vr = e.cornerRadius(abs(topX - leftX))
        let hr = e.cornerRadius(abs(rightY - topY))
        let d = """
          M \(topX + vr) \(topY + hr) L \(rightX - vr) \(rightY - hr) \
          C \(rightX) \(rightY), \(rightX) \(rightY), \(rightX - vr) \(rightY + hr) \
          L \(bottomX + vr) \(bottomY - hr) \
          C \(bottomX) \(bottomY), \(bottomX) \(bottomY), \(bottomX - vr) \(bottomY - hr) \
          L \(leftX + vr) \(leftY + hr) \
          C \(leftX) \(leftY), \(leftX) \(leftY), \(leftX + vr) \(leftY - hr) \
          L \(topX - vr) \(topY + hr) \
          C \(topX) \(topY), \(topX) \(topY), \(topX + vr) \(topY + hr)
          """
        return ([generator.path(d, options(e, continuousPath: true, dark: dark))], nil)
      }
      return ([generator.polygon(p, options(e, dark: dark))], nil)
    case .ellipse:
      return ([generator.ellipse(e.width / 2, e.height / 2, e.width, e.height, options(e, dark: dark))], nil)
    case .line, .arrow:
      return (linearShape(e, dark: dark, canvasBackground: canvasBackground), nil)
    case .freedraw:
      var drawables: [Drawable] = []
      if e.isLoop {
        let o = options(e, dark: dark)
        o.stroke = "none"
        let pts = simplify(e.points, 0.75)
        if pts.count >= 2 { drawables.append(generator.curve(pts, o)) }
      }
      return (drawables, FreedrawShape.path(for: e))
    case .stickynote:
      var el = e
      el.roundness = nil
      el.roughness = 0
      el.strokeColor = "transparent"
      return ([generator.rectangle(0, 0, el.width, el.height, options(el, dark: dark))], nil)
    default:
      return ([], nil)
    }
  }

  /// Placeholder look for embeds without content (modifyIframeLikeForRoughOptions).
  static func iframeLike(_ e: Element) -> Element {
    guard e.type == .embeddable || e.type == .iframe else { return e }
    var el = e
    if CSSColor.isTransparent(e.backgroundColor) && CSSColor.isTransparent(e.strokeColor) {
      el.roughness = 0
      el.backgroundColor = "#d3d3d3"
      el.fillStyle = .solid
    }
    return el
  }

  static func linearShape(_ e: Element, dark: Bool, canvasBackground: String) -> [Drawable] {
    let o = options(e, dark: dark)
    let points = e.points.isEmpty ? [CGPoint.zero] : e.points
    var shapes: [Drawable] = []
    if e.elbowed {
      guard points.allSatisfy({ abs($0.x) <= 1e6 && abs($0.y) <= 1e6 }) else { return [] }
      shapes = [generator.path(elbowPath(points, radius: 16), options(e, continuousPath: true, dark: dark))]
    } else if e.roundness == nil {
      shapes = [o.fill != nil ? generator.polygon(points, o) : generator.linearPath(points, o)]
    } else {
      shapes = [generator.curve(points, o)]
    }
    if e.type == .arrow {
      if let start = e.startArrowhead {
        shapes += arrowheadShapes(e, shapes, .start, start, o, canvasBackground, dark)
      }
      if let end = e.endArrowhead {
        shapes += arrowheadShapes(e, shapes, .end, end, o, canvasBackground, dark)
      }
    }
    return shapes
  }

  static func elbowPath(_ points: [CGPoint], radius: Double) -> String {
    func horizontal(_ a: CGPoint, _ b: CGPoint) -> Bool { abs(a.x - b.x) >= abs(a.y - b.y) }
    var sub: [CGPoint] = []
    if points.count > 2 {
      for i in 1..<(points.count - 1) {
        let prev = points[i - 1]
        let next = points[i + 1]
        let p = points[i]
        let corner = min(radius, p.distance(to: next) / 2, p.distance(to: prev) / 2)
        if horizontal(p, prev) {
          sub.append(prev.x < p.x ? CGPoint(x: p.x - corner, y: p.y) : CGPoint(x: p.x + corner, y: p.y))
        } else if prev.y < p.y {
          sub.append(CGPoint(x: p.x, y: p.y - corner))
        } else {
          sub.append(CGPoint(x: p.x, y: p.y + corner))
        }
        sub.append(p)
        if horizontal(next, p) {
          sub.append(next.x < p.x ? CGPoint(x: p.x - corner, y: p.y) : CGPoint(x: p.x + corner, y: p.y))
        } else if next.y < p.y {
          sub.append(CGPoint(x: p.x, y: p.y - corner))
        } else {
          sub.append(CGPoint(x: p.x, y: p.y + corner))
        }
      }
    }
    var d = ["M \(points[0].x) \(points[0].y)"]
    var i = 0
    while i + 2 < sub.count {
      d.append("L \(sub[i].x) \(sub[i].y)")
      d.append("Q \(sub[i + 1].x) \(sub[i + 1].y), \(sub[i + 2].x) \(sub[i + 2].y)")
      i += 3
    }
    d.append("L \(points[points.count - 1].x) \(points[points.count - 1].y)")
    return d.joined(separator: " ")
  }

  // MARK: - Arrowheads (getArrowheadShapes + bounds.ts getArrowheadPoints)

  enum End { case start, end }

  static func arrowheadSize(_ a: Arrowhead) -> Double {
    switch a {
    case .arrow: 25
    case .diamond, .diamondOutline: 12
    case .cardinalityMany, .cardinalityOneOrMany, .cardinalityZeroOrMany: 15
    case .cardinalityOne, .cardinalityExactlyOne, .cardinalityZeroOrOne: 20
    default: 15
    }
  }

  static func arrowheadAngle(_ a: Arrowhead) -> Double {
    switch a {
    case .bar: 90
    case .arrow: 20
    default: 25
    }
  }

  static func rotate(_ p: CGPoint, _ c: CGPoint, _ rad: Double) -> CGPoint { p.rotated(around: c, by: rad) }

  static func arrowheadPoints(_ e: Element, _ shape: [Drawable], _ pos: End, _ head: Arrowhead, offset: Double = 0) -> [Double]? {
    guard let first = shape.first else { return nil }
    let ops = first.sets.first(where: { $0.type == .path })?.ops ?? first.sets.first?.ops ?? []
    guard ops.count >= 2 else { return nil }
    let index = pos == .start ? 1 : ops.count - 1
    let data = ops[index].data
    guard data.count == 6 else { return nil }
    let p3 = CGPoint(x: data[4], y: data[5])
    let p2 = CGPoint(x: data[2], y: data[3])
    let p1 = CGPoint(x: data[0], y: data[1])
    let prev = ops[index - 1]
    var p0 = CGPoint.zero
    if prev.op == .move { p0 = CGPoint(x: prev.data[0], y: prev.data[1]) }
    else if prev.op == .bcurveTo { p0 = CGPoint(x: prev.data[4], y: prev.data[5]) }
    func eq(_ t: Double, _ k: KeyPath<CGPoint, CGFloat>) -> Double {
      pow(1 - t, 3) * p3[keyPath: k] + 3 * t * pow(1 - t, 2) * p2[keyPath: k]
        + 3 * pow(t, 2) * (1 - t) * p1[keyPath: k] + p0[keyPath: k] * pow(t, 3)
    }
    let (x2, y2) = pos == .start ? (p0.x, p0.y) : (p3.x, p3.y)
    let (x1, y1) = (eq(0.3, \.x), eq(0.3, \.y))
    let distance = hypot(x2 - x1, y2 - y1)
    guard distance > 0 else { return nil }
    let nx = (x2 - x1) / distance
    let ny = (y2 - y1) / distance
    let size = arrowheadSize(head)
    let pts = e.points
    let c = pos == .end ? pts[pts.count - 1] : pts[0]
    let p = pts.count > 1 ? (pos == .end ? pts[pts.count - 2] : pts[1]) : .zero
    let length = hypot(c.x - p.x, c.y - p.y)
    let multiplier = (head == .diamond || head == .diamondOutline) ? 0.25 : 0.5
    let minSize = min(size, length * multiplier)
    let tx = x2 - nx * minSize * offset
    let ty = y2 - ny * minSize * offset
    let xs = tx - nx * minSize
    let ys = ty - ny * minSize
    if head == .circle || head == .circleOutline {
      return [tx, ty, hypot(ys - ty, xs - tx) + e.strokeWidth - 2]
    }
    let angle = arrowheadAngle(head) * .pi / 180
    if head == .cardinalityMany || head == .cardinalityOneOrMany {
      let a = rotate(CGPoint(x: tx, y: ty), CGPoint(x: xs, y: ys), -angle)
      let b = rotate(CGPoint(x: tx, y: ty), CGPoint(x: xs, y: ys), angle)
      return [xs, ys, a.x, a.y, b.x, b.y]
    }
    let a = rotate(CGPoint(x: xs, y: ys), CGPoint(x: tx, y: ty), -angle)
    let b = rotate(CGPoint(x: xs, y: ys), CGPoint(x: tx, y: ty), angle)
    if head == .diamond || head == .diamondOutline {
      let o: CGPoint
      if pos == .start {
        let q = pts.count > 1 ? pts[1] : .zero
        o = rotate(CGPoint(x: tx + minSize * 2, y: ty), CGPoint(x: tx, y: ty), atan2(q.y - ty, q.x - tx))
      } else {
        let q = pts.count > 1 ? pts[pts.count - 2] : .zero
        o = rotate(CGPoint(x: tx - minSize * 2, y: ty), CGPoint(x: tx, y: ty), atan2(ty - q.y, tx - q.x))
      }
      return [tx, ty, a.x, a.y, o.x, o.y, b.x, b.y]
    }
    return [tx, ty, a.x, a.y, b.x, b.y]
  }

  static func arrowheadShapes(
    _ e: Element, _ shape: [Drawable], _ pos: End, _ head: Arrowhead, _ options: RoughOptions,
    _ canvasBackground: String, _ dark: Bool
  ) -> [Drawable] {
    let stroke = color(e.strokeColor, dark)
    let bg = color(canvasBackground, dark)
    func lineOptions() -> RoughOptions {
      let o = options.copy()
      if e.strokeStyle == .dotted {
        o.strokeLineDash = [1.5, 6 + (e.strokeWidth - 1) - 1]
      } else {
        o.strokeLineDash = nil
      }
      o.roughness = min(1, o.roughness)
      return o
    }
    func cardinalityOne(_ pts: [Double]?, _ o: RoughOptions) -> [Drawable] {
      guard let p = pts else { return [] }
      return [generator.line(p[2], p[3], p[4], p[5], o)]
    }
    func linesToTip(_ pts: [Double]?, _ o: RoughOptions) -> [Drawable] {
      guard let p = pts else { return [] }
      return [generator.line(p[2], p[3], p[0], p[1], o), generator.line(p[4], p[5], p[0], p[1], o)]
    }
    func circle(_ pts: [Double]?, fill: String, scale: Double = 1) -> [Drawable] {
      guard let p = pts else { return [] }
      let o = options.copy()
      o.fill = fill
      o.fillStyle = "solid"
      o.stroke = stroke
      o.roughness = min(0.5, o.roughness)
      o.strokeLineDash = nil
      return [generator.circle(p[0], p[1], p[2] * scale, o)]
    }
    switch head {
    case .circle, .circleOutline:
      return circle(arrowheadPoints(e, shape, pos, head), fill: head == .circleOutline ? bg : stroke)
    case .triangle, .triangleOutline:
      guard let p = arrowheadPoints(e, shape, pos, head) else { return [] }
      let o = options.copy()
      o.fill = head == .triangleOutline ? bg : stroke
      o.fillStyle = "solid"
      o.roughness = min(1, o.roughness)
      o.strokeLineDash = nil
      let pts = [CGPoint(x: p[0], y: p[1]), CGPoint(x: p[2], y: p[3]), CGPoint(x: p[4], y: p[5]), CGPoint(x: p[0], y: p[1])]
      return [generator.polygon(pts, o)]
    case .diamond, .diamondOutline:
      guard let p = arrowheadPoints(e, shape, pos, head) else { return [] }
      let o = options.copy()
      o.fill = head == .diamondOutline ? bg : stroke
      o.fillStyle = "solid"
      o.roughness = min(1, o.roughness)
      o.strokeLineDash = nil
      let pts = [
        CGPoint(x: p[0], y: p[1]), CGPoint(x: p[2], y: p[3]), CGPoint(x: p[4], y: p[5]),
        CGPoint(x: p[6], y: p[7]), CGPoint(x: p[0], y: p[1]),
      ]
      return [generator.polygon(pts, o)]
    case .cardinalityOne:
      return cardinalityOne(arrowheadPoints(e, shape, pos, head), lineOptions())
    case .cardinalityMany:
      return linesToTip(arrowheadPoints(e, shape, pos, head), lineOptions())
    case .cardinalityOneOrMany:
      let o = lineOptions()
      return linesToTip(arrowheadPoints(e, shape, pos, .cardinalityMany), o)
        + cardinalityOne(arrowheadPoints(e, shape, pos, .cardinalityOne, offset: -0.25), o)
    case .cardinalityExactlyOne:
      let o = lineOptions()
      return cardinalityOne(arrowheadPoints(e, shape, pos, .cardinalityOne, offset: -0.5), o)
        + cardinalityOne(arrowheadPoints(e, shape, pos, .cardinalityOne), o)
    case .cardinalityZeroOrOne:
      let o = lineOptions()
      return circle(arrowheadPoints(e, shape, pos, .circleOutline, offset: 1.5), fill: bg, scale: 0.8)
        + cardinalityOne(arrowheadPoints(e, shape, pos, .cardinalityOne, offset: -0.5), o)
    case .cardinalityZeroOrMany:
      let o = lineOptions()
      return linesToTip(arrowheadPoints(e, shape, pos, .cardinalityMany), o)
        + circle(arrowheadPoints(e, shape, pos, .circleOutline, offset: 1.5), fill: bg, scale: 0.8)
    default:  // arrow, bar
      return linesToTip(arrowheadPoints(e, shape, pos, head), lineOptions())
    }
  }

  static func simplify(_ points: [CGPoint], _ distance: Double) -> [CGPoint] {
    simplifyPoints(points, distance)
  }
}
