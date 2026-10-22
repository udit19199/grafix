import CoreGraphics
import Foundation

// Port of roughjs/bin/fillers/*.js and hachure-fill (hachureLines).

protocol RoughFiller {
  func fillPolygons(_ polygonList: inout [[CGPoint]], _ o: RoughOptions) -> OpSet
}

/// `getFiller(o, helper)`.
func getFiller(_ o: RoughOptions) -> RoughFiller {
  switch o.fillStyle {
  case "zigzag": return ZigZagFiller()
  case "cross-hatch": return HatchFiller()
  case "dots": return DotFiller()
  case "dashed": return DashedFiller()
  case "zigzag-line": return ZigZagLineFiller()
  default: return HachureFiller()
  }
}

func lineLength(_ p1: CGPoint, _ p2: CGPoint) -> Double {
  (pow(Double(p1.x - p2.x), 2) + pow(Double(p1.y - p2.y), 2)).squareRoot()
}

// MARK: - scan-line-hachure.js

func polygonHachureLines(_ polygonList: inout [[CGPoint]], _ o: RoughOptions) -> [[CGPoint]] {
  let angle = o.hachureAngle + 90
  var gap = o.hachureGap
  if gap < 0 { gap = o.strokeWidth * 4 }
  gap = max(gap, 0.1)
  var skipOffset = 1.0
  if o.roughness >= 1 {
    var r = 0.0
    if let rz = o.randomizer { r = rz.next() }
    if r == 0 { r = Double.random(in: 0..<1) }  // `x?.next() || Math.random()`
    if r > 0.7 { skipOffset = gap }
  }
  return hachureLines(&polygonList, gap, angle, skipOffset == 0 ? 1 : skipOffset)
}

// MARK: - hachure-fill

private func rotatePoints(_ points: inout [CGPoint], _ center: CGPoint, _ degrees: Double) {
  if points.isEmpty { return }
  let angle = (Double.pi / 180) * degrees
  let c = cos(angle), s = sin(angle)
  let cx = Double(center.x), cy = Double(center.y)
  for i in points.indices {
    let x = Double(points[i].x), y = Double(points[i].y)
    points[i].x = ((x - cx) * c) - ((y - cy) * s) + cx
    points[i].y = ((x - cx) * s) + ((y - cy) * c) + cy
  }
}

func hachureLines(
  _ polygonList: inout [[CGPoint]], _ hachureGap: Double, _ hachureAngle: Double,
  _ hachureStepOffset: Double = 1
) -> [[CGPoint]] {
  let angle = hachureAngle
  let gap = max(hachureGap, 0.1)
  let center = CGPoint.zero
  if angle != 0 {
    for i in polygonList.indices { rotatePoints(&polygonList[i], center, angle) }
  }
  var lines = straightHachureLines(polygonList, gap, hachureStepOffset)
  if angle != 0 {
    for i in polygonList.indices { rotatePoints(&polygonList[i], center, -angle) }
    for i in lines.indices { rotatePoints(&lines[i], center, -angle) }
  }
  return lines
}

private struct HEdge {
  var ymin: Double
  var ymax: Double
  var x: Double
  var islope: Double
}

/// Stable sort using a JS-style comparator returning negative/zero/positive.
private func stableSorted<T>(_ a: [T], _ cmp: (T, T) -> Double) -> [T] {
  var arr = a
  if arr.count < 2 { return arr }
  for i in 1..<arr.count {
    let v = arr[i]
    var j = i - 1
    while j >= 0 && cmp(arr[j], v) > 0 {
      arr[j + 1] = arr[j]
      j -= 1
    }
    arr[j + 1] = v
  }
  return arr
}

/// JS `Math.round`.
private func jsRound(_ x: Double) -> Double {
  let f = x.rounded(.down)
  return (x - f) >= 0.5 ? f + 1 : f
}

private func straightHachureLines(
  _ polygons: [[CGPoint]], _ gapIn: Double, _ hachureStepOffset: Double
) -> [[CGPoint]] {
  var vertexArray: [[CGPoint]] = []
  for polygon in polygons {
    var vertices = polygon
    if vertices.isEmpty { continue }
    if !(vertices[0].x == vertices[vertices.count - 1].x
      && vertices[0].y == vertices[vertices.count - 1].y)
    {
      vertices.append(CGPoint(x: vertices[0].x, y: vertices[0].y))
    }
    if vertices.count > 2 { vertexArray.append(vertices) }
  }
  var lines: [[CGPoint]] = []
  let gap = max(gapIn, 0.1)

  var edgesIn: [HEdge] = []
  for vertices in vertexArray {
    for i in 0..<(vertices.count - 1) {
      let p1 = vertices[i], p2 = vertices[i + 1]
      if p1.y != p2.y {
        let ymin = Double(min(p1.y, p2.y))
        edgesIn.append(
          HEdge(
            ymin: ymin, ymax: Double(max(p1.y, p2.y)),
            x: Double(ymin == p1.y ? p1.x : p2.x),
            islope: Double((p2.x - p1.x) / (p2.y - p1.y))))
      }
    }
  }
  var edges = stableSorted(edgesIn) { e1, e2 in
    if e1.ymin < e2.ymin { return -1 }
    if e1.ymin > e2.ymin { return 1 }
    if e1.x < e2.x { return -1 }
    if e1.x > e2.x { return 1 }
    if e1.ymax == e2.ymax { return 0 }
    return (e1.ymax - e2.ymax) / abs(e1.ymax - e2.ymax)
  }
  if edges.isEmpty { return lines }

  var activeEdges: [(s: Double, edge: HEdge)] = []
  var y = edges[0].ymin
  var iteration = 0.0
  while !activeEdges.isEmpty || !edges.isEmpty {
    if !edges.isEmpty {
      var ix = -1
      for i in 0..<edges.count {
        if edges[i].ymin > y { break }
        ix = i
      }
      let removed = Array(edges[0..<(ix + 1)])
      edges.removeFirst(ix + 1)
      for e in removed { activeEdges.append((y, e)) }
    }
    activeEdges = activeEdges.filter { !($0.edge.ymax <= y) }
    activeEdges = stableSorted(activeEdges) { a, b in
      if a.edge.x == b.edge.x { return 0 }
      return (a.edge.x - b.edge.x) / abs(a.edge.x - b.edge.x)
    }
    if hachureStepOffset != 1 || iteration.truncatingRemainder(dividingBy: gap) == 0 {
      if activeEdges.count > 1 {
        var i = 0
        while i < activeEdges.count {
          let nexti = i + 1
          if nexti >= activeEdges.count { break }
          let ce = activeEdges[i].edge
          let ne = activeEdges[nexti].edge
          lines.append([CGPoint(x: jsRound(ce.x), y: y), CGPoint(x: jsRound(ne.x), y: y)])
          i += 2
        }
      }
    }
    y += hachureStepOffset
    for i in activeEdges.indices {
      activeEdges[i].edge.x = activeEdges[i].edge.x + (hachureStepOffset * activeEdges[i].edge.islope)
    }
    iteration += 1
  }
  return lines
}

// MARK: - Fillers

struct HachureFiller: RoughFiller {
  func fillPolygons(_ polygonList: inout [[CGPoint]], _ o: RoughOptions) -> OpSet {
    _fillPolygons(&polygonList, o)
  }

  func _fillPolygons(_ polygonList: inout [[CGPoint]], _ o: RoughOptions) -> OpSet {
    let lines = polygonHachureLines(&polygonList, o)
    return OpSet(type: .fillSketch, ops: renderLines(lines, o))
  }

  func renderLines(_ lines: [[CGPoint]], _ o: RoughOptions) -> [RoughOp] {
    var ops: [RoughOp] = []
    for line in lines {
      ops.append(
        contentsOf: RoughRenderer.doubleLineFillOps(
          line[0].x, line[0].y, line[1].x, line[1].y, o))
    }
    return ops
  }
}

struct HatchFiller: RoughFiller {
  func fillPolygons(_ polygonList: inout [[CGPoint]], _ o: RoughOptions) -> OpSet {
    let h = HachureFiller()
    var set = h._fillPolygons(&polygonList, o)
    let o2 = o.copy()
    o2.hachureAngle = o.hachureAngle + 90
    let set2 = h._fillPolygons(&polygonList, o2)
    set.ops = set.ops + set2.ops
    return set
  }
}

struct ZigZagFiller: RoughFiller {
  func fillPolygons(_ polygonList: inout [[CGPoint]], _ o: RoughOptions) -> OpSet {
    var gap = o.hachureGap
    if gap < 0 { gap = o.strokeWidth * 4 }
    gap = max(gap, 0.1)
    let o2 = o.copy()
    o2.hachureGap = gap
    let lines = polygonHachureLines(&polygonList, o2)
    let zigZagAngle = (Double.pi / 180) * o.hachureAngle
    var zigzagLines: [[CGPoint]] = []
    let dgx = gap * 0.5 * cos(zigZagAngle)
    let dgy = gap * 0.5 * sin(zigZagAngle)
    for l in lines {
      let p1 = l[0], p2 = l[1]
      if lineLength(p1, p2) != 0 {
        zigzagLines.append([CGPoint(x: p1.x - dgx, y: p1.y + dgy), p2])
        zigzagLines.append([CGPoint(x: p1.x + dgx, y: p1.y - dgy), p2])
      }
    }
    let ops = HachureFiller().renderLines(zigzagLines, o)
    return OpSet(type: .fillSketch, ops: ops)
  }
}

struct DashedFiller: RoughFiller {
  func fillPolygons(_ polygonList: inout [[CGPoint]], _ o: RoughOptions) -> OpSet {
    let lines = polygonHachureLines(&polygonList, o)
    return OpSet(type: .fillSketch, ops: dashedLine(lines, o))
  }

  func dashedLine(_ lines: [[CGPoint]], _ o: RoughOptions) -> [RoughOp] {
    let offset = o.dashOffset < 0 ? (o.hachureGap < 0 ? (o.strokeWidth * 4) : o.hachureGap) : o.dashOffset
    let gap = o.dashGap < 0 ? (o.hachureGap < 0 ? (o.strokeWidth * 4) : o.hachureGap) : o.dashGap
    var ops: [RoughOp] = []
    for line in lines {
      let length = lineLength(line[0], line[1])
      let count = Int((length / (offset + gap)).rounded(.down))
      let startOffset = (length + gap - (Double(count) * (offset + gap))) / 2
      var p1 = line[0]
      var p2 = line[1]
      if p1.x > p2.x {
        p1 = line[1]
        p2 = line[0]
      }
      let alpha = atan(Double((p2.y - p1.y) / (p2.x - p1.x)))
      let px = Double(p1.x), py = Double(p1.y)
      for i in 0..<max(count, 0) {
        let lstart = Double(i) * (offset + gap)
        let lend = lstart + offset
        let sx = px + (lstart * cos(alpha)) + (startOffset * cos(alpha))
        let sy = py + lstart * sin(alpha) + (startOffset * sin(alpha))
        let ex = px + (lend * cos(alpha)) + (startOffset * cos(alpha))
        let ey = py + (lend * sin(alpha)) + (startOffset * sin(alpha))
        ops.append(contentsOf: RoughRenderer.doubleLineFillOps(sx, sy, ex, ey, o))
      }
    }
    return ops
  }
}

struct ZigZagLineFiller: RoughFiller {
  func fillPolygons(_ polygonList: inout [[CGPoint]], _ o: RoughOptions) -> OpSet {
    let gap = o.hachureGap < 0 ? (o.strokeWidth * 4) : o.hachureGap
    let zo = o.zigzagOffset < 0 ? gap : o.zigzagOffset
    let o2 = o.copy()
    o2.hachureGap = gap + zo
    let lines = polygonHachureLines(&polygonList, o2)
    return OpSet(type: .fillSketch, ops: zigzagLines(lines, zo, o2))
  }

  func zigzagLines(_ lines: [[CGPoint]], _ zo: Double, _ o: RoughOptions) -> [RoughOp] {
    var ops: [RoughOp] = []
    for line in lines {
      let length = lineLength(line[0], line[1])
      let count = Int(jsRound(length / (2 * zo)))
      var p1 = line[0]
      var p2 = line[1]
      if p1.x > p2.x {
        p1 = line[1]
        p2 = line[0]
      }
      let alpha = atan(Double((p2.y - p1.y) / (p2.x - p1.x)))
      let px = Double(p1.x), py = Double(p1.y)
      for i in 0..<max(count, 0) {
        let lstart = Double(i) * 2 * zo
        let lend = Double(i + 1) * 2 * zo
        let dz = (2 * pow(zo, 2)).squareRoot()
        let sx = px + (lstart * cos(alpha)), sy = py + lstart * sin(alpha)
        let ex = px + (lend * cos(alpha)), ey = py + (lend * sin(alpha))
        let mx = sx + dz * cos(alpha + Double.pi / 4)
        let my = sy + dz * sin(alpha + Double.pi / 4)
        ops.append(contentsOf: RoughRenderer.doubleLineFillOps(sx, sy, mx, my, o))
        ops.append(contentsOf: RoughRenderer.doubleLineFillOps(mx, my, ex, ey, o))
      }
    }
    return ops
  }
}

struct DotFiller: RoughFiller {
  func fillPolygons(_ polygonList: inout [[CGPoint]], _ o: RoughOptions) -> OpSet {
    let o = o.copy()
    o.hachureAngle = 0
    let lines = polygonHachureLines(&polygonList, o)
    return dotsOnLines(lines, o)
  }

  func dotsOnLines(_ lines: [[CGPoint]], _ o: RoughOptions) -> OpSet {
    var ops: [RoughOp] = []
    var gap = o.hachureGap
    if gap < 0 { gap = o.strokeWidth * 4 }
    gap = max(gap, 0.1)
    var fweight = o.fillWeight
    if fweight < 0 { fweight = o.strokeWidth / 2 }
    let ro = gap / 4
    for line in lines {
      let length = lineLength(line[0], line[1])
      let dl = length / gap
      let count = Int(dl.rounded(.up)) - 1
      let offset = length - (Double(count) * gap)
      let x = Double((line[0].x + line[1].x) / 2) - (gap / 4)
      let minY = Double(min(line[0].y, line[1].y))
      for i in 0..<max(count, 0) {
        let y = minY + offset + (Double(i) * gap)
        let cx = (x - ro) + Double.random(in: 0..<1) * 2 * ro
        let cy = (y - ro) + Double.random(in: 0..<1) * 2 * ro
        ops.append(contentsOf: RoughRenderer.ellipse(cx, cy, fweight, fweight, o).ops)
      }
    }
    return OpSet(type: .fillSketch, ops: ops)
  }
}
