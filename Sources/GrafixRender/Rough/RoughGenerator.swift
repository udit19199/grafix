import CoreGraphics
import Foundation

/// Port of roughjs/bin/generator.js `RoughGenerator`. Every method begins with
/// `options.copy()` (generator.js `_o`), so the caller's options are never mutated.
public final class RoughGenerator {
  public init() {}

  private func hasFill(_ o: RoughOptions) -> Bool { !(o.fill ?? "").isEmpty }

  private func drawable(_ shape: String, _ sets: [OpSet], _ o: RoughOptions) -> Drawable {
    Drawable(shape: shape, sets: sets, options: o)
  }

  public func line(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ options: RoughOptions)
    -> Drawable
  {
    let o = options.copy()
    return drawable("line", [RoughRenderer.line(x1, y1, x2, y2, o)], o)
  }

  public func rectangle(
    _ x: Double, _ y: Double, _ width: Double, _ height: Double, _ options: RoughOptions
  ) -> Drawable {
    let o = options.copy()
    var paths: [OpSet] = []
    let outline = RoughRenderer.rectangle(x, y, width, height, o)
    if hasFill(o) {
      let points = [
        CGPoint(x: x, y: y), CGPoint(x: x + width, y: y),
        CGPoint(x: x + width, y: y + height), CGPoint(x: x, y: y + height),
      ]
      if o.fillStyle == "solid" {
        paths.append(RoughRenderer.solidFillPolygon([points], o))
      } else {
        var list = [points]
        paths.append(RoughRenderer.patternFillPolygons(&list, o))
      }
    }
    if o.stroke != "none" { paths.append(outline) }
    return drawable("rectangle", paths, o)
  }

  public func ellipse(
    _ x: Double, _ y: Double, _ width: Double, _ height: Double, _ options: RoughOptions
  ) -> Drawable {
    let o = options.copy()
    var paths: [OpSet] = []
    let params = RoughRenderer.generateEllipseParams(width, height, o)
    let response = RoughRenderer.ellipseWithParams(x, y, o, params)
    if hasFill(o) {
      if o.fillStyle == "solid" {
        var shape = RoughRenderer.ellipseWithParams(x, y, o, params).opset
        shape.type = .fillPath
        paths.append(shape)
      } else {
        var list = [response.estimatedPoints]
        paths.append(RoughRenderer.patternFillPolygons(&list, o))
      }
    }
    if o.stroke != "none" { paths.append(response.opset) }
    return drawable("ellipse", paths, o)
  }

  public func circle(_ x: Double, _ y: Double, _ diameter: Double, _ options: RoughOptions)
    -> Drawable
  {
    var ret = ellipse(x, y, diameter, diameter, options)
    ret.shape = "circle"
    return ret
  }

  public func linearPath(_ points: [CGPoint], _ options: RoughOptions) -> Drawable {
    let o = options.copy()
    return drawable("linearPath", [RoughRenderer.linearPath(points, close: false, o)], o)
  }

  public func arc(
    _ x: Double, _ y: Double, _ width: Double, _ height: Double, _ start: Double, _ stop: Double,
    closed: Bool = false, _ options: RoughOptions
  ) -> Drawable {
    let o = options.copy()
    var paths: [OpSet] = []
    let outline = RoughRenderer.arc(x, y, width, height, start, stop, closed, true, o)
    if closed && hasFill(o) {
      if o.fillStyle == "solid" {
        let fillOptions = o.copy()
        fillOptions.disableMultiStroke = true
        var shape = RoughRenderer.arc(x, y, width, height, start, stop, true, false, fillOptions)
        shape.type = .fillPath
        paths.append(shape)
      } else {
        paths.append(RoughRenderer.patternFillArc(x, y, width, height, start, stop, o))
      }
    }
    if o.stroke != "none" { paths.append(outline) }
    return drawable("arc", paths, o)
  }

  public func curve(_ points: [CGPoint], _ options: RoughOptions) -> Drawable {
    let o = options.copy()
    var paths: [OpSet] = []
    let outline = RoughRenderer.curve(points, o)
    if hasFill(o) && o.fill != "none" && points.count >= 3 {
      if o.fillStyle == "solid" {
        let fo = o.copy()
        fo.disableMultiStroke = true
        fo.roughness = o.roughness != 0 ? (o.roughness + o.fillShapeRoughnessGain) : 0
        let fillShape = RoughRenderer.curve(points, fo)
        paths.append(OpSet(type: .fillPath, ops: mergedShape(fillShape.ops)))
      } else {
        let bcurve = curveToBezier(points)
        let polyPoints = pointsOnBezierCurves(
          bcurve, tolerance: 10, distance: (1 + o.roughness) / 2)
        var list = [polyPoints]
        paths.append(RoughRenderer.patternFillPolygons(&list, o))
      }
    }
    if o.stroke != "none" { paths.append(outline) }
    return drawable("curve", paths, o)
  }

  public func polygon(_ points: [CGPoint], _ options: RoughOptions) -> Drawable {
    let o = options.copy()
    var paths: [OpSet] = []
    let outline = RoughRenderer.linearPath(points, close: true, o)
    if hasFill(o) {
      if o.fillStyle == "solid" {
        paths.append(RoughRenderer.solidFillPolygon([points], o))
      } else {
        var list = [points]
        paths.append(RoughRenderer.patternFillPolygons(&list, o))
      }
    }
    if o.stroke != "none" { paths.append(outline) }
    return drawable("polygon", paths, o)
  }

  public func path(_ d: String, _ options: RoughOptions) -> Drawable {
    let o = options.copy()
    var paths: [OpSet] = []
    if d.isEmpty { return drawable("path", paths, o) }
    var dd = d.replacingOccurrences(of: "\n", with: " ")
    // .replace(/(-\s)/g, '-')
    dd = dd.replacingOccurrences(of: "-\\s", with: "-", options: .regularExpression)
    let fillOK = hasFill(o) && o.fill != "transparent" && o.fill != "none"
    let hasStroke = o.stroke != "none"
    let simplified = (o.simplification ?? 0) != 0 && (o.simplification ?? 0) < 1
    let simp = o.simplification ?? 0
    let distance = simplified ? (4 - 4 * (simp != 0 ? simp : 1)) : ((1 + o.roughness) / 2)
    var sets = pointsOnPath(dd, tolerance: 1, distance: distance)
    let shape = RoughRenderer.svgPath(dd, o)
    if fillOK {
      if o.fillStyle == "solid" {
        if sets.count == 1 {
          let fo = o.copy()
          fo.disableMultiStroke = true
          fo.roughness = o.roughness != 0 ? (o.roughness + o.fillShapeRoughnessGain) : 0
          let fillShape = RoughRenderer.svgPath(dd, fo)
          paths.append(OpSet(type: .fillPath, ops: mergedShape(fillShape.ops)))
        } else {
          paths.append(RoughRenderer.solidFillPolygon(sets, o))
        }
      } else {
        paths.append(RoughRenderer.patternFillPolygons(&sets, o))
      }
    }
    if hasStroke {
      if simplified {
        for set in sets { paths.append(RoughRenderer.linearPath(set, close: false, o)) }
      } else {
        paths.append(shape)
      }
    }
    return drawable("path", paths, o)
  }

  /// generator.js `_mergedShape`.
  private func mergedShape(_ input: [RoughOp]) -> [RoughOp] {
    input.enumerated().filter { (i, d) in i == 0 || d.op != .move }.map { $0.element }
  }
}
