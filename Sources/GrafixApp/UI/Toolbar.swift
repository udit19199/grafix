import GrafixPort
import SwiftUI

/// Top-centre tool island. Ports Excalidraw's `Toolbar.tsx` (the island, lock
/// button, dividers, extra-tools dropdown) and `ToolIcon.scss` (36pt buttons,
/// key badge bottom-right, checked / hover / active states).
struct ToolbarIsland: View {
  let document: EditorDocument
  @State private var extraOpen = false

  private static let mainTools: [Tool] = [
    .hand, .selection, .rectangle, .diamond, .ellipse, .arrow, .line, .freedraw, .text, .image, .eraser,
  ]
  private static let extraTools: [Tool] = [.frame, .embeddable, .laser, .lasso]

  var body: some View {
    let dark = true
    let p = Theme.palette(dark)
    let active = document.view.tool
    HStack(spacing: document.viewSize.width < 860 ? 1 : 4) {
      lockButton(p)
      divider(p).padding(.trailing, 4)
      ForEach(Self.mainTools, id: \.self) { tool in
        ToolButton(document: document, tool: tool, active: active == tool && tool != .image, dark: dark) {
          pick(tool)
        }
      }
      divider(p).padding(.leading, 4)
      extraTrigger(p, active: active)
    }
    .islandStyle(dark: dark, padding: 4)
    .chromeDropdown(isPresented: $extraOpen, alignment: .topTrailing, offset: CGSize(width: 0, height: 44 + 6)) {
      DropdownSurface(dark: dark, minWidth: 190) {
        ForEach(Self.extraTools, id: \.self) { tool in
          let info = PortTools.tool(tool.rawValue)
          DropdownRow(
            dark: dark, icon: info?.iconName ?? tool.rawValue, title: info?.label ?? tool.rawValue.capitalized,
            shortcut: info?.keyBindingLabel, selected: active == tool
          ) {
            extraOpen = false
            document.setTool(tool)
          }
        }
      }
    }
    .onAppear { if DebugChrome.open == "extra" { extraOpen = true } }
    .onChange(of: document.view.tool) { _, _ in extraOpen = false }
    .animation(nil, value: extraOpen)
  }

  private func pick(_ tool: Tool) {
    extraOpen = false
    if tool == .image {
      let c = document.sceneCoordinates(CGPoint(x: document.viewSize.width / 2, y: document.viewSize.height / 2))
      document.insertImageFromPanel(at: c)
    } else {
      document.setTool(tool)
    }
  }

  private func divider(_ p: ChromePalette) -> some View {
    Rectangle().fill(p.border).frame(width: 1, height: 24)
  }

  /// `LockButton`: toggles the tool lock (Q).
  private func lockButton(_ p: ChromePalette) -> some View {
    let locked = document.view.toolLocked
    return Button { document.view.toolLocked.toggle() } label: { Color.clear }
      .chromeStyle { hover, pressed in
        ToolIconBox(
          p: p, checked: locked, hover: hover, pressed: pressed,
          icon: ChromeIcon(name: locked ? "lock" : "unlock", size: 16, color: locked ? p.selectedFg : p.iconFill))
      }
      .help("\(PortStrings.text("toolBar.lock")) — Q")
      .accessibilityLabel(PortStrings.text("toolBar.lock"))
  }

  /// `App-toolbar__extra-tools-trigger`: transparent, shows the active extra tool.
  private func extraTrigger(_ p: ChromePalette, active: Tool) -> some View {
    let shown = Self.extraTools.contains(active)
    let icon = shown ? (PortTools.tool(active.rawValue)?.iconName ?? "dots") : "dots"
    return Button { extraOpen.toggle() } label: { Color.clear }
      .chromeStyle { hover, pressed in
        ToolIconBox(
          p: p, checked: shown, hover: hover, pressed: pressed || extraOpen,
          icon: ChromeIcon(name: icon, size: 16, color: shown ? p.selectedFg : p.iconFill))
      }
      .help(PortStrings.text("toolBar.extraTools"))
      .accessibilityLabel(PortStrings.text("toolBar.extraTools"))
  }
}

/// The 36pt rounded square behind a toolbar icon (`.ToolIcon__icon`).
private struct ToolIconBox<Icon: View>: View {
  let p: ChromePalette
  let checked: Bool
  let hover: Bool
  let pressed: Bool
  let icon: Icon
  var badge: String?

  var body: some View {
    RoundedRectangle(cornerRadius: 8, style: .continuous)
      .fill(checked ? p.selectedBg : (hover || pressed ? p.hover : .clear))
      .overlay(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .strokeBorder(pressed ? p.brandActive : .clear, lineWidth: 1)
      )
      .overlay(icon)
      .overlay(alignment: .bottomTrailing) {
        if let badge {
          Text(badge)
            .font(Theme.font(10))
            .foregroundStyle(checked ? p.selectedFg : p.keybinding)
            .padding(.trailing, 3)
            .padding(.bottom, 2)
        }
      }
      .frame(width: 36, height: 36)
  }
}

/// One tool button with its key badge.
private struct ToolButton: View {
  let document: EditorDocument
  let tool: Tool
  let active: Bool
  let dark: Bool
  let action: () -> Void

  var body: some View {
    let p = Theme.palette(dark)
    let info = PortTools.tool(tool.rawValue)
    let label = info?.label ?? tool.rawValue
    let hint = info?.shortcutHint ?? ""
    let badge = (document.view.zen || tool == .hand) ? nil : info?.keyBindingLabel
    Button(action: action) { Color.clear }
      .chromeStyle { hover, pressed in
        ToolIconBox(
          p: p, checked: active, hover: hover, pressed: pressed,
          icon: ChromeIcon(
            name: info?.iconName ?? tool.rawValue, size: 16, color: active ? p.selectedFg : p.iconFill,
            filled: active && (info?.fillable ?? false)),
          badge: badge)
      }
      .help(hint.isEmpty ? label : "\(label) — \(hint)")
      .accessibilityLabel(label)
      .accessibilityAddTraits(active ? .isSelected : [])
  }
}
