import CoreGraphics
import Foundation

/// Object snapping (simplified from Excalidraw's snapping.ts): when moving a
/// selection, its edges and centre snap to other elements' edges and centres.
public struct SnapResult: Sendable {
  public var offset: CGPoint
  /// Guide lines to draw, in scene coordinates.
  public var lines: [(CGPoint, CGPoint)]
}

extension Scene {
  /// How much to nudge `moving` (a bounds rect already offset by the drag) so it
  /// lines up with nearby elements, within `threshold` scene units.
  public func snap(_ moving: CGRect, excluding ids: Set<String>, viewport: CGRect, threshold: CGFloat) -> SnapResult {
    var bestX: (d: CGFloat, value: CGFloat, target: CGFloat)? = nil
    var bestY: (d: CGFloat, value: CGFloat, target: CGFloat)? = nil
    let xs = [moving.minX, moving.midX, moving.maxX]
    let ys = [moving.minY, moving.midY, moving.maxY]
    var candidates: [CGRect] = []
    for e in elements where !e.isDeleted && !ids.contains(e.id) && e.containerId == nil {
      let b = e.bounds
      guard b.intersects(viewport) else { continue }
      candidates.append(b)
    }
    for b in candidates {
      for tx in [b.minX, b.midX, b.maxX] {
        for x in xs {
          let d = abs(tx - x)
          if d <= threshold, d < (bestX?.d ?? .infinity) { bestX = (d, x, tx) }
        }
      }
      for ty in [b.minY, b.midY, b.maxY] {
        for y in ys {
          let d = abs(ty - y)
          if d <= threshold, d < (bestY?.d ?? .infinity) { bestY = (d, y, ty) }
        }
      }
    }
    let dx = bestX.map { $0.target - $0.value } ?? 0
    let dy = bestY.map { $0.target - $0.value } ?? 0
    let snapped = moving.offsetBy(dx: dx, dy: dy)
    var lines: [(CGPoint, CGPoint)] = []
    if let bx = bestX {
      let x = bx.target
      // Span from the snapped selection to every element sharing that x.
      var minY = snapped.minY
      var maxY = snapped.maxY
      for b in candidates where [b.minX, b.midX, b.maxX].contains(where: { abs($0 - x) < 0.5 }) {
        minY = min(minY, b.minY)
        maxY = max(maxY, b.maxY)
      }
      lines.append((CGPoint(x: x, y: minY), CGPoint(x: x, y: maxY)))
    }
    if let by = bestY {
      let y = by.target
      var minX = snapped.minX
      var maxX = snapped.maxX
      for b in candidates where [b.minY, b.midY, b.maxY].contains(where: { abs($0 - y) < 0.5 }) {
        minX = min(minX, b.minX)
        maxX = max(maxX, b.maxX)
      }
      lines.append((CGPoint(x: minX, y: y), CGPoint(x: maxX, y: y)))
    }
    return SnapResult(offset: CGPoint(x: dx, y: dy), lines: lines)
  }
}
