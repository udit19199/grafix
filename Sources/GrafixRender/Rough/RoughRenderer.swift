import CoreGraphics
import Foundation

// Port of roughjs/bin/renderer.js (4.6.4). Evaluation order mirrors the JS so
// the shared randomizer is consumed identically.

enum RoughRenderer {
  // MARK: Public-ish shapes

  static func line(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ o: RoughOptions)
    -> OpSet
  {
    OpSet(type: .path, ops: doubleLine(x1, y1, x2, y2, o))
  }

  static func linearPath(_ points: [CGPoint], close: Bool, _ o: RoughOptions) -> OpSet {
    let len = points.count
    if len > 2 {
      var ops: [RoughOp] = []
      for i in 0..<(len - 1) {
        ops.append(
          contentsOf: doubleLine(
            points[i].x, points[i].y, points[i + 1].x, points[i + 1].y, o))
      }
      if close {
        ops.append(
          contentsOf: doubleLine(
            points[len - 1].x, points[len - 1].y, points[0].x, points[0].y, o))
      }
      return OpSet(type: .path, ops: ops)
    } else if len == 2 {
      return line(points[0].x, points[0].y, points[1].x, points[1].y, o)
    }
    return OpSet(type: .path, ops: [])
  }

  static func polygon(_ points: [CGPoint], _ o: RoughOptions) -> OpSet {
    linearPath(points, close: true, o)
  }

  static func rectangle(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ o: RoughOptions)
    -> OpSet
  {
    polygon(
      [CGPoint(x: x, y: y), CGPoint(x: x + w, y: y), CGPoint(x: x + w, y: y + h),
       CGPoint(x: x, y: y + h)], o)
  }

  static func curve(_ points: [CGPoint], _ o: RoughOptions) -> OpSet {
    var o1 = curveWithOffset(points, 1 * (1 + o.roughness * 0.2), o)
    if !o.disableMultiStroke {
      let o2 = curveWithOffset(points, 1.5 * (1 + o.roughness * 0.22), cloneOptionsAlterSeed(o))
      o1 = o1 + o2
    }
    return OpSet(type: .path, ops: o1)
  }

  struct EllipseParams {
    var increment: Double
    var rx: Double
    var ry: Double
  }

  static func ellipse(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ o: RoughOptions)
    -> OpSet
  {
    let params = generateEllipseParams(w, h, o)
    return ellipseWithParams(x, y, o, params).opset
  }

  static func generateEllipseParams(_ width: Double, _ height: Double, _ o: RoughOptions)
    -> EllipseParams
  {
    let psq = (Double.pi * 2 * ((pow(width / 2, 2) + pow(height / 2, 2)) / 2).squareRoot())
      .squareRoot()
    let stepCount = (max(o.curveStepCount, (o.curveStepCount / (200.0).squareRoot()) * psq))
      .rounded(.up)
    let increment = (Double.pi * 2) / stepCount
    var rx = abs(width / 2)
    var ry = abs(height / 2)
    let curveFitRandomness = 1 - o.curveFitting
    rx += offsetOpt(rx * curveFitRandomness, o)
    ry += offsetOpt(ry * curveFitRandomness, o)
    return EllipseParams(increment: increment, rx: rx, ry: ry)
  }

  static func ellipseWithParams(
    _ x: Double, _ y: Double, _ o: RoughOptions, _ p: EllipseParams
  ) -> (estimatedPoints: [CGPoint], opset: OpSet) {
    let (ap1, cp1) = computeEllipsePoints(
      p.increment, x, y, p.rx, p.ry, 1, p.increment * offset(0.1, offset(0.4, 1, o), o), o)
    var o1 = curveOps(ap1, nil, o)
    if !o.disableMultiStroke && o.roughness != 0 {
      let (ap2, _) = computeEllipsePoints(p.increment, x, y, p.rx, p.ry, 1.5, 0, o)
      let o2 = curveOps(ap2, nil, o)
      o1 = o1 + o2
    }
    return (cp1, OpSet(type: .path, ops: o1))
  }

  static func arc(
    _ x: Double, _ y: Double, _ width: Double, _ height: Double, _ start: Double, _ stop: Double,
    _ closed: Bool, _ roughClosure: Bool, _ o: RoughOptions
  ) -> OpSet {
    let cx = x, cy = y
    var rx = abs(width / 2)
    var ry = abs(height / 2)
    rx += offsetOpt(rx * 0.01, o)
    ry += offsetOpt(ry * 0.01, o)
    var strt = start
    var stp = stop
    while strt < 0 {
      strt += Double.pi * 2
      stp += Double.pi * 2
    }
    if (stp - strt) > (Double.pi * 2) {
      strt = 0
      stp = Double.pi * 2
    }
    let ellipseInc = (Double.pi * 2) / o.curveStepCount
    let arcInc = min(ellipseInc / 2, (stp - strt) / 2)
    var ops = arcOps(arcInc, cx, cy, rx, ry, strt, stp, 1, o)
    if !o.disableMultiStroke {
      ops.append(contentsOf: arcOps(arcInc, cx, cy, rx, ry, strt, stp, 1.5, o))
    }
    if closed {
      if roughClosure {
        ops.append(contentsOf: doubleLine(cx, cy, cx + rx * cos(strt), cy + ry * sin(strt), o))
        ops.append(contentsOf: doubleLine(cx, cy, cx + rx * cos(stp), cy + ry * sin(stp), o))
      } else {
        ops.append(RoughOp(.lineTo, [cx, cy]))
        ops.append(RoughOp(.lineTo, [cx + rx * cos(strt), cy + ry * sin(strt)]))
      }
    }
    return OpSet(type: .path, ops: ops)
  }

  static func svgPath(_ path: String, _ o: RoughOptions) -> OpSet {
    let segments = normalizePath(absolutizePath(parsePath(path)))
    var ops: [RoughOp] = []
    var first = [0.0, 0.0]
    var current = [0.0, 0.0]
    for seg in segments {
      let data = seg.data
      switch seg.key {
      case "M":
        current = [data[0], data[1]]
        first = [data[0], data[1]]
      case "L":
        ops.append(contentsOf: doubleLine(current[0], current[1], data[0], data[1], o))
        current = [data[0], data[1]]
      case "C":
        ops.append(
          contentsOf: bezierTo(data[0], data[1], data[2], data[3], data[4], data[5], current, o))
        current = [data[4], data[5]]
      case "Z":
        ops.append(contentsOf: doubleLine(current[0], current[1], first[0], first[1], o))
        current = [first[0], first[1]]
      default:
        break
      }
    }
    return OpSet(type: .path, ops: ops)
  }

  // MARK: Fills

  static func solidFillPolygon(_ polygonList: [[CGPoint]], _ o: RoughOptions) -> OpSet {
    var ops: [RoughOp] = []
    for points in polygonList where !points.isEmpty {
      let off = o.maxRandomnessOffset
      let len = points.count
      if len > 2 {
        let mx = points[0].x + offsetOpt(off, o)
        let my = points[0].y + offsetOpt(off, o)
        ops.append(RoughOp(.move, [mx, my]))
        for i in 1..<len {
          let lx = points[i].x + offsetOpt(off, o)
          let ly = points[i].y + offsetOpt(off, o)
          ops.append(RoughOp(.lineTo, [lx, ly]))
        }
      }
    }
    return OpSet(type: .fillPath, ops: ops)
  }

  static func patternFillPolygons(_ polygonList: inout [[CGPoint]], _ o: RoughOptions) -> OpSet {
    getFiller(o).fillPolygons(&polygonList, o)
  }

  static func patternFillArc(
    _ x: Double, _ y: Double, _ width: Double, _ height: Double, _ start: Double, _ stop: Double,
    _ o: RoughOptions
  ) -> OpSet {
    let cx = x, cy = y
    var rx = abs(width / 2)
    var ry = abs(height / 2)
    rx += offsetOpt(rx * 0.01, o)
    ry += offsetOpt(ry * 0.01, o)
    var strt = start
    var stp = stop
    while strt < 0 {
      strt += Double.pi * 2
      stp += Double.pi * 2
    }
    if (stp - strt) > (Double.pi * 2) {
      strt = 0
      stp = Double.pi * 2
    }
    let increment = (stp - strt) / o.curveStepCount
    var points: [CGPoint] = []
    var angle = strt
    while angle <= stp {
      points.append(CGPoint(x: cx + rx * cos(angle), y: cy + ry * sin(angle)))
      angle = angle + increment
    }
    points.append(CGPoint(x: cx + rx * cos(stp), y: cy + ry * sin(stp)))
    points.append(CGPoint(x: cx, y: cy))
    var list = [points]
    return patternFillPolygons(&list, o)
  }

  // MARK: Helpers exposed to fillers

  static func doubleLineFillOps(
    _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ o: RoughOptions
  ) -> [RoughOp] {
    doubleLine(x1, y1, x2, y2, o, filling: true)
  }

  // MARK: Private helpers

  static func cloneOptionsAlterSeed(_ ops: RoughOptions) -> RoughOptions {
    let result = ops.copy()
    result.randomizer = nil
    if ops.seed != 0 {
      result.seed = ops.seed &+ 1
    }
    return result
  }

  static func offset(_ min: Double, _ max: Double, _ ops: RoughOptions, _ roughnessGain: Double = 1)
    -> Double
  {
    ops.roughness * roughnessGain * ((ops.random() * (max - min)) + min)
  }

  static func offsetOpt(_ x: Double, _ ops: RoughOptions, _ roughnessGain: Double = 1) -> Double {
    offset(-x, x, ops, roughnessGain)
  }

  static func doubleLine(
    _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ o: RoughOptions,
    filling: Bool = false
  ) -> [RoughOp] {
    let singleStroke = filling ? o.disableMultiStrokeFill : o.disableMultiStroke
    let o1 = lineOps(x1, y1, x2, y2, o, true, false)
    if singleStroke { return o1 }
    let o2 = lineOps(x1, y1, x2, y2, o, true, true)
    return o1 + o2
  }

  static func lineOps(
    _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ o: RoughOptions,
    _ move: Bool, _ overlay: Bool
  ) -> [RoughOp] {
    let lengthSq = pow(x1 - x2, 2) + pow(y1 - y2, 2)
    let length = lengthSq.squareRoot()
    var roughnessGain = 1.0
    if length < 200 {
      roughnessGain = 1
    } else if length > 500 {
      roughnessGain = 0.4
    } else {
      roughnessGain = (-0.0016668) * length + 1.233334
    }
    var off = o.maxRandomnessOffset
    if (off * off * 100) > lengthSq {
      off = length / 10
    }
    let halfOffset = off / 2
    let divergePoint = 0.2 + o.random() * 0.2
    var midDispX = o.bowing * o.maxRandomnessOffset * (y2 - y1) / 200
    var midDispY = o.bowing * o.maxRandomnessOffset * (x1 - x2) / 200
    midDispX = offsetOpt(midDispX, o, roughnessGain)
    midDispY = offsetOpt(midDispY, o, roughnessGain)
    var ops: [RoughOp] = []
    func randomHalf() -> Double { offsetOpt(halfOffset, o, roughnessGain) }
    func randomFull() -> Double { offsetOpt(off, o, roughnessGain) }
    let pv = o.preserveVertices
    if move {
      if overlay {
        let a = x1 + (pv ? 0 : randomHalf())
        let b = y1 + (pv ? 0 : randomHalf())
        ops.append(RoughOp(.move, [a, b]))
      } else {
        let a = x1 + (pv ? 0 : offsetOpt(off, o, roughnessGain))
        let b = y1 + (pv ? 0 : offsetOpt(off, o, roughnessGain))
        ops.append(RoughOp(.move, [a, b]))
      }
    }
    if overlay {
      let d0 = midDispX + x1 + (x2 - x1) * divergePoint + randomHalf()
      let d1 = midDispY + y1 + (y2 - y1) * divergePoint + randomHalf()
      let d2 = midDispX + x1 + 2 * (x2 - x1) * divergePoint + randomHalf()
      let d3 = midDispY + y1 + 2 * (y2 - y1) * divergePoint + randomHalf()
      let d4 = x2 + (pv ? 0 : randomHalf())
      let d5 = y2 + (pv ? 0 : randomHalf())
      ops.append(RoughOp(.bcurveTo, [d0, d1, d2, d3, d4, d5]))
    } else {
      let d0 = midDispX + x1 + (x2 - x1) * divergePoint + randomFull()
      let d1 = midDispY + y1 + (y2 - y1) * divergePoint + randomFull()
      let d2 = midDispX + x1 + 2 * (x2 - x1) * divergePoint + randomFull()
      let d3 = midDispY + y1 + 2 * (y2 - y1) * divergePoint + randomFull()
      let d4 = x2 + (pv ? 0 : randomFull())
      let d5 = y2 + (pv ? 0 : randomFull())
      ops.append(RoughOp(.bcurveTo, [d0, d1, d2, d3, d4, d5]))
    }
    return ops
  }

  static func curveWithOffset(_ points: [CGPoint], _ off: Double, _ o: RoughOptions) -> [RoughOp] {
    var ps: [CGPoint] = []
    func jittered(_ p: CGPoint) -> CGPoint {
      let x = p.x + offsetOpt(off, o)
      let y = p.y + offsetOpt(off, o)
      return CGPoint(x: x, y: y)
    }
    ps.append(jittered(points[0]))
    ps.append(jittered(points[0]))
    for i in 1..<points.count {
      ps.append(jittered(points[i]))
      if i == points.count - 1 {
        ps.append(jittered(points[i]))
      }
    }
    return curveOps(ps, nil, o)
  }

  static func curveOps(_ points: [CGPoint], _ closePoint: [Double]?, _ o: RoughOptions)
    -> [RoughOp]
  {
    let len = points.count
    var ops: [RoughOp] = []
    if len > 3 {
      let s = 1 - o.curveTightness
      ops.append(RoughOp(.move, [points[1].x, points[1].y]))
      var i = 1
      while i + 2 < len {
        let c = points[i]
        let b1x = c.x + (s * points[i + 1].x - s * points[i - 1].x) / 6
        let b1y = c.y + (s * points[i + 1].y - s * points[i - 1].y) / 6
        let b2x = points[i + 1].x + (s * points[i].x - s * points[i + 2].x) / 6
        let b2y = points[i + 1].y + (s * points[i].y - s * points[i + 2].y) / 6
        ops.append(
          RoughOp(.bcurveTo, [b1x, b1y, b2x, b2y, points[i + 1].x, points[i + 1].y]))
        i += 1
      }
      if let cp = closePoint, cp.count == 2 {
        let ro = o.maxRandomnessOffset
        let a = cp[0] + offsetOpt(ro, o)
        let b = cp[1] + offsetOpt(ro, o)
        ops.append(RoughOp(.lineTo, [a, b]))
      }
    } else if len == 3 {
      ops.append(RoughOp(.move, [points[1].x, points[1].y]))
      ops.append(
        RoughOp(
          .bcurveTo,
          [points[1].x, points[1].y, points[2].x, points[2].y, points[2].x, points[2].y]))
    } else if len == 2 {
      ops.append(
        contentsOf: doubleLine(points[0].x, points[0].y, points[1].x, points[1].y, o))
    }
    return ops
  }

  static func computeEllipsePoints(
    _ incrementIn: Double, _ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double,
    _ off: Double, _ overlap: Double, _ o: RoughOptions
  ) -> ([CGPoint], [CGPoint]) {
    var increment = incrementIn
    let coreOnly = o.roughness == 0
    var corePoints: [CGPoint] = []
    var allPoints: [CGPoint] = []
    if coreOnly {
      increment = increment / 4
      allPoints.append(CGPoint(x: cx + rx * cos(-increment), y: cy + ry * sin(-increment)))
      var angle = 0.0
      while angle <= Double.pi * 2 {
        let p = CGPoint(x: cx + rx * cos(angle), y: cy + ry * sin(angle))
        corePoints.append(p)
        allPoints.append(p)
        angle = angle + increment
      }
      allPoints.append(CGPoint(x: cx + rx * cos(0), y: cy + ry * sin(0)))
      allPoints.append(CGPoint(x: cx + rx * cos(increment), y: cy + ry * sin(increment)))
    } else {
      let radOffset = offsetOpt(0.5, o) - (Double.pi / 2)
      func pt(_ f: Double, _ a: Double) -> CGPoint {
        let x = offsetOpt(off, o) + cx + f * rx * cos(a)
        let y = offsetOpt(off, o) + cy + f * ry * sin(a)
        return CGPoint(x: x, y: y)
      }
      allPoints.append(pt(0.9, radOffset - increment))
      let endAngle = Double.pi * 2 + radOffset - 0.01
      var angle = radOffset
      while angle < endAngle {
        let p = pt(1, angle)
        corePoints.append(p)
        allPoints.append(p)
        angle = angle + increment
      }
      allPoints.append(pt(1, radOffset + Double.pi * 2 + overlap * 0.5))
      allPoints.append(pt(0.98, radOffset + overlap))
      allPoints.append(pt(0.9, radOffset + overlap * 0.5))
    }
    return (allPoints, corePoints)
  }

  static func arcOps(
    _ increment: Double, _ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double,
    _ strt: Double, _ stp: Double, _ off: Double, _ o: RoughOptions
  ) -> [RoughOp] {
    let radOffset = strt + offsetOpt(0.1, o)
    var points: [CGPoint] = []
    func pt(_ f: Double, _ a: Double) -> CGPoint {
      let x = offsetOpt(off, o) + cx + f * rx * cos(a)
      let y = offsetOpt(off, o) + cy + f * ry * sin(a)
      return CGPoint(x: x, y: y)
    }
    points.append(pt(0.9, radOffset - increment))
    var angle = radOffset
    while angle <= stp {
      points.append(pt(1, angle))
      angle = angle + increment
    }
    points.append(CGPoint(x: cx + rx * cos(stp), y: cy + ry * sin(stp)))
    points.append(CGPoint(x: cx + rx * cos(stp), y: cy + ry * sin(stp)))
    return curveOps(points, nil, o)
  }

  static func bezierTo(
    _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ x: Double, _ y: Double,
    _ current: [Double], _ o: RoughOptions
  ) -> [RoughOp] {
    var ops: [RoughOp] = []
    let base = o.maxRandomnessOffset != 0 ? o.maxRandomnessOffset : 1
    let ros = [base, base + 0.3]
    var f = [0.0, 0.0]
    let iterations = o.disableMultiStroke ? 1 : 2
    let pv = o.preserveVertices
    for i in 0..<iterations {
      if i == 0 {
        ops.append(RoughOp(.move, [current[0], current[1]]))
      } else {
        let a = current[0] + (pv ? 0 : offsetOpt(ros[0], o))
        let b = current[1] + (pv ? 0 : offsetOpt(ros[0], o))
        ops.append(RoughOp(.move, [a, b]))
      }
      if pv {
        f = [x, y]
      } else {
        let fx = x + offsetOpt(ros[i], o)
        let fy = y + offsetOpt(ros[i], o)
        f = [fx, fy]
      }
      let d0 = x1 + offsetOpt(ros[i], o)
      let d1 = y1 + offsetOpt(ros[i], o)
      let d2 = x2 + offsetOpt(ros[i], o)
      let d3 = y2 + offsetOpt(ros[i], o)
      ops.append(RoughOp(.bcurveTo, [d0, d1, d2, d3, f[0], f[1]]))
    }
    return ops
  }
}
