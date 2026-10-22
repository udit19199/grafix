import CoreGraphics
import Foundation

// Ports of path-data-parser (parsePath / absolutize / normalize), points-on-curve
// (pointsOnBezierCurves / simplify / curveToBezier) and points-on-path (pointsOnPath).
// Reference: ~/Workspace/oss/npm-ref/node_modules/{path-data-parser,points-on-curve,points-on-path}/lib

struct PathSegment: Equatable {
  var key: Character
  var data: [Double]
}

// MARK: - path-data-parser: parser.js

private enum PathToken: Equatable {
  case command(Character)
  case number(Double)
  case eod
}

private let pathParamCounts: [Character: Int] = [
  "A": 7, "a": 7, "C": 6, "c": 6, "H": 1, "h": 1, "L": 2, "l": 2, "M": 2, "m": 2,
  "Q": 4, "q": 4, "S": 4, "s": 4, "T": 2, "t": 2, "V": 1, "v": 1, "Z": 0, "z": 0,
]

/// `tokenize(d)`: returns `[]` on any malformed input (as the JS does).
private func tokenizePath(_ d: String) -> [PathToken] {
  let chars = Array(d.unicodeScalars)
  var tokens: [PathToken] = []
  var i = 0
  let n = chars.count
  func isDigit(_ c: Unicode.Scalar) -> Bool { c.value >= 48 && c.value <= 57 }
  while i < n {
    let c = chars[i]
    if c == " " || c == "\t" || c == "\r" || c == "\n" || c == "," {
      i += 1
    } else if pathParamCounts[Character(c)] != nil {
      tokens.append(.command(Character(c)))
      i += 1
    } else {
      // ([-+]?[0-9]+(\.[0-9]*)?|[-+]?\.[0-9]+)([eE][-+]?[0-9]+)?
      var j = i
      if j < n && (chars[j] == "-" || chars[j] == "+") { j += 1 }
      var ok = false
      let digitsStart = j
      while j < n && isDigit(chars[j]) { j += 1 }
      if j > digitsStart {
        ok = true
        if j < n && chars[j] == "." {
          j += 1
          while j < n && isDigit(chars[j]) { j += 1 }
        }
      } else if j < n && chars[j] == "." {
        var k = j + 1
        let fs = k
        while k < n && isDigit(chars[k]) { k += 1 }
        if k > fs {
          ok = true
          j = k
        }
      }
      if !ok { return [] }
      if j < n && (chars[j] == "e" || chars[j] == "E") {
        var k = j + 1
        if k < n && (chars[k] == "-" || chars[k] == "+") { k += 1 }
        let es = k
        while k < n && isDigit(chars[k]) { k += 1 }
        if k > es { j = k }
      }
      var s = String(String.UnicodeScalarView(chars[i..<j]))
      if s.hasSuffix(".") { s += "0" }
      if s.hasPrefix("+") { s.removeFirst() }
      guard let v = Double(s) else { return [] }
      tokens.append(.number(v))
      i = j
    }
  }
  tokens.append(.eod)
  return tokens
}

/// `parsePath(d)`. Malformed input yields the segments parsed so far (JS throws).
func parsePath(_ d: String) -> [PathSegment] {
  var segments: [PathSegment] = []
  let tokens = tokenizePath(d)
  if tokens.isEmpty { return [] }
  var mode: Character = "B"  // 'BOD' sentinel
  var bod = true
  var index = 0
  var token = tokens[index]
  while token != .eod {
    var paramsCount = 0
    if bod {
      if case .command(let c) = token, c == "M" || c == "m" {
        index += 1
        paramsCount = pathParamCounts[c]!
        mode = c
        bod = false
      } else {
        return parsePath("M0,0" + d)
      }
    } else if case .number = token {
      paramsCount = pathParamCounts[mode] ?? 0
    } else if case .command(let c) = token {
      index += 1
      paramsCount = pathParamCounts[c]!
      mode = c
    }
    if index + paramsCount < tokens.count {
      var params: [Double] = []
      for i in index..<(index + paramsCount) {
        if case .number(let v) = tokens[i] {
          params.append(v)
        } else {
          return segments
        }
      }
      segments.append(PathSegment(key: mode, data: params))
      if paramsCount == 0, case .number = token { return segments }  // JS would loop forever
      index += paramsCount
      token = tokens[index]
      if mode == "M" { mode = "L" }
      if mode == "m" { mode = "l" }
    } else {
      return segments
    }
  }
  return segments
}

// MARK: - absolutize.js

func absolutizePath(_ segments: [PathSegment]) -> [PathSegment] {
  var cx = 0.0, cy = 0.0
  var subx = 0.0, suby = 0.0
  var out: [PathSegment] = []
  func rel(_ data: [Double]) -> [Double] {
    data.enumerated().map { (i, d) in (i % 2 == 1) ? (d + cy) : (d + cx) }
  }
  for seg in segments {
    let data = seg.data
    switch seg.key {
    case "M":
      out.append(PathSegment(key: "M", data: data))
      cx = data[0]; cy = data[1]
      subx = data[0]; suby = data[1]
    case "m":
      cx += data[0]; cy += data[1]
      out.append(PathSegment(key: "M", data: [cx, cy]))
      subx = cx; suby = cy
    case "L":
      out.append(PathSegment(key: "L", data: data))
      cx = data[0]; cy = data[1]
    case "l":
      cx += data[0]; cy += data[1]
      out.append(PathSegment(key: "L", data: [cx, cy]))
    case "C":
      out.append(PathSegment(key: "C", data: data))
      cx = data[4]; cy = data[5]
    case "c":
      let nd = rel(data)
      out.append(PathSegment(key: "C", data: nd))
      cx = nd[4]; cy = nd[5]
    case "Q":
      out.append(PathSegment(key: "Q", data: data))
      cx = data[2]; cy = data[3]
    case "q":
      let nd = rel(data)
      out.append(PathSegment(key: "Q", data: nd))
      cx = nd[2]; cy = nd[3]
    case "A":
      out.append(PathSegment(key: "A", data: data))
      cx = data[5]; cy = data[6]
    case "a":
      cx += data[5]; cy += data[6]
      out.append(PathSegment(key: "A", data: [data[0], data[1], data[2], data[3], data[4], cx, cy]))
    case "H":
      out.append(PathSegment(key: "H", data: data))
      cx = data[0]
    case "h":
      cx += data[0]
      out.append(PathSegment(key: "H", data: [cx]))
    case "V":
      out.append(PathSegment(key: "V", data: data))
      cy = data[0]
    case "v":
      cy += data[0]
      out.append(PathSegment(key: "V", data: [cy]))
    case "S":
      out.append(PathSegment(key: "S", data: data))
      cx = data[2]; cy = data[3]
    case "s":
      let nd = rel(data)
      out.append(PathSegment(key: "S", data: nd))
      cx = nd[2]; cy = nd[3]
    case "T":
      out.append(PathSegment(key: "T", data: data))
      cx = data[0]; cy = data[1]
    case "t":
      cx += data[0]; cy += data[1]
      out.append(PathSegment(key: "T", data: [cx, cy]))
    case "Z", "z":
      out.append(PathSegment(key: "Z", data: []))
      cx = subx; cy = suby
    default:
      break
    }
  }
  return out
}

// MARK: - normalize.js

/// `normalize(segments)`: reduces to M, L, C, Z.
func normalizePath(_ segments: [PathSegment]) -> [PathSegment] {
  var out: [PathSegment] = []
  var lastType: Character = " "
  var cx = 0.0, cy = 0.0
  var subx = 0.0, suby = 0.0
  var lcx = 0.0, lcy = 0.0
  for seg in segments {
    let data = seg.data
    switch seg.key {
    case "M":
      out.append(PathSegment(key: "M", data: data))
      cx = data[0]; cy = data[1]
      subx = data[0]; suby = data[1]
    case "C":
      out.append(PathSegment(key: "C", data: data))
      cx = data[4]; cy = data[5]
      lcx = data[2]; lcy = data[3]
    case "L":
      out.append(PathSegment(key: "L", data: data))
      cx = data[0]; cy = data[1]
    case "H":
      cx = data[0]
      out.append(PathSegment(key: "L", data: [cx, cy]))
    case "V":
      cy = data[0]
      out.append(PathSegment(key: "L", data: [cx, cy]))
    case "S":
      var cx1 = 0.0, cy1 = 0.0
      if lastType == "C" || lastType == "S" {
        cx1 = cx + (cx - lcx)
        cy1 = cy + (cy - lcy)
      } else {
        cx1 = cx
        cy1 = cy
      }
      out.append(PathSegment(key: "C", data: [cx1, cy1] + data))
      lcx = data[0]; lcy = data[1]
      cx = data[2]; cy = data[3]
    case "T":
      let x = data[0], y = data[1]
      var x1 = 0.0, y1 = 0.0
      if lastType == "Q" || lastType == "T" {
        x1 = cx + (cx - lcx)
        y1 = cy + (cy - lcy)
      } else {
        x1 = cx
        y1 = cy
      }
      let cx1 = cx + 2 * (x1 - cx) / 3
      let cy1 = cy + 2 * (y1 - cy) / 3
      let cx2 = x + 2 * (x1 - x) / 3
      let cy2 = y + 2 * (y1 - y) / 3
      out.append(PathSegment(key: "C", data: [cx1, cy1, cx2, cy2, x, y]))
      lcx = x1; lcy = y1
      cx = x; cy = y
    case "Q":
      let x1 = data[0], y1 = data[1], x = data[2], y = data[3]
      let cx1 = cx + 2 * (x1 - cx) / 3
      let cy1 = cy + 2 * (y1 - cy) / 3
      let cx2 = x + 2 * (x1 - x) / 3
      let cy2 = y + 2 * (y1 - y) / 3
      out.append(PathSegment(key: "C", data: [cx1, cy1, cx2, cy2, x, y]))
      lcx = x1; lcy = y1
      cx = x; cy = y
    case "A":
      let r1 = abs(data[0]), r2 = abs(data[1])
      let angle = data[2]
      let largeArcFlag = data[3], sweepFlag = data[4]
      let x = data[5], y = data[6]
      if r1 == 0 || r2 == 0 {
        out.append(PathSegment(key: "C", data: [cx, cy, x, y, x, y]))
        cx = x; cy = y
      } else if cx != x || cy != y {
        let curves = arcToCubicCurves(
          cx, cy, x, y, r1, r2, angle, largeArcFlag != 0, sweepFlag != 0, nil)
        for c in curves { out.append(PathSegment(key: "C", data: c)) }
        cx = x; cy = y
      }
    case "Z":
      out.append(PathSegment(key: "Z", data: []))
      cx = subx; cy = suby
    default:
      break
    }
    lastType = seg.key
  }
  return out
}

private func degToRad(_ degrees: Double) -> Double { (Double.pi * degrees) / 180 }

private func rotatePt(_ x: Double, _ y: Double, _ a: Double) -> (Double, Double) {
  (x * cos(a) - y * sin(a), x * sin(a) + y * cos(a))
}

private func arcToCubicCurves(
  _ x1In: Double, _ y1In: Double, _ x2In: Double, _ y2In: Double,
  _ r1In: Double, _ r2In: Double, _ angle: Double,
  _ largeArcFlag: Bool, _ sweepFlag: Bool, _ recursive: [Double]?
) -> [[Double]] {
  var x1 = x1In, y1 = y1In, x2 = x2In, y2 = y2In, r1 = r1In, r2 = r2In
  let angleRad = degToRad(angle)
  var params: [[Double]] = []
  var f1 = 0.0, f2 = 0.0, cx = 0.0, cy = 0.0
  if let r = recursive {
    f1 = r[0]; f2 = r[1]; cx = r[2]; cy = r[3]
  } else {
    (x1, y1) = rotatePt(x1, y1, -angleRad)
    (x2, y2) = rotatePt(x2, y2, -angleRad)
    let x = (x1 - x2) / 2
    let y = (y1 - y2) / 2
    var h = (x * x) / (r1 * r1) + (y * y) / (r2 * r2)
    if h > 1 {
      h = h.squareRoot()
      r1 = h * r1
      r2 = h * r2
    }
    let sign: Double = (largeArcFlag == sweepFlag) ? -1 : 1
    let r1Pow = r1 * r1
    let r2Pow = r2 * r2
    let left = r1Pow * r2Pow - r1Pow * y * y - r2Pow * x * x
    let right = r1Pow * y * y + r2Pow * x * x
    let k = sign * abs(left / right).squareRoot()
    cx = k * r1 * y / r2 + (x1 + x2) / 2
    cy = k * -r2 * x / r1 + (y1 + y2) / 2
    func fixed9(_ v: Double) -> Double { Double(String(format: "%.9f", v)) ?? v }
    f1 = asin(fixed9((y1 - cy) / r2))
    f2 = asin(fixed9((y2 - cy) / r2))
    if x1 < cx { f1 = Double.pi - f1 }
    if x2 < cx { f2 = Double.pi - f2 }
    if f1 < 0 { f1 = Double.pi * 2 + f1 }
    if f2 < 0 { f2 = Double.pi * 2 + f2 }
    if sweepFlag && f1 > f2 { f1 = f1 - Double.pi * 2 }
    if !sweepFlag && f2 > f1 { f2 = f2 - Double.pi * 2 }
  }
  var df = f2 - f1
  if abs(df) > (Double.pi * 120 / 180) {
    let f2old = f2
    let x2old = x2
    let y2old = y2
    if sweepFlag && f2 > f1 {
      f2 = f1 + (Double.pi * 120 / 180) * 1
    } else {
      f2 = f1 + (Double.pi * 120 / 180) * -1
    }
    x2 = cx + r1 * cos(f2)
    y2 = cy + r2 * sin(f2)
    params = arcToCubicCurves(
      x2, y2, x2old, y2old, r1, r2, angle, false, sweepFlag, [f2, f2old, cx, cy])
  }
  df = f2 - f1
  let c1 = cos(f1), s1 = sin(f1), c2 = cos(f2), s2 = sin(f2)
  let t = tan(df / 4)
  let hx = 4 / 3 * r1 * t
  let hy = 4 / 3 * r2 * t
  let m1 = [x1, y1]
  var m2 = [x1 + hx * s1, y1 - hy * c1]
  let m3 = [x2 + hx * s2, y2 - hy * c2]
  let m4 = [x2, y2]
  m2[0] = 2 * m1[0] - m2[0]
  m2[1] = 2 * m1[1] - m2[1]
  if recursive != nil {
    return [m2, m3, m4] + params
  }
  params = [m2, m3, m4] + params
  var curves: [[Double]] = []
  var i = 0
  while i < params.count {
    let a = rotatePt(params[i][0], params[i][1], angleRad)
    let b = rotatePt(params[i + 1][0], params[i + 1][1], angleRad)
    let c = rotatePt(params[i + 2][0], params[i + 2][1], angleRad)
    curves.append([a.0, a.1, b.0, b.1, c.0, c.1])
    i += 3
  }
  return curves
}

// MARK: - points-on-curve

private func distanceSq(_ p1: CGPoint, _ p2: CGPoint) -> Double {
  let dx = Double(p1.x - p2.x), dy = Double(p1.y - p2.y)
  return pow(dx, 2) + pow(dy, 2)
}

private func distance(_ p1: CGPoint, _ p2: CGPoint) -> Double { distanceSq(p1, p2).squareRoot() }

private func lerp(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
  CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
}

private func distanceToSegmentSq(_ p: CGPoint, _ v: CGPoint, _ w: CGPoint) -> Double {
  let l2 = distanceSq(v, w)
  if l2 == 0 { return distanceSq(p, v) }
  var t = Double((p.x - v.x) * (w.x - v.x) + (p.y - v.y) * (w.y - v.y)) / l2
  t = max(0, min(1, t))
  return distanceSq(p, lerp(v, w, t))
}

private func flatness(_ points: [CGPoint], _ offset: Int) -> Double {
  let p1 = points[offset], p2 = points[offset + 1], p3 = points[offset + 2], p4 = points[offset + 3]
  var ux = Double(3 * p2.x - 2 * p1.x - p4.x)
  ux *= ux
  var uy = Double(3 * p2.y - 2 * p1.y - p4.y)
  uy *= uy
  var vx = Double(3 * p3.x - 2 * p4.x - p1.x)
  vx *= vx
  var vy = Double(3 * p3.y - 2 * p4.y - p1.y)
  vy *= vy
  if ux < vx { ux = vx }
  if uy < vy { uy = vy }
  return ux + uy
}

private func bezierWithSplitting(
  _ points: [CGPoint], _ offset: Int, _ tolerance: Double, _ out: inout [CGPoint]
) {
  if flatness(points, offset) < tolerance {
    let p0 = points[offset]
    if let last = out.last {
      if distance(last, p0) > 1 { out.append(p0) }
    } else {
      out.append(p0)
    }
    out.append(points[offset + 3])
  } else {
    let t = 0.5
    let p1 = points[offset], p2 = points[offset + 1], p3 = points[offset + 2], p4 = points[offset + 3]
    let q1 = lerp(p1, p2, t), q2 = lerp(p2, p3, t), q3 = lerp(p3, p4, t)
    let r1 = lerp(q1, q2, t), r2 = lerp(q2, q3, t)
    let red = lerp(r1, r2, t)
    bezierWithSplitting([p1, q1, r1, red], 0, tolerance, &out)
    bezierWithSplitting([red, r2, q3, p4], 0, tolerance, &out)
  }
}

/// points-on-curve `simplify`.
func simplifyPoints(_ points: [CGPoint], _ distance: Double) -> [CGPoint] {
  var out: [CGPoint] = []
  simplifyPoints(points, 0, points.count, distance, &out)
  return out
}

/// Ramer-Douglas-Peucker, as in points-on-curve `simplifyPoints`.
func simplifyPoints(
  _ points: [CGPoint], _ start: Int, _ end: Int, _ epsilon: Double, _ out: inout [CGPoint]
) {
  let s = points[start]
  let e = points[end - 1]
  var maxDistSq = 0.0
  var maxNdx = 1
  var i = start + 1
  while i < end - 1 {
    let distSq = distanceToSegmentSq(points[i], s, e)
    if distSq > maxDistSq {
      maxDistSq = distSq
      maxNdx = i
    }
    i += 1
  }
  if maxDistSq.squareRoot() > epsilon {
    simplifyPoints(points, start, maxNdx + 1, epsilon, &out)
    simplifyPoints(points, maxNdx, end, epsilon, &out)
  } else {
    if out.isEmpty { out.append(s) }
    out.append(e)
  }
}

/// points-on-curve `pointsOnBezierCurves(points, tolerance, distance)`.
func pointsOnBezierCurves(_ points: [CGPoint], tolerance: Double = 0.15, distance: Double? = nil)
  -> [CGPoint]
{
  var newPoints: [CGPoint] = []
  let numSegments = Double(points.count - 1) / 3
  var i = 0
  while Double(i) < numSegments {
    bezierWithSplitting(points, i * 3, tolerance, &newPoints)
    i += 1
  }
  if let d = distance, d > 0 {
    return simplifyPoints(newPoints, d)
  }
  return newPoints
}

/// points-on-curve `curveToBezier(pointsIn, curveTightness)`.
func curveToBezier(_ pointsIn: [CGPoint], curveTightness: Double = 0) -> [CGPoint] {
  let len = pointsIn.count
  precondition(len >= 3, "A curve must have at least three points.")
  var out: [CGPoint] = []
  if len == 3 {
    out = [pointsIn[0], pointsIn[1], pointsIn[2], pointsIn[2]]
  } else {
    var points: [CGPoint] = [pointsIn[0], pointsIn[0]]
    for i in 1..<pointsIn.count {
      points.append(pointsIn[i])
      if i == pointsIn.count - 1 { points.append(pointsIn[i]) }
    }
    let s = 1 - curveTightness
    out.append(points[0])
    var i = 1
    while i + 2 < points.count {
      let c = points[i]
      let b1 = CGPoint(
        x: c.x + (s * points[i + 1].x - s * points[i - 1].x) / 6,
        y: c.y + (s * points[i + 1].y - s * points[i - 1].y) / 6)
      let b2 = CGPoint(
        x: points[i + 1].x + (s * points[i].x - s * points[i + 2].x) / 6,
        y: points[i + 1].y + (s * points[i].y - s * points[i + 2].y) / 6)
      let b3 = points[i + 1]
      out.append(contentsOf: [b1, b2, b3])
      i += 1
    }
  }
  return out
}

// MARK: - points-on-path

/// points-on-path `pointsOnPath(path, tolerance, distance)`.
func pointsOnPath(_ path: String, tolerance: Double? = nil, distance: Double? = nil) -> [[CGPoint]] {
  let normalized = normalizePath(absolutizePath(parsePath(path)))
  var sets: [[CGPoint]] = []
  var currentPoints: [CGPoint] = []
  var start = CGPoint.zero
  var pendingCurve: [CGPoint] = []

  func appendPendingCurve() {
    if pendingCurve.count >= 4 {
      currentPoints.append(
        contentsOf: pointsOnBezierCurves(pendingCurve, tolerance: tolerance ?? 0.15))
    }
    pendingCurve = []
  }
  func appendPendingPoints() {
    appendPendingCurve()
    if !currentPoints.isEmpty {
      sets.append(currentPoints)
      currentPoints = []
    }
  }

  for seg in normalized {
    let data = seg.data
    switch seg.key {
    case "M":
      appendPendingPoints()
      start = CGPoint(x: data[0], y: data[1])
      currentPoints.append(start)
    case "L":
      appendPendingCurve()
      currentPoints.append(CGPoint(x: data[0], y: data[1]))
    case "C":
      if pendingCurve.isEmpty {
        let lastPoint = currentPoints.last ?? start
        pendingCurve.append(CGPoint(x: lastPoint.x, y: lastPoint.y))
      }
      pendingCurve.append(CGPoint(x: data[0], y: data[1]))
      pendingCurve.append(CGPoint(x: data[2], y: data[3]))
      pendingCurve.append(CGPoint(x: data[4], y: data[5]))
    case "Z":
      appendPendingCurve()
      currentPoints.append(CGPoint(x: start.x, y: start.y))
    default:
      break
    }
  }
  appendPendingPoints()

  guard let distance, distance != 0 else { return sets }
  var out: [[CGPoint]] = []
  for set in sets {
    let simplified = simplifyPoints(set, distance)
    if !simplified.isEmpty { out.append(simplified) }
  }
  return out
}
