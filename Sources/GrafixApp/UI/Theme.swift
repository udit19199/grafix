import GrafixCore
import GrafixPort
import SwiftUI

/// Excalidraw theme tokens (css/theme.scss via GrafixPort.PortTheme) and the
/// shared building blocks of the chrome: palette, font, islands, buttons.
enum Theme {
  static func canvasBackground(_ dark: Bool) -> Color { dark ? Color(red: 0.07, green: 0.07, blue: 0.07) : .white }
  static func metrics(_ dark: Bool) -> PortMetrics { PortMetrics.load(dark: dark) }
  static func palette(_ dark: Bool) -> ChromePalette { dark ? ChromePalette.darkValue : ChromePalette.lightValue }

  /// Excalidraw's UI font ("Assistant"), registered from the bundled woff2 files.
  static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
    Fonts.register()
    return Font.custom("Assistant", size: size).weight(weight)
  }
}

/// Every colour the chrome needs, resolved once per theme from the CSS tokens.
struct ChromePalette: Sendable {
  let dark: Bool
  let island, border, text, iconFill, keybinding, hover, selectedBg, selectedFg: Color
  let surfaceLow, surfaceLowest, surfaceMid, surfaceHigh: Color
  let primary, primaryDarkest, primaryDarker, primaryLight, brandActive, brandHover: Color
  let disabled, sliderTrack, sliderThumb, outline, popup, danger: Color
  let islandShadows: [PortShadowLayer]
  let popupShadow: [PortShadowLayer]

  /// `--button-bg` inside `.shape-actions-theme-scope`.
  var panelButtonBg: Color { dark ? surfaceHigh : surfaceMid }
  /// `--button-hover-bg` inside `.shape-actions-theme-scope`.
  var panelButtonHover: Color { dark ? Color(red: 0.212, green: 0.208, blue: 0.255) : surfaceHigh }

  static let lightValue = ChromePalette(dark: false)
  static let darkValue = ChromePalette(dark: true)

  private init(dark: Bool) {
    func c(_ token: String, _ fallback: Color = .gray) -> Color { PortTheme.color(token, dark: dark) ?? fallback }
    self.dark = dark
    island = c("island-bg-color", dark ? .black : .white)
    border = c("default-border-color")
    text = c("text-primary-color")
    iconFill = c("icon-fill-color")
    keybinding = c("keybinding-color")
    hover = c("button-hover-bg")
    selectedBg = c("color-surface-primary-container")
    selectedFg = c("color-on-primary-container")
    surfaceLow = c("color-surface-low")
    surfaceLowest = c("color-surface-lowest")
    surfaceMid = c("color-surface-mid")
    surfaceHigh = c("color-surface-high")
    primary = c("color-primary")
    primaryDarkest = c("color-primary-darkest")
    primaryDarker = c("color-primary-darker")
    primaryLight = c("color-primary-light")
    brandActive = c("color-brand-active")
    brandHover = c("color-brand-hover")
    disabled = c("color-disabled")
    sliderTrack = c("color-slider-track")
    sliderThumb = c("color-slider-thumb")
    outline = dark ? c("color-gray-80") : c("color-gray-20")
    popup = c("popup-bg-color")
    danger = c("color-danger")
    islandShadows = PortTheme.shadowLayers("shadow-island", dark: dark)
    popupShadow = PortTheme.shadowLayers("modal-shadow", dark: dark)
  }
}

// MARK: - Icons

/// An Excalidraw icon at an explicit colour. `filled` paints stroked shapes as
/// solid too, which is what `.fillable.ToolIcon--checked svg { fill }` does.
struct ChromeIcon: View {
  let name: String
  var size: CGFloat = 16
  var height: CGFloat?
  let color: Color
  var filled = false

  var body: some View {
    let shapes = PortIcons.icon(name)?.shapes ?? []
    let h = height ?? size
    ZStack {
      ForEach(Array(shapes.enumerated()), id: \.offset) { _, shape in
        let path = Path(SVGPath.cgPath(shape.d, size: CGSize(width: size, height: h)))
        if shape.filled {
          path.fill(color)
        } else {
          if filled { path.fill(color) }
          path.stroke(color, style: StrokeStyle(lineWidth: shape.strokeWidth * size / 512, lineCap: .round, lineJoin: .round))
        }
      }
    }
    .frame(width: size, height: h)
    .accessibilityHidden(true)
  }
}

// MARK: - Islands

extension View {
  /// Excalidraw's `.Island`: island background, large radius and its shadow.
  func islandStyle(dark: Bool, padding: CGFloat = 0, radius: CGFloat = 8) -> some View {
    let p = Theme.palette(dark)
    return self
      .padding(padding)
      .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(p.island))
      .portShadows(p.islandShadows)
  }
}

// MARK: - Buttons

/// A button style that hands its content the hover and pressed state, so each
/// chrome button can draw Excalidraw's per-state background and border.
struct ChromeButtonStyle<Out: View>: ButtonStyle {
  let render: (_ hover: Bool, _ pressed: Bool) -> Out

  func makeBody(configuration: Configuration) -> some View {
    Inner(pressed: configuration.isPressed, render: render)
  }

  private struct Inner: View {
    let pressed: Bool
    let render: (Bool, Bool) -> Out
    @State private var hover = false
    var body: some View {
      render(hover, pressed)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }
  }
}

extension Button {
  /// Draws the button with `render(hover, pressed)`; the label is ignored.
  @MainActor func chromeStyle<Out: View>(@ViewBuilder _ render: @escaping (_ hover: Bool, _ pressed: Bool) -> Out) -> some View {
    buttonStyle(ChromeButtonStyle(render: render))
  }
}

/// Excalidraw's `outlineButtonIconStyles` button used in the properties panel:
/// 32pt square, 1px border, `selected` fills with the primary container.
struct PanelButton: View {
  let dark: Bool
  let icon: String
  var selected = false
  var mixed = false
  var title: String = ""
  var width: CGFloat = 32
  var iconSize: CGFloat = 16
  let action: () -> Void

  var body: some View {
    let p = Theme.palette(dark)
    Button(action: action) { Color.clear }
      .chromeStyle { hover, pressed in
        let bg = selected ? p.selectedBg : (hover ? p.panelButtonHover : p.panelButtonBg)
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(bg)
          .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .strokeBorder(pressed ? p.brandActive : (selected ? p.selectedBg : .clear), lineWidth: 1)
          )
          .overlay(ChromeIcon(name: icon, size: iconSize, color: selected ? p.selectedFg : p.iconFill))
          .frame(width: width, height: 32)
      }
      .help(title)
      .accessibilityLabel(title)
      .accessibilityAddTraits(selected ? .isSelected : [])
  }
}
