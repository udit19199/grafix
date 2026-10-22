import CoreGraphics
import Foundation

/// Taper setting for one end of a stroke (`start.taper` / `end.taper` in perfect-freehand).
public enum StrokeTaper: Sendable, Equatable {
  /// `false` / `0` / undefined: no taper.
  case none
  /// `true`: taper over `max(size, strokeLength)`.
  case full
  /// Taper over a fixed distance.
  case distance(Double)
}

/// Per-end options (`StrokeOptions.start` / `.end`).
public struct StrokeEndOptions: Sendable {
  public var cap: Bool
  public var taper: StrokeTaper
  public var easing: @Sendable (Double) -> Double

  public init(
    cap: Bool = true, taper: StrokeTaper = .none,
    easing: @escaping @Sendable (Double) -> Double
  ) {
    self.cap = cap
    self.taper = taper
    self.easing = easing
  }

  /// Library default for the start: `t * (2 - t)`.
  public static let defaultStart = StrokeEndOptions(easing: { $0 * (2 - $0) })
  /// Library default for the end: `--t * t * t + 1`.
  public static let defaultEnd = StrokeEndOptions(easing: { t in (t - 1) * (t - 1) * (t - 1) + 1 })
}

/// perfect-freehand 1.2.0 `StrokeOptions`, with the library defaults.
public struct StrokeOptions: Sendable {
  public var size: Double
  public var thinning: Double
  public var smoothing: Double
  public var streamline: Double
  public var easing: @Sendable (Double) -> Double
  public var simulatePressure: Bool
  public var last: Bool
  public var start: StrokeEndOptions
  public var end: StrokeEndOptions

  public init(
    size: Double = 16, thinning: Double = 0.5, smoothing: Double = 0.5,
    streamline: Double = 0.5,
    easing: @escaping @Sendable (Double) -> Double = { $0 },
    simulatePressure: Bool = true, last: Bool = false,
    start: StrokeEndOptions = .defaultStart, end: StrokeEndOptions = .defaultEnd
  ) {
    self.size = size
    self.thinning = thinning
    self.smoothing = smoothing
    self.streamline = streamline
    self.easing = easing
    self.simulatePressure = simulatePressure
    self.last = last
    self.start = start
    self.end = end
  }
}

/// One streamlined input sample (`StrokePoint`).
public struct StrokePoint: Sendable, Equatable {
  public var point: CGPoint
  public var pressure: Double
  public var distance: Double
  public var vector: CGPoint
  public var runningLength: Double
}

/// Port of perfect-freehand 1.2.0 (getStroke, getStrokePoints, getStrokeOutlinePoints).
public enum PerfectFreehand {
  private static let rateOfPressureChange = 0.275
  private static let fixedPi = Double.pi + 0.0001

  // MARK: vec helpers (vec.ts)

  private static func add(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
    CGPoint(x: a.x + b.x, y: a.y + b.y)
  }
  private static func sub(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
    CGPoint(x: a.x - b.x, y: a.y - b.y)
  }
  private static func mul(_ a: CGPoint, _ t: Double) -> CGPoint {
    CGPoint(x: a.x * t, y: a.y * t)
  }
  private static func per(_ a: CGPoint) -> CGPoint { CGPoint(x: a.y, y: -a.x) }
  private static func neg(_ a: CGPoint) -> CGPoint { CGPoint(x: -a.x, y: -a.y) }
  private static func dpr(_ a: CGPoint, _ b: CGPoint) -> Double { a.x * b.x + a.y * b.y }
  private static func uni(_ a: CGPoint) -> CGPoint {
    let l = hypot(a.x, a.y)
    return CGPoint(x: a.x / l, y: a.y / l)
  }
  private static func dist2(_ a: CGPoint, _ b: CGPoint) -> Double {
    let d = sub(a, b)
    return d.x * d.x + d.y * d.y
  }
  /// `lrp`: linear interpolation.
  private static func lrp(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
    add(a, mul(sub(b, a), t))
  }
  /// `prj`: project a point from `a` along direction `b` by distance `c`.
  private static func prj(_ a: CGPoint, _ b: CGPoint, _ c: Double) -> CGPoint {
    add(a, mul(b, c))
  }
  /// `rotAround`.
  private static func rotAround(_ a: CGPoint, _ c: CGPoint, _ r: Double) -> CGPoint {
    let s = sin(r)
    let co = cos(r)
    let px = a.x - c.x
    let py = a.y - c.y
    return CGPoint(x: px * co - py * s + c.x, y: px * s + py * co + c.y)
  }

  /// `getStrokeRadius`.
  private static func strokeRadius(
    _ size: Double, _ thinning: Double, _ pressure: Double, _ easing: (Double) -> Double
  ) -> Double {
    size * easing(0.5 - thinning * (0.5 - pressure))
  }

  // MARK: getStroke

  /// `getStroke`: points are `[x, y]` or `[x, y, pressure]`.
  public static func getStroke(_ points: [[Double]], _ options: StrokeOptions) -> [CGPoint] {
    getStrokeOutlinePoints(getStrokePoints(points, options), options)
  }

  // MARK: getStrokePoints

  /// `getStrokePoints`.
  public static func getStrokePoints(_ points: [[Double]], _ options: StrokeOptions) -> [StrokePoint] {
    let streamline = options.streamline
    let size = options.size
    let isComplete = options.last
    if points.isEmpty { return [] }

    let t = 0.15 + (1 - streamline) * 0.85

    // Working points: position plus optional pressure.
    struct P {
      var x: Double
      var y: Double
      var pressure: Double?
    }
    var pts: [P] = points.map { P(x: $0[0], y: $0[1], pressure: $0.count > 2 ? $0[2] : nil) }

    if pts.count == 2 {
      let last = pts[1]
      pts = [pts[0]]
      for i in 1..<5 {
        // lrp drops the pressure component.
        let q = lrp(
          CGPoint(x: pts[0].x, y: pts[0].y), CGPoint(x: last.x, y: last.y), Double(i) / 4)
        pts.append(P(x: q.x, y: q.y, pressure: nil))
      }
    }
    if pts.count == 1 {
      pts.append(P(x: pts[0].x + 1, y: pts[0].y + 1, pressure: pts[0].pressure))
    }

    func pressureOr(_ p: Double?, _ fallback: Double) -> Double {
      if let p, p >= 0 { return p }
      return fallback
    }

    var result: [StrokePoint] = [
      StrokePoint(
        point: CGPoint(x: pts[0].x, y: pts[0].y), pressure: pressureOr(pts[0].pressure, 0.25),
        distance: 0, vector: CGPoint(x: 1, y: 1), runningLength: 0)
    ]
    var hasReachedMinimumLength = false
    var runningLength = 0.0
    var prev = result[0]
    let max = pts.count - 1

    for i in 1..<pts.count {
      let cur = pts[i]
      let point: CGPoint
      if isComplete && i == max {
        point = CGPoint(x: cur.x, y: cur.y)
      } else {
        point = lrp(prev.point, CGPoint(x: cur.x, y: cur.y), t)
      }
      if prev.point == point { continue }
      let distance = hypot(point.y - prev.point.y, point.x - prev.point.x)
      runningLength += distance
      if i < max && !hasReachedMinimumLength {
        if runningLength < size { continue }
        hasReachedMinimumLength = true
      }
      prev = StrokePoint(
        point: point, pressure: pressureOr(cur.pressure, 0.5),
        distance: distance, vector: uni(sub(prev.point, point)), runningLength: runningLength)
      result.append(prev)
    }

    result[0].vector = result.count > 1 ? result[1].vector : CGPoint(x: 0, y: 0)
    return result
  }

  // MARK: getStrokeOutlinePoints

  /// `getStrokeOutlinePoints`.
  public static func getStrokeOutlinePoints(
    _ points: [StrokePoint], _ options: StrokeOptions
  ) -> [CGPoint] {
    let size = options.size
    let smoothing = options.smoothing
    let thinning = options.thinning
    let simulatePressure = options.simulatePressure
    let easing = options.easing
    let isComplete = options.last
    let capStart = options.start.cap
    let capEnd = options.end.cap
    let taperStartEase = options.start.easing
    let taperEndEase = options.end.easing

    if points.isEmpty || size <= 0 { return [] }

    let totalLength = points[points.count - 1].runningLength

    func taperValue(_ t: StrokeTaper) -> Double {
      switch t {
      case .none: return 0
      case .full: return Swift.max(size, totalLength)
      case .distance(let d): return d
      }
    }
    let taperStart = taperValue(options.start.taper)
    let taperEnd = taperValue(options.end.taper)

    let minDistance = pow(size * smoothing, 2)

    var leftPts: [CGPoint] = []
    var rightPts: [CGPoint] = []

    // Average the pressure of the first ten points to seed the simulated pressure.
    var prevPressure = points.prefix(10).reduce(points[0].pressure) { acc, curr in
      var pressure = curr.pressure
      if simulatePressure {
        let sp = Swift.min(1, curr.distance / size)
        let rp = Swift.min(1, 1 - sp)
        pressure = Swift.min(1, acc + (rp - acc) * (sp * rateOfPressureChange))
      }
      return (acc + pressure) / 2
    }

    var radius = strokeRadius(size, thinning, points[points.count - 1].pressure, easing)
    var firstRadius: Double? = nil
    var prevVector = points[0].vector
    var pl = points[0].point
    var pr = pl
    var tl = pl
    var tr = pr
    var isPrevPointSharpCorner = false

    for i in 0..<points.count {
      var pressure = points[i].pressure
      let point = points[i].point
      let vector = points[i].vector
      let distance = points[i].distance
      let rl = points[i].runningLength

      // Remove noisy trailing points.
      if i < points.count - 1 && totalLength - rl < 3 { continue }

      if thinning != 0 {
        if simulatePressure {
          let sp = Swift.min(1, distance / size)
          let rp = Swift.min(1, 1 - sp)
          pressure = Swift.min(1, prevPressure + (rp - prevPressure) * (sp * rateOfPressureChange))
        }
        radius = strokeRadius(size, thinning, pressure, easing)
      } else {
        radius = size / 2
      }

      if firstRadius == nil { firstRadius = radius }

      let ts = rl < taperStart ? taperStartEase(rl / taperStart) : 1
      let te = totalLength - rl < taperEnd ? taperEndEase((totalLength - rl) / taperEnd) : 1
      radius = Swift.max(0.01, radius * Swift.min(ts, te))

      let nextVector = (i < points.count - 1 ? points[i + 1] : points[i]).vector
      let nextDpr = i < points.count - 1 ? dpr(vector, nextVector) : 1.0
      let prevDpr = dpr(vector, prevVector)

      let isPointSharpCorner = prevDpr < 0 && !isPrevPointSharpCorner
      let isNextPointSharpCorner = nextDpr < 0

      if isPointSharpCorner || isNextPointSharpCorner {
        let offset = mul(per(prevVector), radius)
        let step = 1.0 / 13
        var t = 0.0
        while t <= 1 {
          tl = rotAround(sub(point, offset), point, fixedPi * t)
          leftPts.append(tl)
          tr = rotAround(add(point, offset), point, fixedPi * -t)
          rightPts.append(tr)
          t += step
        }
        pl = tl
        pr = tr
        if isNextPointSharpCorner { isPrevPointSharpCorner = true }
        continue
      }

      isPrevPointSharpCorner = false

      if i == points.count - 1 {
        let offset = mul(per(vector), radius)
        leftPts.append(sub(point, offset))
        rightPts.append(add(point, offset))
        continue
      }

      let offset = mul(per(lrp(nextVector, vector, nextDpr)), radius)

      tl = sub(point, offset)
      if i <= 1 || dist2(pl, tl) > minDistance {
        leftPts.append(tl)
        pl = tl
      }
      tr = add(point, offset)
      if i <= 1 || dist2(pr, tr) > minDistance {
        rightPts.append(tr)
        pr = tr
      }

      prevPressure = pressure
      prevVector = vector
    }

    let firstPoint = points[0].point
    let lastPoint = points.count > 1 ? points[points.count - 1].point : add(points[0].point, CGPoint(x: 1, y: 1))

    var startCap: [CGPoint] = []
    var endCap: [CGPoint] = []

    if points.count == 1 {
      if !(taperStart != 0 || taperEnd != 0) || isComplete {
        let start = prj(
          firstPoint, uni(per(sub(firstPoint, lastPoint))), -(firstRadius ?? radius))
        var dotPts: [CGPoint] = []
        let step = 1.0 / 13
        var t = step
        while t <= 1 {
          dotPts.append(rotAround(start, firstPoint, fixedPi * 2 * t))
          t += step
        }
        return dotPts
      }
    } else {
      // Start cap.
      if taperStart != 0 || (taperEnd != 0 && points.count == 1) {
        // skip the start cap
      } else if capStart {
        let step = 1.0 / 13
        var t = step
        while t <= 1 {
          startCap.append(rotAround(rightPts[0], firstPoint, fixedPi * t))
          t += step
        }
      } else {
        let cornersVector = sub(leftPts[0], rightPts[0])
        let offsetA = mul(cornersVector, 0.5)
        let offsetB = mul(cornersVector, 0.51)
        startCap.append(contentsOf: [
          sub(firstPoint, offsetA), sub(firstPoint, offsetB),
          add(firstPoint, offsetB), add(firstPoint, offsetA),
        ])
      }

      // End cap.
      let direction = per(neg(points[points.count - 1].vector))
      if taperEnd != 0 || (taperStart != 0 && points.count == 1) {
        endCap.append(lastPoint)
      } else if capEnd {
        let start = prj(lastPoint, direction, radius)
        let step = 1.0 / 29
        var t = step
        while t < 1 {
          endCap.append(rotAround(start, lastPoint, fixedPi * 3 * t))
          t += step
        }
      } else {
        endCap.append(contentsOf: [
          add(lastPoint, mul(direction, radius)),
          add(lastPoint, mul(direction, radius * 0.99)),
          sub(lastPoint, mul(direction, radius * 0.99)),
          sub(lastPoint, mul(direction, radius)),
        ])
      }
    }

    return leftPts + endCap + rightPts.reversed() + startCap
  }
}
