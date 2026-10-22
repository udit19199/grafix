import CoreGraphics
import Foundation

// Port of Rough.js 4.6.4 (MIT, https://github.com/rough-stuff/rough), the exact
// version Excalidraw depends on. Keep this a line-by-line port: Excalidraw's
// look depends on consuming random numbers in exactly the same order.
// Reference copy: ~/Workspace/oss/npm-ref/node_modules/roughjs/bin/*.js

public enum RoughOpKind: Sendable { case move, bcurveTo, lineTo }

public struct RoughOp: Sendable, Equatable {
  public var op: RoughOpKind
  public var data: [Double]
  public init(_ op: RoughOpKind, _ data: [Double]) {
    self.op = op
    self.data = data
  }
}

public enum OpSetType: Sendable { case path, fillPath, fillSketch }

public struct OpSet: Sendable {
  public var type: OpSetType
  public var ops: [RoughOp]
}

/// Rough.js `Drawable`.
public struct Drawable: @unchecked Sendable {
  public var shape: String
  public var sets: [OpSet]
  public var options: RoughOptions
}

/// Rough.js `Random` (math.js): a Park-Miller style LCG on int32.
public final class RoughRandom {
  var seed: Int32
  init(seed: Int32) { self.seed = seed }
  func next() -> Double {
    if seed != 0 {
      seed = 48271 &* seed
      return Double(Int32(0x7FFF_FFFF) & seed) / 2_147_483_648.0
    }
    return Double.random(in: 0..<1)
  }
}

/// Rough.js `ResolvedOptions`. A class because Rough.js mutates the options
/// object (lazily attaching `randomizer`) and copies share that randomizer;
/// `copy()` is JS's `Object.assign({}, o)`.
public final class RoughOptions {
  public var maxRandomnessOffset: Double = 2
  public var roughness: Double = 1
  public var bowing: Double = 1
  public var stroke: String = "#000"
  public var strokeWidth: Double = 1
  public var curveTightness: Double = 0
  public var curveFitting: Double = 0.95
  public var curveStepCount: Double = 9
  public var fillStyle: String = "hachure"
  public var fillWeight: Double = -1
  public var hachureAngle: Double = -41
  public var hachureGap: Double = -1
  public var dashOffset: Double = -1
  public var dashGap: Double = -1
  public var zigzagOffset: Double = -1
  public var seed: Int32 = 0
  public var disableMultiStroke: Bool = false
  public var disableMultiStrokeFill: Bool = false
  public var preserveVertices: Bool = false
  public var fillShapeRoughnessGain: Double = 0.8
  public var fill: String? = nil
  public var strokeLineDash: [Double]? = nil
  public var simplification: Double? = nil
  var randomizer: RoughRandom? = nil

  public init() {}

  public func copy() -> RoughOptions {
    let o = RoughOptions()
    o.maxRandomnessOffset = maxRandomnessOffset
    o.roughness = roughness
    o.bowing = bowing
    o.stroke = stroke
    o.strokeWidth = strokeWidth
    o.curveTightness = curveTightness
    o.curveFitting = curveFitting
    o.curveStepCount = curveStepCount
    o.fillStyle = fillStyle
    o.fillWeight = fillWeight
    o.hachureAngle = hachureAngle
    o.hachureGap = hachureGap
    o.dashOffset = dashOffset
    o.dashGap = dashGap
    o.zigzagOffset = zigzagOffset
    o.seed = seed
    o.disableMultiStroke = disableMultiStroke
    o.disableMultiStrokeFill = disableMultiStrokeFill
    o.preserveVertices = preserveVertices
    o.fillShapeRoughnessGain = fillShapeRoughnessGain
    o.fill = fill
    o.strokeLineDash = strokeLineDash
    o.simplification = simplification
    o.randomizer = randomizer
    return o
  }

  func random() -> Double {
    if randomizer == nil { randomizer = RoughRandom(seed: seed) }
    return randomizer!.next()
  }
}

typealias RPoint = CGPoint
