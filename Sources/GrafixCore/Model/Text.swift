import CoreGraphics
import CoreText
import Foundation

/// The bundled Excalidraw fonts and text measurement.
///
/// Fonts are merged from Excalidraw's WOFF2 subsets by
/// `scripts/port/merge-fonts.py` into `Resources/Fonts/*.ttf`.
public enum Fonts {
  private static let registered: Void = {
    guard let dir = Bundle.module.url(forResource: "Fonts", withExtension: nil) else { return }
    let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
    for url in urls where url.pathExtension == "ttf" || url.pathExtension == "woff2" {
      CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
  }()

  /// Ensures the bundled fonts are available to CoreText. Cheap after the first call.
  public static func register() { _ = registered }

  /// The bundled font file for a family (used to embed fonts in SVG exports).
  public static func fontData(for family: Int) -> Data? {
    let file: String? =
      switch FontFamily(rawValue: family) {
      case .virgil: "Virgil"
      case .cascadia: "Cascadia"
      case .excalifont, .none: "Excalifont"
      case .nunito: "Nunito"
      case .lilitaOne: "LilitaOne"
      case .comicShanns: "ComicShanns"
      case .liberationSans: "LiberationSans"
      default: nil
      }
    guard let file, let dir = Bundle.module.url(forResource: "Fonts", withExtension: nil) else { return nil }
    return try? Data(contentsOf: dir.appendingPathComponent(file + ".ttf"))
  }

  /// PostScript-ish name used to create the font for an Excalidraw family id.
  public static func fontName(for family: Int) -> String {
    switch FontFamily(rawValue: family) {
    case .virgil: "Virgil"
    case .helvetica: "Helvetica"
    case .cascadia: "Cascadia Code"
    case .excalifont, .none: "Excalifont"
    case .nunito: "Nunito"
    case .lilitaOne: "Lilita One"
    case .comicShanns: "Comic Shanns Regular"
    case .liberationSans: "Liberation Sans"
    case .assistant: "Helvetica Neue"
    }
  }

  nonisolated(unsafe) private static var cache: [String: CTFont] = [:]
  private static let lock = NSLock()

  /// A CTFont for the family and size, with system fallback for missing glyphs.
  public static func font(family: Int, size: CGFloat) -> CTFont {
    register()
    let key = "\(family)@\(size)"
    lock.lock()
    defer { lock.unlock() }
    if let f = cache[key] { return f }
    var attributes: [CFString: Any] = [kCTFontFamilyNameAttribute: fontName(for: family)]
    if family == FontFamily.nunito.rawValue {
      // Nunito is a variable font; Excalidraw uses weight 500.
      attributes[kCTFontVariationAttribute] = [0x7767_6874: 500]  // 'wght'
    }
    let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
    let font = CTFontCreateWithFontDescriptor(descriptor, size, nil)
    cache[key] = font
    return font
  }
}

/// Text measuring and wrapping, matching Excalidraw's textMeasurements.ts and
/// textWrapping.ts closely enough for layout (widths come from CoreText).
public enum TextLayout {
  public static let boundTextPadding: CGFloat = 5

  /// Width of one line in pixels.
  public static func lineWidth(_ line: String, family: Int, size: CGFloat) -> CGFloat {
    guard !line.isEmpty else { return 0 }
    let attributed = NSAttributedString(
      string: line, attributes: [kCTFontAttributeName as NSAttributedString.Key: Fonts.font(family: family, size: size)])
    let ctLine = CTLineCreateWithAttributedString(attributed)
    return CGFloat(CTLineGetTypographicBounds(ctLine, nil, nil, nil))
  }

  public static func lines(_ text: String) -> [String] {
    text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
      .components(separatedBy: "\n")
  }

  /// Size of (already wrapped) text: widest line x line count * lineHeight.
  public static func measure(_ text: String, family: Int, size: CGFloat, lineHeight: CGFloat) -> CGSize {
    let ls = lines(text)
    let width = ls.map { lineWidth($0, family: family, size: size) }.max() ?? 0
    return CGSize(width: width, height: CGFloat(ls.count) * size * lineHeight)
  }

  /// Greedy word wrap to `maxWidth`. Long words break by character. Explicit
  /// newlines are kept.
  public static func wrap(_ text: String, family: Int, size: CGFloat, maxWidth: CGFloat) -> String {
    guard maxWidth > 0 else { return text }
    var out: [String] = []
    for line in lines(text) {
      if lineWidth(line, family: family, size: size) <= maxWidth {
        out.append(line)
        continue
      }
      var current = ""
      // Split keeping the whitespace attached to the preceding word.
      var words: [String] = []
      var word = ""
      for ch in line {
        word.append(ch)
        if ch == " " {
          words.append(word)
          word = ""
        }
      }
      if !word.isEmpty { words.append(word) }
      for w in words {
        let candidate = current + w
        if lineWidth(candidate.trimmingCharacters(in: .whitespaces), family: family, size: size) <= maxWidth {
          current = candidate
          continue
        }
        if !current.isEmpty {
          out.append(current.trimmingCharacters(in: CharacterSet(charactersIn: " ")))
          current = ""
        }
        // Word itself too long: break it.
        if lineWidth(w.trimmingCharacters(in: .whitespaces), family: family, size: size) > maxWidth {
          var piece = ""
          for ch in w {
            if lineWidth(piece + String(ch), family: family, size: size) > maxWidth, !piece.isEmpty {
              out.append(piece)
              piece = ""
            }
            piece.append(ch)
          }
          current = piece
        } else {
          current = w
        }
      }
      out.append(current.trimmingCharacters(in: CharacterSet(charactersIn: " ")))
    }
    return out.joined(separator: "\n")
  }

  /// Distance from the top of a line box to the baseline (Excalidraw getVerticalOffset).
  public static func baselineOffset(family: Int, size: CGFloat, lineHeightPx: CGFloat) -> CGFloat {
    let m = (FontFamily(rawValue: family) ?? .excalifont).metrics
    let em = size / m.unitsPerEm
    let lineGap = (lineHeightPx - em * m.ascender + em * m.descender) / 2
    return em * m.ascender + lineGap
  }
}

// MARK: - Element text helpers

extension Element {
  /// Sizes a free-standing text element to fit its text (autoResize).
  public mutating func fitText() {
    let source = autoResize ? originalText : TextLayout.wrap(
      originalText, family: fontFamily, size: fontSize, maxWidth: width)
    text = source
    let size = TextLayout.measure(source, family: fontFamily, size: fontSize, lineHeight: lineHeight)
    if autoResize { width = size.width }
    height = size.height
  }

  /// Max label width inside this container (getBoundTextMaxWidth).
  public func labelMaxWidth(fontSize: Double = 20) -> CGFloat {
    let pad = TextLayout.boundTextPadding
    switch type {
    case .arrow: return max(0.7 * width, fontSize * 11)
    case .ellipse: return ((width / 2) * 2.0.squareRoot()).rounded() - pad * 2
    case .diamond: return (width / 2).rounded() - pad * 2
    default: return width - pad * 2
    }
  }

  public var labelMaxHeight: CGFloat {
    let pad = TextLayout.boundTextPadding
    switch type {
    case .ellipse: return ((height / 2) * 2.0.squareRoot()).rounded() - pad * 2
    case .diamond: return (height / 2).rounded() - pad * 2
    default: return height - pad * 2
    }
  }

  /// Top-left of the label area (getContainerCoords).
  public var labelOrigin: CGPoint {
    var dx = TextLayout.boundTextPadding
    var dy = dx
    if type == .ellipse {
      dx += (width / 2) * (1 - 2.0.squareRoot() / 2)
      dy += (height / 2) * (1 - 2.0.squareRoot() / 2)
    }
    if type == .diamond {
      dx += width / 4
      dy += height / 4
    }
    return CGPoint(x: x + dx, y: y + dy)
  }

  /// Point half way along a linear element's path, in scene coordinates.
  public var pathMidpoint: CGPoint {
    guard points.count >= 2 else { return CGPoint(x: x, y: y) }
    if points.count % 2 == 1, !elbowed {
      let p = points[points.count / 2]
      return CGPoint(x: x + p.x, y: y + p.y)
    }
    var total: CGFloat = 0
    for i in 1..<points.count { total += points[i].distance(to: points[i - 1]) }
    var walked: CGFloat = 0
    for i in 1..<points.count {
      let seg = points[i].distance(to: points[i - 1])
      if walked + seg >= total / 2, seg > 0 {
        let t = (total / 2 - walked) / seg
        let p = points[i - 1] + (points[i] - points[i - 1]) * t
        return CGPoint(x: x + p.x, y: y + p.y)
      }
      walked += seg
    }
    return CGPoint(x: x + points[0].x, y: y + points[0].y)
  }
}

extension Scene {
  /// Re-wraps and re-positions the label of `containerID`, growing the container
  /// if the text no longer fits (redrawTextBoundingBox + computeBoundTextPosition).
  public mutating func layoutLabel(of containerID: String) {
    guard let ci = indexOf(containerID), let tid = elements[ci].boundTextID,
      let ti = indexOf(tid), !elements[ti].isDeleted
    else { return }
    var container = elements[ci]
    var label = elements[ti]
    let maxWidth = container.labelMaxWidth(fontSize: label.fontSize)
    let wrapped = TextLayout.wrap(label.originalText, family: label.fontFamily, size: label.fontSize, maxWidth: maxWidth)
    let size = TextLayout.measure(wrapped, family: label.fontFamily, size: label.fontSize, lineHeight: label.lineHeight)
    label.text = wrapped
    label.width = size.width
    label.height = size.height
    if container.type != .arrow, size.height > container.labelMaxHeight {
      let pad = TextLayout.boundTextPadding * 2
      let dim = size.height.rounded(.up)
      let newHeight: CGFloat =
        switch container.type {
        case .ellipse: (((dim + pad) / 2.0.squareRoot()) * 2).rounded()
        case .diamond: 2 * (dim + pad)
        default: dim + pad
        }
      if newHeight != container.height {
        container.height = newHeight
        container.bump()
      }
    }
    if container.type == .arrow {
      let mid = container.pathMidpoint
      label.x = mid.x - label.width / 2
      label.y = mid.y - label.height / 2
      label.angle = 0
    } else {
      let origin = container.labelOrigin
      let maxW = container.labelMaxWidth(fontSize: label.fontSize)
      let maxH = container.labelMaxHeight
      switch label.verticalAlign {
      case .top: label.y = origin.y
      case .bottom: label.y = origin.y + maxH - label.height
      case .middle: label.y = origin.y + maxH / 2 - label.height / 2
      }
      switch label.textAlign {
      case .left: label.x = origin.x
      case .right: label.x = origin.x + maxW - label.width
      case .center: label.x = origin.x + maxW / 2 - label.width / 2
      }
      label.angle = container.angle
      if container.angle != 0 {
        let contentCenter = CGPoint(x: origin.x + maxW / 2, y: origin.y + maxH / 2)
        let textCenter = CGPoint(x: label.x + label.width / 2, y: label.y + label.height / 2)
        // The label keeps its own unrotated box; only its centre moves with the container.
        let r = textCenter.rotated(around: contentCenter, by: container.angle)
        label.x = r.x - label.width / 2
        label.y = r.y - label.height / 2
      }
    }
    label.bump()
    elements[ci] = container
    elements[ti] = label
  }
}
