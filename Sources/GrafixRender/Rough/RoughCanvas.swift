import CoreGraphics
import Foundation

// Port of roughjs/bin/canvas.js `draw()` for CoreGraphics.

extension Drawable {
  /// Builds the CGPath for one op set (canvas.js `_drawToContext`).
  public func cgPath(_ set: OpSet) -> CGPath {
    let path = CGMutablePath()
    var hasCurrent = false
    for item in set.ops {
      let d = item.data
      switch item.op {
      case .move:
        path.move(to: CGPoint(x: d[0], y: d[1]))
        hasCurrent = true
      case .bcurveTo:
        if !hasCurrent {
          path.move(to: CGPoint(x: d[0], y: d[1]))
          hasCurrent = true
        }
        path.addCurve(
          to: CGPoint(x: d[4], y: d[5]), control1: CGPoint(x: d[0], y: d[1]),
          control2: CGPoint(x: d[2], y: d[3]))
      case .lineTo:
        if !hasCurrent {
          path.move(to: CGPoint(x: d[0], y: d[1]))
          hasCurrent = true
        } else {
          path.addLine(to: CGPoint(x: d[0], y: d[1]))
        }
      }
    }
    return path
  }

  /// Draws all sets. `color` converts a CSS colour string to a CGColor.
  public func draw(in ctx: CGContext, color: (String) -> CGColor) {
    let o = options
    for drawing in sets {
      switch drawing.type {
      case .path:
        ctx.saveGState()
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setStrokeColor(color(o.stroke == "none" ? "transparent" : o.stroke))
        ctx.setLineWidth(o.strokeWidth)
        if let dash = o.strokeLineDash, !dash.isEmpty {
          ctx.setLineDash(phase: 0, lengths: dash.map { CGFloat($0) })
        }
        ctx.addPath(cgPath(drawing))
        ctx.strokePath()
        ctx.restoreGState()
      case .fillPath:
        ctx.saveGState()
        ctx.setFillColor(color(o.fill ?? ""))
        let evenOdd = shape == "curve" || shape == "polygon" || shape == "path"
        ctx.addPath(cgPath(drawing))
        ctx.fillPath(using: evenOdd ? .evenOdd : .winding)
        ctx.restoreGState()
      case .fillSketch:
        var fweight = o.fillWeight
        if fweight < 0 { fweight = o.strokeWidth / 2 }
        ctx.saveGState()
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setStrokeColor(color(o.fill ?? ""))
        ctx.setLineWidth(fweight)
        ctx.addPath(cgPath(drawing))
        ctx.strokePath()
        ctx.restoreGState()
      }
    }
  }
}
