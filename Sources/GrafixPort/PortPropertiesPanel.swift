import SwiftUI

/// The element style the properties panel edits. Field names match the
/// Excalidraw element keys so the values round-trip into the document unchanged.
public struct PortElementStyle: Sendable, Equatable {
  public var strokeColor: String
  public var backgroundColor: String
  public var strokeWidth: Double
  public var roughness: Double
  public var opacity: Double

  public init(
    strokeColor: String = "#1e1e1e",
    backgroundColor: String = "transparent",
    strokeWidth: Double = 2,
    roughness: Double = 1,
    opacity: Double = 100
  ) {
    self.strokeColor = strokeColor
    self.backgroundColor = backgroundColor
    self.strokeWidth = strokeWidth
    self.roughness = roughness
    self.opacity = opacity
  }
}

/// The left-hand properties panel.
///
/// The layout follows the repo's `.selected-shape-actions` column: a 0.75rem
/// heading above each control, 0.5rem between rows, and each colour row laid out
/// as a 1fr swatch strip, a 15px separator column and the 1.625rem trigger
/// swatch (`.color-picker-container` in ColorPicker.scss).
public struct PortPropertiesPanel: View {
  @Binding public var style: PortElementStyle
  public let dark: Bool

  public init(style: Binding<PortElementStyle>, dark: Bool) {
    self._style = style
    self.dark = dark
  }

  private var metrics: PortMetrics { PortMetrics.load(dark: dark) }

  public var body: some View {
    VStack(alignment: .leading, spacing: PortLength.remSize * 0.5) {
      PortColorRow(
        label: PortStrings.text("labels.stroke"),
        value: style.strokeColor,
        picks: PortPalette.strokePicks,
        palette: PortPalette.strokePalette,
        dark: dark,
        metrics: metrics,
        onChange: { style.strokeColor = $0 }
      )
      PortColorRow(
        label: PortStrings.text("labels.background"),
        value: style.backgroundColor,
        picks: PortPalette.backgroundPicks,
        palette: PortPalette.backgroundPalette,
        dark: dark,
        metrics: metrics,
        onChange: { style.backgroundColor = $0 }
      )
      WidthRow(style: $style, metrics: metrics, dark: dark)
      SloppinessRow(style: $style, metrics: metrics, dark: dark)
      OpacityRow(style: $style, metrics: metrics, dark: dark)
    }
    // .App-menu__left: 0.75rem padding inside a 12.5rem box.
    .padding(PortLength.remSize * 0.75)
    .frame(width: PortLength.remSize * 12.5, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
        .fill(metrics.islandColor)
        .portShadows(metrics.islandShadows)
    )
  }
}

/// The repo's heading for a control in the styles panel
/// (`.selected-shape-actions h3`): 0.75rem, regular weight, 0.25rem below.
struct PortRowHeading: View {
  let text: String
  let metrics: PortMetrics

  var body: some View {
    Text(text)
      .font(.system(size: PortLength.remSize * 0.75))
      .fontWeight(.regular)
      .foregroundStyle(metrics.textColor)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.bottom, PortLength.remSize * 0.25)
  }
}

/// The repo's `ButtonSeparator`: a 1px by 1rem line, centred in a 15px column.
struct PortButtonSeparator: View {
  let color: Color

  var body: some View {
    Rectangle()
      .fill(color)
      .frame(width: 1, height: PortLength.remSize)
      .frame(width: 15)
  }
}

/// A colour row: the heading, the quick picks, a separator, and the swatch that
/// opens the full palette.
private struct PortColorRow: View {
  let label: String
  let value: String
  let picks: [String]
  let palette: [PortColorFamily]
  let dark: Bool
  let metrics: PortMetrics
  let onChange: (String) -> Void

  @State private var expanded = false

  /// The picker swatch sizes from ColorPicker.scss.
  private static let swatchSize: CGFloat = PortLength.remSize * 1.375
  private static let triggerSize: CGFloat = PortLength.remSize * 1.625
  private var swatchGap: CGFloat { 5 }

  /// Where the value sits in the palette, so the grid can show that family's
  /// shades the way PickerColorList does.
  private var shadeIndex: Int {
    for family in palette {
      if let index = family.shades.firstIndex(of: value) {
        return index
      }
    }
    return PortPalette.defaultStrokeShadeIndex
  }

  private var selectedFamily: PortColorFamily? {
    palette.first { $0.shades.contains(value) }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      PortRowHeading(text: label, metrics: metrics)
      HStack(spacing: 0) {
        HStack(spacing: swatchGap) {
          ForEach(picks, id: \.self) { pick in
            PortSwatch(
              color: pick,
              size: Self.swatchSize,
              radius: 4,
              isSelected: pick == value,
              dark: dark,
              onSelect: {
                onChange(pick)
                expanded = false
              }
            )
          }
          Spacer(minLength: 0)
        }
        // grid-template-columns: 1fr 15px 1.625rem
        .frame(maxWidth: .infinity)
        PortButtonSeparator(color: metrics.borderColor)
        PortSwatch(
          color: value,
          size: Self.triggerSize,
          radius: 5,
          isSelected: false,
          dark: dark,
          onSelect: { expanded.toggle() }
        )
        .help(PortStrings.text("labels.colorPicker"))
      }
      if expanded {
        PickerGrid(
          family: selectedFamily,
          palette: palette,
          shadeIndex: shadeIndex,
          value: value,
          dark: dark,
          metrics: metrics,
          onSelect: { onChange($0) }
        )
        .padding(.top, 8)
      }
    }
  }
}

/// The full palette: the selected family's shades, then one swatch per palette
/// entry, laid out five to a row.
private struct PickerGrid: View {
  let family: PortColorFamily?
  let palette: [PortColorFamily]
  let shadeIndex: Int
  let value: String
  let dark: Bool
  let metrics: PortMetrics
  let onSelect: (String) -> Void

  private let swatchSize: CGFloat = PortLength.remSize * 1.375
  private let swatchGap: CGFloat = 5

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let family, family.shades.count > 1 {
        HStack(spacing: swatchGap) {
          ForEach(family.shades, id: \.self) { shade in
            PortSwatch(
              color: shade, size: swatchSize, radius: 4, isSelected: shade == value,
              dark: dark, onSelect: { onSelect(shade) })
          }
          Spacer(minLength: 0)
        }
      }
      // One swatch per palette entry, in the repo's declaration order.
      let columns = Array(repeating: GridItem(.fixed(swatchSize), spacing: swatchGap), count: 5)
      LazyVGrid(columns: columns, alignment: .leading, spacing: swatchGap) {
        ForEach(Array(palette.enumerated()), id: \.offset) { _, entry in
          let color =
            entry.shades.count > 1
            ? entry.shades[min(shadeIndex, entry.shades.count - 1)] : entry.shades.first ?? ""
          PortSwatch(
            color: color, size: swatchSize, radius: 4, isSelected: color == value, dark: dark,
            onSelect: { onSelect(color) })
        }
      }
    }
  }
}

/// One palette swatch, drawn the way `.color-picker__button` is: a 1.375rem
/// rounded square of the colour, an outline when the colour is nearly white, a
/// checkerboard when it is transparent, and a 1px ring just outside the swatch
/// when it is the current colour.
private struct PortSwatch: View {
  let color: String
  let size: CGFloat
  let radius: CGFloat
  let isSelected: Bool
  let dark: Bool
  let onSelect: () -> Void

  /// ColorPicker.scss sets `--color-outline` from the gray scale per theme.
  private var outlineColor: Color {
    (dark ? PortTheme.color("color-gray-80", dark: true) : PortTheme.color("color-gray-20"))
      ?? .black.opacity(0.1)
  }

  private var rgb: PortRGB? { PortRGB.parse(color) }
  private var isTransparent: Bool { rgb == nil || (rgb?.alpha ?? 1) == 0 }

  /// `.has-outline`: a light swatch needs a hairline to read against the island.
  private var hasOutline: Bool {
    guard let rgb else {
      return true
    }
    return !rgb.isDark(threshold: 240)
  }

  var body: some View {
    Button(action: onSelect) {
      ZStack {
        if isTransparent {
          Checkerboard()
        } else if let rgb {
          Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: rgb.alpha)
        }
        if hasOutline {
          RoundedRectangle(cornerRadius: radius, style: .continuous)
            .stroke(outlineColor, lineWidth: 1)
        }
      }
      .frame(width: size, height: size)
      .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
      .overlay {
        if isSelected {
          // .active .color-picker__button-outline: a 1px ring drawn 1px outside.
          RoundedRectangle(cornerRadius: radius, style: .continuous)
            .stroke(
              PortTheme.color("color-primary-darkest", dark: dark) ?? .accentColor, lineWidth: 1
            )
            .padding(-1)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(color)
    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
  }
}

/// The checkerboard the repo shows for a transparent colour
/// (`.color-picker__button.is-transparent`).
private struct Checkerboard: View {
  private let squares = 4

  var body: some View {
    GeometryReader { geometry in
      let cell = geometry.size.width / CGFloat(squares)
      ZStack {
        Color.white
        ForEach(0..<(squares * squares), id: \.self) { index in
          let row = index / squares
          let column = index % squares
          if (row + column).isMultiple(of: 2) {
            Color(white: 0.85)
              .frame(width: cell, height: cell)
              .position(x: cell * (CGFloat(column) + 0.5), y: cell * (CGFloat(row) + 0.5))
          }
        }
      }
    }
  }
}

/// Stroke width: the repo's three icons, thin to extra bold.
private struct WidthRow: View {
  @Binding var style: PortElementStyle
  let metrics: PortMetrics
  let dark: Bool

  private var options: [(width: Double, label: String, icon: String)] {
    [
      (1, PortStrings.text("labels.thin"), "strokewidthbase"),
      (2, PortStrings.text("labels.bold"), "strokewidthbold"),
      (4, PortStrings.text("labels.extraBold"), "strokewidthextrabold"),
    ]
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      PortRowHeading(text: PortStrings.text("labels.strokeWidth"), metrics: metrics)
      HStack(spacing: 8) {
        ForEach(options, id: \.width) { option in
          Button {
            style.strokeWidth = option.width
          } label: {
            PortIconView(name: option.icon, size: metrics.iconSize, color: metrics.iconColor)
              .frame(width: metrics.buttonSize, height: metrics.buttonSize)
              .background(
                RoundedRectangle(cornerRadius: metrics.cornerRadius - 2, style: .continuous)
                  .fill(
                    style.strokeWidth == option.width
                      ? metrics.selectedBackground : metrics.hoverBackground)
              )
          }
          .buttonStyle(.plain)
          .help(option.label)
          .accessibilityLabel(option.label)
        }
      }
    }
  }
}

/// Sloppiness: the repo's three hand-drawn icons.
private struct SloppinessRow: View {
  @Binding var style: PortElementStyle
  let metrics: PortMetrics
  let dark: Bool

  private var options: [(value: Double, label: String, icon: String)] {
    [
      (0, PortStrings.text("labels.architect"), "architect"),
      (1, PortStrings.text("labels.artist"), "artist"),
      (2, PortStrings.text("labels.cartoonist"), "cartoonist"),
    ]
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      PortRowHeading(text: PortStrings.text("labels.sloppiness"), metrics: metrics)
      HStack(spacing: 8) {
        ForEach(options, id: \.value) { option in
          Button {
            style.roughness = option.value
          } label: {
            PortIconView(name: option.icon, size: metrics.iconSize, color: metrics.iconColor)
              .frame(width: metrics.buttonSize, height: metrics.buttonSize)
              .background(
                RoundedRectangle(cornerRadius: metrics.cornerRadius - 2, style: .continuous)
                  .fill(
                    style.roughness == option.value
                      ? metrics.selectedBackground : metrics.hoverBackground)
              )
          }
          .buttonStyle(.plain)
          .help(option.label)
          .accessibilityLabel(option.label)
        }
      }
    }
  }
}

/// Opacity: a slider with the value shown, as the repo's opacity control does.
private struct OpacityRow: View {
  @Binding var style: PortElementStyle
  let metrics: PortMetrics
  let dark: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      PortRowHeading(text: PortStrings.text("labels.opacity"), metrics: metrics)
      HStack(spacing: 8) {
        Slider(value: $style.opacity, in: 0...100)
          .controlSize(.small)
        Text("\(Int(style.opacity))%")
          .font(.system(size: PortLength.remSize * 0.75))
          .foregroundStyle(metrics.textColor)
          .frame(width: 38, alignment: .trailing)
      }
    }
  }
}
