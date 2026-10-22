import GrafixPort
import GrafixRender
import SwiftUI

/// A colour swatch the way `.color-picker__button` draws it: rounded square,
/// checkerboard when transparent, hairline outline when nearly white, ring when
/// active.
struct ColorSwatch: View {
  let color: String?
  let dark: Bool
  var size: CGFloat = 22
  var radius: CGFloat = 4
  var active = false
  var hotkey: String?

  var body: some View {
    let p = Theme.palette(dark)
    let rgb = color.flatMap { PortRGB.parse($0) }
    let transparent = rgb == nil || (rgb?.alpha ?? 1) == 0
    let display = (color.flatMap { dark ? CSSColor.applyDarkModeFilter($0) : $0 }).flatMap { PortRGB.parse($0) } ?? rgb
    let outline = transparent || !(rgb?.isDark(threshold: 255) ?? false)
    ZStack {
      if transparent {
        Checkerboard()
      } else if let display {
        Color(.sRGB, red: display.red, green: display.green, blue: display.blue, opacity: display.alpha)
      }
      if let hotkey {
        Text(hotkey)
          .font(.system(size: 10, weight: .medium, design: .monospaced))
          .foregroundStyle(hotkeyColor(display: display, transparent: transparent))
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
          .padding(.trailing, 4)
          .padding(.bottom, 2)
      }
    }
    .frame(width: size, height: size)
    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    .overlay {
      if outline {
        RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(p.outline, lineWidth: 1)
      }
    }
    .overlay {
      if active {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
          .strokeBorder(p.primaryDarkest, lineWidth: 1)
          .padding(-2)
      }
    }
  }

  private func hotkeyColor(display: PortRGB?, transparent: Bool) -> Color {
    if transparent { return Color(white: 0.67) }
    return (display?.isDark(threshold: 160) ?? false) ? Color(white: 0.83) : Color(white: 0.2)
  }
}

private struct Checkerboard: View {
  var body: some View {
    Canvas { ctx, size in
      let cell: CGFloat = 8
      ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
      var y: CGFloat = 0
      var row = 0
      while y < size.height {
        var x: CGFloat = 0
        var col = 0
        while x < size.width {
          if (row + col) % 2 == 0 { ctx.fill(Path(CGRect(x: x, y: y, width: cell, height: cell)), with: .color(Color(white: 0.8))) }
          x += cell
          col += 1
        }
        y += cell
        row += 1
      }
    }
  }
}

/// `ColorPicker` trigger row: legend, five top picks, divider and the current colour.
struct ColorPickerRow: View {
  let dark: Bool
  let title: String
  let value: String?
  let picks: [String]
  let which: PanelPopover
  let isOpen: Bool
  let onPick: (String) -> Void
  let onToggle: () -> Void
  var showsTitle = true

  var body: some View {
    let p = Theme.palette(dark)
    PanelSection(dark: dark, title: showsTitle ? title : nil) {
      HStack(spacing: 0) {
        HStack(spacing: 5) {
          ForEach(picks, id: \.self) { c in
            Button { onPick(c) } label: { Color.clear }
              .chromeStyle { hover, pressed in
                ColorSwatch(color: c, dark: dark, active: value?.lowercased() == c)
                  .overlay {
                    if hover || pressed {
                      RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(p.primary, lineWidth: 1)
                    }
                  }
              }
              .help(c == "transparent" ? "Transparent" : c)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        Rectangle().fill(p.border).frame(width: 1, height: 16).frame(width: 15)
        Button(action: onToggle) { Color.clear }
          .chromeStyle { _, _ in
            ColorSwatch(color: value, dark: dark, size: 26, radius: 5)
              .overlay {
                if value == nil {
                  Image(systemName: "minus").font(.system(size: 10)).foregroundStyle(p.text.opacity(0.5))
                }
              }
              .overlay {
                if isOpen {
                  RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(p.primaryDarkest, lineWidth: 1).padding(-2)
                }
              }
          }
          .help(PortStrings.text("labels.colorPicker"))
      }
      .padding(.vertical, 4)
    }
    .panelAnchor(which)
  }
}

/// The popover of `ColorPicker`: base colours, the shades of the current one and
/// a hex input.
struct ColorPickerPopover: View {
  let dark: Bool
  let value: String?
  let palette: [PortColorFamily]
  let isBackground: Bool
  let onChange: (String) -> Void

  @State private var hex = ""
  @FocusState private var hexFocused: Bool

  private static let baseKeys = ["q", "w", "e", "r", "t", "a", "s", "d", "f", "g", "z", "x", "c", "v", "b"]

  private var current: (family: Int, shade: Int)? {
    guard let value else { return nil }
    let v = value.lowercased()
    for (i, f) in palette.enumerated() {
      if let s = f.shades.firstIndex(where: { $0.lowercased() == v }) { return (i, s) }
    }
    return nil
  }
  private var activeShade: Int {
    current?.shade ?? (isBackground ? PortPalette.defaultBackgroundShadeIndex : PortPalette.defaultStrokeShadeIndex)
  }

  var body: some View {
    let p = Theme.palette(dark)
    VStack(alignment: .leading, spacing: 12) {
      VStack(alignment: .leading, spacing: 0) {
        heading(PortStrings.text("colorPicker.colors"))
        grid {
          ForEach(Array(palette.enumerated()), id: \.offset) { i, f in
            let c = f.shades.count > 1 ? f.shades[min(activeShade, f.shades.count - 1)] : (f.shades.first ?? "transparent")
            swatchButton(c, active: current?.family == i, key: i < Self.baseKeys.count ? Self.baseKeys[i] : nil)
          }
        }
      }
      VStack(alignment: .leading, spacing: 0) {
        heading(PortStrings.text("colorPicker.shades"))
        if let cur = current, palette[cur.family].shades.count > 1 {
          grid {
            ForEach(Array(palette[cur.family].shades.enumerated()), id: \.offset) { i, c in
              swatchButton(c, active: i == cur.shade, key: "\(i + 1)")
            }
          }
        } else {
          Text(PortStrings.text("colorPicker.noShades"))
            .font(Theme.font(12)).foregroundStyle(p.text.opacity(0.6))
            .padding(8)
        }
      }
      hexInput(p)
    }
    .frame(width: 5 * 30 + 4 * 4 + 16)
    .onAppear { hex = (value ?? "").replacingOccurrences(of: "#", with: "") }
    .onChange(of: value) { _, v in if !hexFocused { hex = (v ?? "").replacingOccurrences(of: "#", with: "") } }
  }

  private func heading(_ t: String) -> some View {
    Text(t).font(Theme.font(12)).foregroundStyle(Theme.palette(dark).text).padding(.horizontal, 8)
  }

  private func grid<C: View>(@ViewBuilder _ content: () -> C) -> some View {
    LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 4), count: 5), alignment: .leading, spacing: 4) {
      content()
    }
    .padding(8)
  }

  private func swatchButton(_ c: String, active: Bool, key: String?) -> some View {
    let p = Theme.palette(dark)
    return Button { onChange(c) } label: { Color.clear }
      .chromeStyle { hover, pressed in
        ColorSwatch(color: c, dark: dark, size: 30, radius: 6, active: active, hotkey: key)
          .overlay {
            if (hover || pressed) && !active {
              RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(p.primary, lineWidth: 1)
            }
          }
      }
      .help(c)
  }

  private func hexInput(_ p: ChromePalette) -> some View {
    let valid = hex.isEmpty || PortRGB.parse("#" + hex) != nil
    return HStack(spacing: 8) {
      Text("#").font(Theme.font(14)).foregroundStyle(p.text.opacity(0.6))
      TextField(PortStrings.text("colorPicker.hexCode"), text: $hex)
        .textFieldStyle(.plain)
        .font(Theme.font(14))
        .foregroundStyle(p.text)
        .focused($hexFocused)
        .onSubmit { commitHex() }
        .onChange(of: hex) { _, h in
          let cleaned = h.filter { $0.isHexDigit }.prefix(8)
          if String(cleaned) != h { hex = String(cleaned) }
          if [3, 4, 6, 8].contains(cleaned.count), PortRGB.parse("#" + cleaned) != nil { onChange("#" + cleaned.lowercased()) }
        }
      Circle().fill(Color.clear).frame(width: 0)
    }
    .padding(.horizontal, 12)
    .frame(height: 32)
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .strokeBorder(hexFocused ? p.primaryDarkest : (valid ? p.border : p.danger), lineWidth: 1)
    )
    .padding(8)
  }

  private func commitHex() {
    if PortRGB.parse("#" + hex) != nil, !hex.isEmpty { onChange("#" + hex.lowercased()) }
  }
}
