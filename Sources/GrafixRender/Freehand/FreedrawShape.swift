import CoreGraphics
import Foundation
import GrafixCore

/// Excalidraw freedraw geometry (packages/element/src/shape.ts).
public enum FreedrawShape {
  /// Excalidraw's `DEFAULT_STROKE_STREAMLINE`.
  public static let defaultStreamline = 0.5

  /// Port of `getVariableWidthFreedrawOutline` / `getFreedrawOutlinePoints`.
  public static func outline(for element: Element, streamline: Double = defaultStreamline)
    -> [CGPoint]
  {
    let input: [[Double]]
    if element.simulatePressure {
      input = element.points.map { [$0.x, $0.y] }
    } else if element.points.isEmpty {
      input = [[0, 0, 0.5]]
    } else {
      input = element.points.enumerated().map { i, p in
        i < element.pressures.count ? [p.x, p.y, element.pressures[i]] : [p.x, p.y]
      }
    }
    let options = StrokeOptions(
      size: element.strokeWidth * 4.25, thinning: 0.6, smoothing: 0.5, streamline: streamline,
      easing: { sin($0 * .pi / 2) },
      simulatePressure: element.simulatePressure, last: true)
    return PerfectFreehand.getStroke(input, options)
  }

  /// Port of `getSvgPathFromStroke`: M p0 Q (p_i, mid(p_i, p_i+1))... L p0 Z.
  public static func path(for element: Element, streamline: Double = defaultStreamline) -> CGPath {
    path(fromOutline: outline(for: element, streamline: streamline))
  }

  /// Quadratic-midpoint closed path through an outline.
  public static func path(fromOutline pts: [CGPoint]) -> CGPath {
    let path = CGMutablePath()
    guard let first = pts.first else { return path }
    func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
      CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }
    path.move(to: first)
    for i in 0..<pts.count {
      let next = i == pts.count - 1 ? first : pts[i + 1]
      path.addQuadCurve(to: mid(pts[i], next), control: pts[i])
    }
    path.addLine(to: first)
    path.closeSubpath()
    return path
  }
}
