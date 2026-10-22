import CoreGraphics
import Foundation
import SwiftUI

/// Reads the repo's stylesheet values. The tokens themselves are generated into
/// PortTheme.swift; this file is what turns a CSS string into something SwiftUI
/// can draw.
extension PortTheme {
  /// The colour of a CSS custom property, e.g. "color-primary".
  public static func color(_ token: String, dark: Bool = false) -> Color? {
    guard let rgb = rgb(token, dark: dark) else {
      return nil
    }
    return Color(
      .sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: rgb.alpha)
  }

  /// The same value as a raw colour, for tests and for Core Graphics drawing.
  public static func rgb(_ token: String, dark: Bool = false) -> PortRGB? {
    guard let value = raw(token, dark: dark) else {
      return nil
    }
    return PortRGB.parse(value)
  }

  /// A length in points, e.g. "2rem" becomes 32. `rem` follows the browser's
  /// default root size of 16, which is what the web editor lays out against.
  public static func length(_ token: String, dark: Bool = false) -> CGFloat? {
    guard let value = raw(token, dark: dark) else {
      return nil
    }
    return PortLength.parse(value)
  }

  /// A unitless number, e.g. "0.25" from "--space-factor".
  public static func number(_ token: String, dark: Bool = false) -> Double? {
    guard let value = raw(token, dark: dark) else {
      return nil
    }
    return Double(value.trimmingCharacters(in: .whitespaces))
  }

  /// The layers of a CSS box-shadow, outermost first as written.
  public static func shadowLayers(_ token: String, dark: Bool = false) -> [PortShadowLayer] {
    guard let value = raw(token, dark: dark) else {
      return []
    }
    return PortShadowLayer.parseList(value)
  }
}

/// A colour parsed from the repo's stylesheets.
public struct PortRGB: Sendable, Equatable {
  public var red: Double
  public var green: Double
  public var blue: Double
  public var alpha: Double

  public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
    self.red = red
    self.green = green
    self.blue = blue
    self.alpha = alpha
  }

  public static let clear = PortRGB(red: 0, green: 0, blue: 0, alpha: 0)

  /// The repo's `isColorDark`: a YIQ contrast test used to decide whether a
  /// swatch needs an outline to stay visible. A transparent or unparsable
  /// colour is not dark, which is what the source assumes too.
  public func isDark(threshold: Double = 160) -> Bool {
    if alpha == 0 {
      return false
    }
    let yiq = (red * 255 * 299 + green * 255 * 587 + blue * 255 * 114) / 1000
    return yiq < threshold
  }

  /// Parses the forms the repo uses: #rgb, #rrggbb, #rrggbbaa, rgb(), rgba(),
  /// hsl(), hsla(), and the keyword colours in its palette.
  public static func parse(_ raw: String) -> PortRGB? {
    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if value.isEmpty || value == "none" || value == "initial" || value == "inherit" {
      return nil
    }
    if value == "transparent" {
      return .clear
    }
    if value == "white" {
      return PortRGB(red: 1, green: 1, blue: 1)
    }
    if value == "black" {
      return PortRGB(red: 0, green: 0, blue: 0)
    }
    if value.hasPrefix("#") {
      return parseHex(String(value.dropFirst()))
    }
    guard let open = value.firstIndex(of: "("), value.hasSuffix(")") else {
      return nil
    }
    let name = String(value[value.startIndex..<open])
    let arguments = value[value.index(after: open)..<value.index(before: value.endIndex)]
    return parseFunction(name: name, arguments: String(arguments))
  }

  private static func parseHex(_ digits: String) -> PortRGB? {
    guard let value = UInt32(digits, radix: 16) else {
      return nil
    }
    switch digits.count {
    case 3:
      return PortRGB(
        red: Double((value >> 8) & 0xF) / 15,
        green: Double((value >> 4) & 0xF) / 15,
        blue: Double(value & 0xF) / 15
      )
    case 4:
      return PortRGB(
        red: Double((value >> 12) & 0xF) / 15,
        green: Double((value >> 8) & 0xF) / 15,
        blue: Double((value >> 4) & 0xF) / 15,
        alpha: Double(value & 0xF) / 15
      )
    case 6:
      return PortRGB(
        red: Double((value >> 16) & 0xFF) / 255,
        green: Double((value >> 8) & 0xFF) / 255,
        blue: Double(value & 0xFF) / 255
      )
    case 8:
      return PortRGB(
        red: Double((value >> 24) & 0xFF) / 255,
        green: Double((value >> 16) & 0xFF) / 255,
        blue: Double((value >> 8) & 0xFF) / 255,
        alpha: Double(value & 0xFF) / 255
      )
    default:
      return nil
    }
  }

  private static func parseFunction(name: String, arguments: String) -> PortRGB? {
    // Both "a, b, c" and "a b c / d" appear in the stylesheets.
    let parts =
      arguments
      .replacingOccurrences(of: "/", with: " ")
      .split(whereSeparator: { $0 == "," || $0.isWhitespace })
      .map(String.init)
    guard parts.count >= 3 else {
      return nil
    }
    switch name {
    case "rgb", "rgba":
      guard let red = component(parts[0]), let green = component(parts[1]),
        let blue = component(parts[2])
      else {
        return nil
      }
      let alpha = parts.count > 3 ? (alphaValue(parts[3]) ?? 1) : 1
      return PortRGB(red: red, green: green, blue: blue, alpha: alpha)
    case "hsl", "hsla":
      guard let hue = Double(parts[0].replacingOccurrences(of: "deg", with: "")),
        let saturation = percent(parts[1]),
        let lightness = percent(parts[2])
      else {
        return nil
      }
      let alpha = parts.count > 3 ? (alphaValue(parts[3]) ?? 1) : 1
      return hsl(hue: hue, saturation: saturation, lightness: lightness, alpha: alpha)
    default:
      return nil
    }
  }

  /// A red, green or blue value: "255" or "100%".
  private static func component(_ value: String) -> Double? {
    if value.hasSuffix("%"), let percent = Double(value.dropLast()) {
      return percent / 100
    }
    guard let number = Double(value) else {
      return nil
    }
    return number / 255
  }

  private static func alphaValue(_ value: String) -> Double? {
    if value.hasSuffix("%"), let percent = Double(value.dropLast()) {
      return percent / 100
    }
    return Double(value)
  }

  private static func percent(_ value: String) -> Double? {
    guard value.hasSuffix("%"), let number = Double(value.dropLast()) else {
      return nil
    }
    return number / 100
  }

  private static func hsl(
    hue: Double, saturation: Double, lightness: Double, alpha: Double
  ) -> PortRGB {
    let hueFraction =
      (hue.truncatingRemainder(dividingBy: 360) + 360)
      .truncatingRemainder(dividingBy: 360) / 360
    let a = saturation * min(lightness, 1 - lightness)
    func channel(_ offset: Double) -> Double {
      let k = (offset + hueFraction * 12).truncatingRemainder(dividingBy: 12)
      return lightness - a * max(-1, min(min(k - 3, 9 - k), 1))
    }
    return PortRGB(
      red: channel(0), green: channel(8), blue: channel(4), alpha: alpha)
  }
}

/// A CSS length, converted to points.
public enum PortLength {
  /// The browser's default root font size, which the web editor lays out against.
  public static let remSize: CGFloat = 16

  public static func parse(_ raw: String) -> CGFloat? {
    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if value.hasSuffix("rem") {
      guard let number = Double(value.dropLast(3)) else {
        return nil
      }
      return CGFloat(number) * remSize
    }
    if value.hasSuffix("px") {
      guard let number = Double(value.dropLast(2)) else {
        return nil
      }
      return CGFloat(number)
    }
    if value == "0" {
      return 0
    }
    guard let number = Double(value) else {
      return nil
    }
    return CGFloat(number)
  }
}

/// One layer of a CSS box-shadow.
public struct PortShadowLayer: Sendable, Equatable {
  public var offsetX: CGFloat
  public var offsetY: CGFloat
  public var blur: CGFloat
  public var spread: CGFloat
  public var color: PortRGB

  public init(
    offsetX: CGFloat, offsetY: CGFloat, blur: CGFloat, spread: CGFloat, color: PortRGB
  ) {
    self.offsetX = offsetX
    self.offsetY = offsetY
    self.blur = blur
    self.spread = spread
    self.color = color
  }

  /// Splits "0 0 1px 0 rgba(...), 0 7px 14px rgba(...)" into layers.
  public static func parseList(_ raw: String) -> [PortShadowLayer] {
    var layers: [PortShadowLayer] = []
    var current = ""
    var depth = 0
    var pieces: [String] = []
    for character in raw {
      if character == "(" {
        depth += 1
      } else if character == ")" {
        depth -= 1
      }
      if character == "," && depth == 0 {
        pieces.append(current)
        current = ""
        continue
      }
      current.append(character)
    }
    pieces.append(current)
    for piece in pieces {
      if let layer = parse(piece) {
        layers.append(layer)
      }
    }
    return layers
  }

  private static func parse(_ raw: String) -> PortShadowLayer? {
    var lengths: [CGFloat] = []
    var color: PortRGB?
    var token = ""
    var depth = 0
    var parts: [String] = []
    for character in raw + " " {
      if character == "(" {
        depth += 1
      } else if character == ")" {
        depth -= 1
      }
      if character.isWhitespace && depth == 0 {
        if !token.isEmpty {
          parts.append(token)
          token = ""
        }
        continue
      }
      token.append(character)
    }
    for part in parts {
      if part.contains("(") {
        color = PortRGB.parse(part)
      } else if let length = PortLength.parse(part) {
        lengths.append(length)
      } else if part.lowercased() == "inset" {
        continue
      }
    }
    guard lengths.count >= 2 else {
      return nil
    }
    return PortShadowLayer(
      offsetX: lengths.count > 0 ? lengths[0] : 0,
      offsetY: lengths.count > 1 ? lengths[1] : 0,
      blur: lengths.count > 2 ? lengths[2] : 0,
      spread: lengths.count > 3 ? lengths[3] : 0,
      color: color ?? PortRGB(red: 0, green: 0, blue: 0, alpha: 0.2)
    )
  }
}

/// The measurements the repo's stylesheets give each toolbar and panel control.
/// Every value here comes from a theme token or a stylesheet rule, so the native
/// UI keeps the web editor's sizes instead of inventing its own.
public struct PortMetrics: Sendable {
  public var buttonSize: CGFloat
  public var iconSize: CGFloat
  public var largeButtonSize: CGFloat
  public var largeIconSize: CGFloat
  public var cornerRadius: CGFloat
  public var islandPadding: CGFloat
  public var rowGap: CGFloat
  public var dividerHeight: CGFloat
  public var keybindingFontSize: CGFloat
  public var dropdownMinWidth: CGFloat
  public var dropdownOffset: CGFloat
  public var islandColor: Color
  public var islandShadows: [PortShadowLayer]
  public var borderColor: Color
  public var iconColor: Color
  public var keybindingColor: Color
  public var selectedBackground: Color
  public var selectedIconColor: Color
  public var selectedKeybindingColor: Color
  public var hoverBackground: Color
  public var disabledIconColor: Color
  public var textColor: Color
  public var surfaceLowest: Color

  public static func load(dark: Bool) -> PortMetrics {
    func color(_ token: String, fallback: Color) -> Color {
      PortTheme.color(token, dark: dark) ?? fallback
    }
    func length(_ token: String, fallback: CGFloat) -> CGFloat {
      PortTheme.length(token, dark: dark) ?? fallback
    }
    let island = color("island-bg-color", fallback: dark ? .black : .white)
    return PortMetrics(
      buttonSize: length("default-button-size", fallback: 32),
      iconSize: length("default-icon-size", fallback: 16),
      largeButtonSize: length("lg-button-size", fallback: 36),
      largeIconSize: length("lg-icon-size", fallback: 16),
      cornerRadius: length("border-radius-lg", fallback: 8),
      islandPadding: length("space-factor", fallback: 4),
      rowGap: length("space-factor", fallback: 4),
      dividerHeight: 24,
      keybindingFontSize: PortLength.remSize * 0.625,
      dropdownMinWidth: PortLength.remSize * 11.875,
      dropdownOffset: PortLength.remSize * 0.375,
      islandColor: island,
      islandShadows: PortTheme.shadowLayers("shadow-island", dark: dark),
      borderColor: color("default-border-color", fallback: island),
      iconColor: color("icon-fill-color", fallback: .primary),
      keybindingColor: color("keybinding-color", fallback: .secondary),
      selectedBackground: color("color-surface-primary-container", fallback: .accentColor),
      selectedIconColor: color("color-on-primary-container", fallback: .primary),
      selectedKeybindingColor: color("color-on-primary-container", fallback: .primary),
      hoverBackground: color("button-hover-bg", fallback: island),
      disabledIconColor: color("color-disabled", fallback: .secondary),
      textColor: color("text-primary-color", fallback: .primary),
      surfaceLowest: color("color-surface-lowest", fallback: island)
    )
  }
}

/// Draws the repo's island: the rounded, shadowed panel the toolbar and the
/// side panels float in.
public struct PortIsland<Content: View>: View {
  private let metrics: PortMetrics
  private let padding: CGFloat
  private let content: Content

  public init(
    metrics: PortMetrics, padding: CGFloat? = nil, @ViewBuilder content: () -> Content
  ) {
    self.metrics = metrics
    self.padding = padding ?? metrics.islandPadding
    self.content = content()
  }

  public var body: some View {
    content
      .padding(padding)
      .background(
        RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
          .fill(metrics.islandColor)
      )
      .portShadows(metrics.islandShadows)
  }
}

extension View {
  /// Applies each CSS shadow layer in order. Spread has no SwiftUI equivalent,
  /// so it widens the blur radius instead of being dropped.
  public func portShadows(_ layers: [PortShadowLayer], scale: CGFloat = 1) -> some View {
    layers.reduce(AnyView(self)) { view, layer in
      AnyView(
        view.shadow(
          color: Color(
            .sRGB,
            red: layer.color.red,
            green: layer.color.green,
            blue: layer.color.blue,
            opacity: layer.color.alpha
          ),
          radius: (layer.blur + layer.spread) * scale,
          x: layer.offsetX * scale,
          y: layer.offsetY * scale
        )
      )
    }
  }
}
