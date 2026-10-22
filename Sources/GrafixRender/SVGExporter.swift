import CoreGraphics
import Foundation
import GrafixCore

/// SVG export (Excalidraw's "Export to SVG"), built from the same cached
/// geometry the canvas draws, so it matches the PNG exactly.
public enum SVGExporter {
  public static func svg(_ scene: Scene, frameID: String? = nil, padding: CGFloat = 10, dark: Bool = false, background: Bool = true) -> String? {
    guard let bounds = SceneRenderer.exportBounds(scene, frameID: frameID, padding: padding) else { return nil }
    let cache = RenderCache()
    var out = """
      <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" \
      viewBox="\(f(bounds.minX)) \(f(bounds.minY)) \(f(bounds.width)) \(f(bounds.height))" \
      width="\(f(bounds.width))" height="\(f(bounds.height))">
      <!-- svg-source:grafix -->

      """
    if background {
      out += "<rect x=\"\(f(bounds.minX))\" y=\"\(f(bounds.minY))\" width=\"\(f(bounds.width))\" height=\"\(f(bounds.height))\" fill=\"\(color(scene.viewBackgroundColor, dark))\"/>\n"
    }
    // Embed the fonts the text uses, like Excalidraw's SVG export.
    let families = Set(scene.visibleElements.filter(\.isText).map(\.fontFamily))
    if !families.isEmpty {
      out += "<defs><style class=\"style-fonts\">\n"
      for family in families.sorted() {
        guard let data = Fonts.fontData(for: family) else { continue }
        out += "@font-face { font-family: \"\(Fonts.fontName(for: family))\"; src: url(data:font/ttf;base64,\(data.base64EncodedString())); }\n"
      }
      out += "</style></defs>\n"
    }
    let positions = scene.positions()
    let frame = frameID.flatMap { scene.element($0) }
    if let frame {
      out += "<clipPath id=\"exportclip\"><rect x=\"\(f(frame.x))\" y=\"\(f(frame.y))\" width=\"\(f(frame.width))\" height=\"\(f(frame.height))\"/></clipPath>\n<g clip-path=\"url(#exportclip)\">\n"
    }
    for e in scene.elements where !e.isDeleted {
      if e.isText, let c = e.containerId, positions[c] != nil { continue }
      if e.isFrame { continue }
      out += element(e, scene: scene, cache: cache, dark: dark)
      if let t = e.boundTextID, let i = positions[t], !scene.elements[i].isDeleted {
        out += element(scene.elements[i], scene: scene, cache: cache, dark: dark, container: e)
      }
    }
    if frame != nil { out += "</g>\n" }
    out += "</svg>\n"
    return out
  }

  static func element(_ e: Element, scene: Scene, cache: RenderCache, dark: Bool, container: Element? = nil) -> String {
    let opacity = min(max(e.opacity, 0), 100) / 100
    let angle = e.isText && container?.type == .arrow ? 0 : e.angle
    let c = e.rotationCenter
    var transform = "translate(\(f(e.x)) \(f(e.y)))"
    if angle != 0 {
      transform = "rotate(\(f(angle * 180 / .pi)) \(f(c.x)) \(f(c.y))) " + transform
    }
    var body = ""
    switch e.type {
    case .text:
      let lineHeight = e.fontSize * e.lineHeight
      let baseline = TextLayout.baselineOffset(family: e.fontFamily, size: e.fontSize, lineHeightPx: lineHeight)
      let anchor = e.textAlign == .center ? "middle" : e.textAlign == .right ? "end" : "start"
      let x = e.textAlign == .center ? e.width / 2 : e.textAlign == .right ? e.width : 0
      for (i, line) in TextLayout.lines(e.text).enumerated() {
        body += "<text x=\"\(f(x))\" y=\"\(f(CGFloat(i) * lineHeight + baseline))\" font-family=\"\(Fonts.fontName(for: e.fontFamily)), Segoe UI Emoji\" font-size=\"\(f(e.fontSize))px\" fill=\"\(color(e.strokeColor, dark))\" text-anchor=\"\(anchor)\" style=\"white-space: pre;\" direction=\"ltr\" dominant-baseline=\"alphabetic\">\(escape(line))</text>"
      }
    case .image:
      if let id = e.fileId, let url = scene.files[id]?["dataURL"]?.string {
        let sx = e.scale.first ?? 1
        let sy = e.scale.count > 1 ? e.scale[1] : 1
        let flip = sx < 0 || sy < 0 ? " transform=\"translate(\(f(sx < 0 ? e.width : 0)) \(f(sy < 0 ? e.height : 0))) scale(\(f(sx < 0 ? -1 : 1)) \(f(sy < 0 ? -1 : 1)))\"" : ""
        body += "<image href=\"\(url)\" width=\"\(f(e.width))\" height=\"\(f(e.height))\" preserveAspectRatio=\"none\"\(flip)/>"
      }
    case .frame, .magicframe, .selection:
      return ""
    default:
      let shape = cache.shape(for: e, dark: dark, background: scene.viewBackgroundColor)
      for op in shape.ops {
        let d = pathData(op.path)
        switch op.kind {
        case .stroke, .sketch:
          var dash = ""
          if let a = op.dash, !a.isEmpty { dash = " stroke-dasharray=\"\(a.map { f($0) }.joined(separator: " "))\"" }
          body += "<path d=\"\(d)\" stroke=\"\(hex(op.color))\" stroke-width=\"\(f(op.lineWidth))\" fill=\"none\" stroke-linecap=\"round\" stroke-linejoin=\"round\"\(dash)/>"
        case .fill(let evenOdd):
          body += "<path d=\"\(d)\" fill=\"\(hex(op.color))\" stroke=\"none\"\(evenOdd ? " fill-rule=\"evenodd\"" : "")/>"
        }
      }
      if let fd = shape.freedraw, let col = shape.freedrawColor {
        body += "<path d=\"\(pathData(fd))\" fill=\"\(hex(col))\" stroke=\"none\"/>"
      }
    }
    guard !body.isEmpty else { return "" }
    let alpha = opacity < 1 ? " opacity=\"\(f(opacity))\"" : ""
    let link = e.link.map { "<a href=\"\(escape($0))\">" } ?? ""
    return "\(link)<g transform=\"\(transform)\"\(alpha)>\(body)</g>\(e.link != nil ? "</a>" : "")\n"
  }

  static func pathData(_ path: CGPath) -> String {
    var d = ""
    path.applyWithBlock { el in
      let p = el.pointee.points
      switch el.pointee.type {
      case .moveToPoint: d += "M\(f(p[0].x)) \(f(p[0].y)) "
      case .addLineToPoint: d += "L\(f(p[0].x)) \(f(p[0].y)) "
      case .addQuadCurveToPoint: d += "Q\(f(p[0].x)) \(f(p[0].y)), \(f(p[1].x)) \(f(p[1].y)) "
      case .addCurveToPoint: d += "C\(f(p[0].x)) \(f(p[0].y)), \(f(p[1].x)) \(f(p[1].y)), \(f(p[2].x)) \(f(p[2].y)) "
      case .closeSubpath: d += "Z "
      @unknown default: break
      }
    }
    return d.trimmingCharacters(in: .whitespaces)
  }

  static func f(_ v: CGFloat) -> String {
    let r = (v * 100).rounded() / 100
    return r == r.rounded() ? String(Int(r)) : String(format: "%.2f", r)
  }

  static func color(_ css: String, _ dark: Bool) -> String { dark ? CSSColor.applyDarkModeFilter(css) : css }

  static func hex(_ c: CGColor) -> String {
    guard let comps = c.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)?.components,
      comps.count >= 3
    else { return "#000" }
    let a = comps.count > 3 ? comps[3] : 1
    if a == 0 { return "transparent" }
    let base = String(format: "#%02x%02x%02x", Int(comps[0] * 255), Int(comps[1] * 255), Int(comps[2] * 255))
    return a < 1 ? base + String(format: "%02x", Int(a * 255)) : base
  }

  static func escape(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
  }
}
