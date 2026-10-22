// Port of Rough.js math.ts and renderer.ts line primitives at
// 56a2762171b1294d643501e8d14f120db6b27bd7, https://github.com/rough-stuff/rough
// MIT License, Copyright (c) 2019 Preet Shihn. See THIRD_PARTY_NOTICES.md.
import Foundation

public struct RoughRandom: Sendable {
  private var seed: UInt32
  public init(seed: UInt32) { self.seed = seed }
  public mutating func next() -> Double {
    if seed == 0 { return Double.random(in: 0..<1) }
    seed = 48271 &* seed
    return Double(seed & 0x7fff_ffff) / 2_147_483_648
  }
}

public struct RoughLineOptions: Sendable {
  public var seed: UInt32
  public var roughness: Double
  public var maxRandomnessOffset: Double
  public var bowing: Double
  public var disableMultiStroke: Bool
  public var preserveVertices: Bool
  public init(
    seed: UInt32, roughness: Double = 1, maxRandomnessOffset: Double = 2,
    bowing: Double = 1, disableMultiStroke: Bool = false, preserveVertices: Bool = false
  ) {
    self.seed = seed
    self.roughness = roughness
    self.maxRandomnessOffset = maxRandomnessOffset
    self.bowing = bowing
    self.disableMultiStroke = disableMultiStroke
    self.preserveVertices = preserveVertices
  }
}

public struct RoughOperation: Equatable, Sendable {
  public enum Kind: String, Sendable { case move, bcurveTo }
  public var kind: Kind
  public var data: [Double]
}

/// Stateful generator: one instance preserves the upstream random sequence across polygon edges.
public struct RoughLineGenerator: Sendable {
  public var options: RoughLineOptions
  private var random: RoughRandom
  public init(options: RoughLineOptions) {
    self.options = options
    self.random = RoughRandom(seed: options.seed)
  }

  public mutating func line(x1: Double, y1: Double, x2: Double, y2: Double) -> [RoughOperation] {
    let first = stroke(x1, y1, x2, y2, overlay: false)
    return options.disableMultiStroke ? first : first + stroke(x1, y1, x2, y2, overlay: true)
  }

  private mutating func offset(_ amount: Double, gain: Double) -> Double {
    options.roughness * gain * ((random.next() * (amount - -amount)) + -amount)
  }

  private mutating func stroke(
    _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, overlay: Bool
  ) -> [RoughOperation] {
    let lengthSquared = pow(x1 - x2, 2) + pow(y1 - y2, 2)
    let length = sqrt(lengthSquared)
    let gain = length < 200 ? 1 : length > 500 ? 0.4 : -0.0016668 * length + 1.233334
    var amount = options.maxRandomnessOffset
    if amount * amount * 100 > lengthSquared { amount = length / 10 }
    let halfAmount = amount / 2
    let divergePoint = 0.2 + random.next() * 0.2
    var midX = options.bowing * options.maxRandomnessOffset * (y2 - y1) / 200
    var midY = options.bowing * options.maxRandomnessOffset * (x1 - x2) / 200
    midX = offset(midX, gain: gain)
    midY = offset(midY, gain: gain)
    let strokeAmount = overlay ? halfAmount : amount
    let startX = x1 + (options.preserveVertices ? 0 : offset(strokeAmount, gain: gain))
    let startY = y1 + (options.preserveVertices ? 0 : offset(strokeAmount, gain: gain))
    let control1X = midX + x1 + (x2 - x1) * divergePoint + offset(strokeAmount, gain: gain)
    let control1Y = midY + y1 + (y2 - y1) * divergePoint + offset(strokeAmount, gain: gain)
    let control2X = midX + x1 + 2 * (x2 - x1) * divergePoint + offset(strokeAmount, gain: gain)
    let control2Y = midY + y1 + 2 * (y2 - y1) * divergePoint + offset(strokeAmount, gain: gain)
    let endX = x2 + (options.preserveVertices ? 0 : offset(strokeAmount, gain: gain))
    let endY = y2 + (options.preserveVertices ? 0 : offset(strokeAmount, gain: gain))
    return [
      .init(kind: .move, data: [startX, startY]),
      .init(kind: .bcurveTo, data: [control1X, control1Y, control2X, control2Y, endX, endY]),
    ]
  }
}
