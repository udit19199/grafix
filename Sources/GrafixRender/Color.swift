import CoreGraphics
import Foundation

/// CSS colour parsing and Excalidraw's dark-mode colour transform.
public enum CSSColor {
  public struct RGBA: Equatable, Sendable {
    public var r, g, b, a: Double
  }

  nonisolated(unsafe) private static var cache: [String: CGColor] = [:]
  nonisolated(unsafe) private static var darkCache: [String: String] = [:]
  private static let lock = NSLock()

  /// CGColor for a CSS colour string. Unknown strings become black; "transparent" is clear.
  public static func cgColor(_ css: String, dark: Bool = false) -> CGColor {
    let key = dark ? "d:" + css : css
    lock.lock()
    if let c = cache[key] {
      lock.unlock()
      return c
    }
    lock.unlock()
    let source = dark ? applyDarkModeFilter(css) : css
    let rgba = parse(source) ?? RGBA(r: 0, g: 0, b: 0, a: 1)
    let color = CGColor(srgbRed: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a)
    lock.lock()
    cache[key] = color
    lock.unlock()
    return color
  }

  public static func isTransparent(_ css: String) -> Bool {
    let v = css.trimmingCharacters(in: .whitespaces).lowercased()
    if v == "transparent" || v.isEmpty { return true }
    return (parse(v)?.a ?? 1) == 0
  }

  public static func parse(_ raw: String) -> RGBA? {
    let v = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if v == "transparent" { return RGBA(r: 0, g: 0, b: 0, a: 0) }
    if let named = named[v] { return parse(named) }
    if v.hasPrefix("#") {
      let hex = String(v.dropFirst())
      guard let n = UInt64(hex, radix: 16) else { return nil }
      func c(_ shift: Int, _ bits: Int) -> Double {
        let mask: UInt64 = bits == 4 ? 0xF : 0xFF
        let value = Double((n >> UInt64(shift)) & mask)
        return bits == 4 ? value / 15 : value / 255
      }
      switch hex.count {
      case 3: return RGBA(r: c(8, 4), g: c(4, 4), b: c(0, 4), a: 1)
      case 4: return RGBA(r: c(12, 4), g: c(8, 4), b: c(4, 4), a: c(0, 4))
      case 6: return RGBA(r: c(16, 8), g: c(8, 8), b: c(0, 8), a: 1)
      case 8: return RGBA(r: c(24, 8), g: c(16, 8), b: c(8, 8), a: c(0, 8))
      default: return nil
      }
    }
    if v.hasPrefix("rgb"), let open = v.firstIndex(of: "("), let close = v.lastIndex(of: ")") {
      let parts = v[v.index(after: open)..<close].split(whereSeparator: { ", /".contains($0) })
        .map { String($0) }
      guard parts.count >= 3 else { return nil }
      func channel(_ s: String) -> Double {
        s.hasSuffix("%") ? (Double(s.dropLast()) ?? 0) / 100 : (Double(s) ?? 0) / 255
      }
      var alpha = 1.0
      if parts.count >= 4 {
        let s = parts[3]
        alpha = s.hasSuffix("%") ? (Double(s.dropLast()) ?? 100) / 100 : Double(s) ?? 1
      }
      return RGBA(r: channel(parts[0]), g: channel(parts[1]), b: channel(parts[2]), a: alpha)
    }
    return nil
  }

  static let named: [String: String] = [
    "black": "#000000", "white": "#ffffff", "red": "#ff0000", "green": "#008000", "blue": "#0000ff",
    "yellow": "#ffff00", "orange": "#ffa500", "purple": "#800080", "gray": "#808080",
    "grey": "#808080", "pink": "#ffc0cb", "brown": "#a52a2a", "cyan": "#00ffff",
    "magenta": "#ff00ff", "lightgray": "#d3d3d3", "darkgray": "#a9a9a9", "silver": "#c0c0c0",
    "navy": "#000080", "teal": "#008080", "olive": "#808000", "maroon": "#800000",
    "lime": "#00ff00", "aqua": "#00ffff", "fuchsia": "#ff00ff",
  ]

  /// Excalidraw applyDarkModeFilter: CSS `invert(93%) hue-rotate(180deg)` on a colour.
  public static func applyDarkModeFilter(_ css: String) -> String {
    lock.lock()
    if let c = darkCache[css] {
      lock.unlock()
      return c
    }
    lock.unlock()
    guard let rgba = parse(css), rgba.a > 0 else { return css }
    let p = 0.93
    func invert(_ c: Double) -> Double {
      let v = c * 255
      return (max(0, min(255, (v * (1 - p) + (255 - v) * p).rounded())))
    }
    let r = invert(rgba.r) / 255
    let g = invert(rgba.g) / 255
    let b = invert(rgba.b) / 255
    let a = Double.pi  // 180 degrees
    let cs = cos(a)
    let sn = sin(a)
    let m = [
      0.213 + cs * 0.787 - sn * 0.213, 0.715 - cs * 0.715 - sn * 0.715, 0.072 - cs * 0.072 + sn * 0.928,
      0.213 - cs * 0.213 + sn * 0.143, 0.715 + cs * 0.285 + sn * 0.14, 0.072 - cs * 0.072 - sn * 0.283,
      0.213 - cs * 0.213 - sn * 0.787, 0.715 - cs * 0.715 + sn * 0.715, 0.072 + cs * 0.928 + sn * 0.072,
    ]
    func clamp255(_ x: Double) -> Int { Int((max(0, min(1, x)) * 255).rounded()) }
    let nr = clamp255(r * m[0] + g * m[1] + b * m[2])
    let ng = clamp255(r * m[3] + g * m[4] + b * m[5])
    let nb = clamp255(r * m[6] + g * m[7] + b * m[8])
    var out = String(format: "#%02x%02x%02x", nr, ng, nb)
    if rgba.a < 1 { out += String(format: "%02x", Int((rgba.a * 255).rounded())) }
    lock.lock()
    darkCache[css] = out
    lock.unlock()
    return out
  }
}
