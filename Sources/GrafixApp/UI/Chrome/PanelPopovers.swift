import GrafixCore
import GrafixPort
import SwiftUI

/// The small pointer on a Radix popover (`Popover.Arrow`).
struct PopoverArrow: Shape {
  func path(in r: CGRect) -> Path {
    var p = Path()
    p.move(to: CGPoint(x: r.maxX, y: r.minY))
    p.addLine(to: CGPoint(x: r.minX, y: r.midY))
    p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
    p.closeSubpath()
    return p
  }
}

// MARK: - Arrowheads

enum ArrowheadOptions {
  struct Option: Identifiable {
    let value: String?
    let key: String?
    var id: String { value ?? "none" }
    var title: String { PortStrings.text("labels.arrowhead_\(value ?? "none")") }
    var icon: String { "arrowhead" + (value ?? "none").replacingOccurrences(of: "_", with: "") }
  }
  struct Section { let name: String?; let options: [Option] }

  static let visible = [
    Section(name: nil, options: [
      Option(value: nil, key: "q"), Option(value: "arrow", key: "w"),
      Option(value: "triangle", key: "e"), Option(value: "triangle_outline", key: "r"),
    ])
  ]
  static let hidden = [
    Section(name: nil, options: [
      Option(value: "circle", key: "a"), Option(value: "circle_outline", key: "s"),
      Option(value: "diamond", key: "d"), Option(value: "diamond_outline", key: "f"),
      Option(value: "bar", key: "z"),
    ]),
    Section(name: PortStrings.text("labels.cardinality"), options: [
      Option(value: "cardinality_one", key: "x"), Option(value: "cardinality_many", key: "c"),
      Option(value: "cardinality_one_or_many", key: "v"), Option(value: "cardinality_exactly_one", key: nil),
      Option(value: "cardinality_zero_or_one", key: nil), Option(value: "cardinality_zero_or_many", key: nil),
    ]),
  ]
  static var all: [Option] { (visible + hidden).flatMap(\.options) }
  static func icon(for value: String?) -> String { Option(value: value, key: nil).icon }
}

/// The start / end arrowhead trigger button (32pt, 16px wide icon).
struct ArrowheadTrigger: View {
  let dark: Bool
  let value: String??
  let flip: Bool
  let active: Bool
  let title: String
  let action: () -> Void

  var body: some View {
    let p = Theme.palette(dark)
    Button(action: action) { Color.clear }
      .chromeStyle { hover, pressed in
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(active ? p.selectedBg : (hover ? p.panelButtonHover : p.panelButtonBg))
          .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(pressed ? p.brandActive : .clear, lineWidth: 1)
          )
          .overlay {
            if let value {
              ChromeIcon(name: ArrowheadOptions.icon(for: value), size: 16, height: 8, color: active ? p.selectedFg : p.iconFill)
                .scaleEffect(x: flip ? -1 : 1, y: 1)
            }
          }
          .frame(width: 32, height: 32)
      }
      .help(title)
  }
}

/// Popover of `IconPicker`: a grid of arrowheads plus a "More options" collapsible.
struct ArrowheadPopover: View {
  let dark: Bool
  let value: String??
  let flip: Bool
  let onChange: (String?) -> Void
  @State private var more: Bool

  init(dark: Bool, value: String??, flip: Bool, onChange: @escaping (String?) -> Void) {
    self.dark = dark
    self.value = value
    self.flip = flip
    self.onChange = onChange
    let hiddenHas = value.flatMap { $0 }.map { v in ArrowheadOptions.hidden.contains { $0.options.contains { $0.value == v } } } ?? false
    _more = State(initialValue: hiddenHas)
  }

  var body: some View {
    let p = Theme.palette(dark)
    VStack(alignment: .leading, spacing: 8) {
      ForEach(Array(ArrowheadOptions.visible.enumerated()), id: \.offset) { _, s in section(s) }
      Button { more.toggle() } label: {
        HStack(spacing: 4) {
          Image(systemName: more ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .semibold))
          Text(PortStrings.text("labels.more_options")).font(Theme.font(12))
        }
        .foregroundStyle(p.text)
      }
      .buttonStyle(.plain)
      if more {
        ForEach(Array(ArrowheadOptions.hidden.enumerated()), id: \.offset) { _, s in section(s) }
      }
    }
    .padding(8)
    .background(RoundedRectangle(cornerRadius: 4).fill(p.popup))
    .shadow(color: .black.opacity(dark ? 0.5 : 0.25), radius: 5, y: 2)
  }

  private func section(_ s: ArrowheadOptions.Section) -> some View {
    let p = Theme.palette(dark)
    return VStack(alignment: .leading, spacing: 8) {
      if let name = s.name { Text(name).font(Theme.font(12)).foregroundStyle(p.text) }
      LazyVGrid(columns: Array(repeating: GridItem(.fixed(45), spacing: 8), count: 4), alignment: .leading, spacing: 8) {
        ForEach(s.options) { o in
          let active = value == .some(o.value)
          Button { onChange(o.value) } label: { Color.clear }
            .chromeStyle { hover, pressed in
              RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(active ? p.selectedBg : (pressed ? p.panelButtonBg.opacity(1) : (hover ? p.panelButtonHover : .clear)))
                .overlay(ChromeIcon(name: o.icon, size: 36, height: 18, color: active ? p.selectedFg : p.iconFill)
                  .scaleEffect(x: flip ? -1 : 1, y: 1))
                .overlay(alignment: .bottomTrailing) {
                  if let k = o.key {
                    Text(k).font(Theme.font(9)).foregroundStyle(p.keybinding).padding(.trailing, 2).padding(.bottom, 1)
                  }
                }
                .frame(width: 45, height: 28)
            }
            .help(o.key.map { "\(o.title) — \($0.uppercased())" } ?? o.title)
        }
      }
    }
  }
}

// MARK: - Fonts

enum FontChoices {
  struct Font: Identifiable {
    let id: Int
    let name: String
    let icon: String
    let title: String
  }
  static let top: [Font] = [
    Font(id: 5, name: "Excalifont", icon: "freedraw", title: PortStrings.text("labels.handDrawn")),
    Font(id: 6, name: "Nunito", icon: "fontfamilynormal", title: PortStrings.text("labels.normal")),
    Font(id: 8, name: "Comic Shanns", icon: "fontfamilycode", title: PortStrings.text("labels.code")),
  ]
  static let all: [Font] = [
    Font(id: 5, name: "Excalifont", icon: "fontfamilyhanddrawn", title: "Excalifont"),
    Font(id: 6, name: "Nunito", icon: "fontfamilynormal", title: "Nunito"),
    Font(id: 7, name: "Lilita One", icon: "fontfamilyhanddrawn", title: "Lilita One"),
    Font(id: 8, name: "Comic Shanns", icon: "fontfamilycode", title: "Comic Shanns"),
    Font(id: 1, name: "Virgil", icon: "fontfamilyhanddrawn", title: "Virgil"),
    Font(id: 3, name: "Cascadia", icon: "fontfamilycode", title: "Cascadia"),
    Font(id: 9, name: "Liberation Sans", icon: "fontfamilynormal", title: "Liberation Sans"),
  ]
  static func isTop(_ id: Int?) -> Bool { id.map { v in top.contains { $0.id == v } } ?? false }
}

/// The "Available fonts" dropdown of `FontPicker`.
struct FontPopover: View {
  let dark: Bool
  let value: Int?
  let onChange: (Int) -> Void

  var body: some View {
    let p = Theme.palette(dark)
    Fonts.register()
    return DropdownSurface(dark: dark, minWidth: 220) {
      Text("Available fonts").font(Theme.font(12)).foregroundStyle(p.text).padding(.bottom, 4)
      ForEach(FontChoices.all) { f in
        DropdownRow(
          dark: dark, icon: f.icon, title: f.name,
          font: SwiftUI.Font.custom(Fonts.fontName(for: f.id), size: 14), selected: value == f.id
        ) { onChange(f.id) }
      }
    }
  }
}

// MARK: - Link

/// Edit the link of the selected element (`hyperlink` action).
struct LinkPopover: View {
  let dark: Bool
  let initial: String
  let onSave: (String?) -> Void
  let onClose: () -> Void
  @State private var text = ""
  @FocusState private var focused: Bool

  var body: some View {
    let p = Theme.palette(dark)
    HStack(spacing: 8) {
      TextField("Paste a link", text: $text)
        .textFieldStyle(.plain)
        .font(Theme.font(14))
        .foregroundStyle(p.text)
        .focused($focused)
        .padding(.horizontal, 12)
        .frame(width: 220, height: 32)
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(focused ? p.primaryDarkest : p.border, lineWidth: 1))
        .onSubmit { onSave(text.trimmingCharacters(in: .whitespaces)); onClose() }
      if !initial.isEmpty {
        PanelButton(dark: dark, icon: "trash", title: "Remove link") { onSave(nil); onClose() }
      }
    }
    .islandStyle(dark: dark, padding: 12)
    .onAppear { text = initial; focused = true }
    .onExitCommand { onClose() }
  }
}
