import GrafixCore
import GrafixPort
import SwiftUI

/// Hamburger menu at the top-left. Ports Excalidraw's `MainMenu` (main-menu/),
/// `DefaultItems` and the `dropdownMenu/` styles.
struct MainMenuButton: View {
  @Bindable var model: AppModel
  @State private var open = false
  @State private var showExport = false
  @State private var confirmReset = false
  @State private var backgroundPicker = false

  var body: some View {
    let doc = model.document
    let dark = true
    let p = Theme.palette(dark)
    Button { open.toggle() } label: { Color.clear }
      .chromeStyle { hover, pressed in
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(p.surfaceHigh)
          .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .strokeBorder(pressed || open ? p.primary : p.border, lineWidth: 1)
          )
          .overlay(ChromeIcon(name: "hamburger", color: p.iconFill))
          .frame(width: 36, height: 36)
      }
      .help(PortStrings.text("buttons.menu"))
      .accessibilityLabel(PortStrings.text("buttons.menu"))
      .chromeDropdown(isPresented: $open, alignment: .topLeading, offset: CGSize(width: 0, height: 36 + 8)) {
        menu(dark: dark)
      }
      .onAppear {
        switch DebugChrome.open {
        case "menu": open = true
        case "bg-picker": open = true; backgroundPicker = true
        case "export": showExport = true
        default: break
        }
      }
      .sheet(isPresented: $showExport) { ExportSheet(document: doc) }
      .alert(PortStrings.text("buttons.clearReset"), isPresented: $confirmReset) {
        Button(PortStrings.text("buttons.cancel"), role: .cancel) {}
        Button(PortStrings.text("buttons.confirm"), role: .destructive) { doc.clearCanvas() }
      } message: {
        Text(PortStrings.text("alerts.clearReset"))
      }
  }

  private func menu(dark: Bool) -> some View {
    let doc = model.document
    let p = Theme.palette(dark)
    func close(_ action: @escaping () -> Void) -> () -> Void { { open = false; action() } }
    return DropdownSurface(dark: dark, minWidth: 212) {
      DropdownRow(dark: dark, icon: "load", title: PortStrings.text("buttons.load"), shortcut: Shortcut.text("loadScene"),
        action: close { model.importFile() })
      DropdownRow(dark: dark, icon: "export", title: PortStrings.text("buttons.export"), shortcut: Shortcut.text("saveScene"),
        action: close { ExportActions.exportExcalidraw(doc) })
      DropdownRow(dark: dark, icon: "image", title: PortStrings.text("buttons.exportImage"), shortcut: Shortcut.text("imageExport"),
        action: close { showExport = true })
      DropdownRow(dark: dark, icon: "search", title: PortStrings.text("search.title"), shortcut: Shortcut.text("searchMenu"),
        action: close { model.showFind = true })
      DropdownRow(dark: dark, icon: "helpicon", title: PortStrings.text("helpDialog.title"), shortcut: "?",
        action: close { model.showHelp = true })
      DropdownRow(dark: dark, icon: "trash", title: PortStrings.text("buttons.clearReset"), shortcut: Shortcut.text("clearCanvas"),
        action: close { confirmReset = true })
      DropdownDivider(dark: dark)
      canvasBackground(dark: dark)
      DropdownDivider(dark: dark)
      DropdownRow(dark: dark, icon: "grid", title: PortStrings.text("labels.toggleGrid"), shortcut: Shortcut.text("gridMode"),
        trailing: check(doc.view.grid, p)) {
        doc.view.grid.toggle()
        doc.onOverlayChange?()
      }
      DropdownRow(dark: dark, icon: "zen", title: PortStrings.text("buttons.zenMode"), shortcut: Shortcut.text("zenMode"),
        trailing: check(doc.view.zen, p), action: close { doc.view.zen.toggle() })
      DropdownRow(dark: dark, icon: "eye", title: PortStrings.text("labels.viewMode"), shortcut: Shortcut.text("viewMode"),
        trailing: check(doc.view.viewMode, p), action: close { doc.view.viewMode.toggle() })
      DropdownRow(dark: dark, icon: "sidebar", title: "Workspace sidebar", shortcut: "⌘B",
        trailing: check(model.showWorkspace, p), action: close { model.showWorkspace.toggle() })
    }
  }

  private func check(_ on: Bool, _ p: ChromePalette) -> AnyView? {
    on ? AnyView(ChromeIcon(name: "check", color: p.primaryDarker)) : nil
  }

  /// `ChangeCanvasBackground`: group title and the five quick picks.
  private func canvasBackground(dark: Bool) -> some View {
    let doc = model.document
    let p = Theme.palette(dark)
    _ = doc.revision
    return VStack(alignment: .leading, spacing: 0) {
      Text(PortStrings.text("labels.canvasBackground"))
        .font(Theme.font(12)).foregroundStyle(p.text)
        .padding(.top, 8).padding(.horizontal, 10).padding(.bottom, 2)
      ColorPickerRow(
        dark: dark, title: "", value: doc.scene.viewBackgroundColor,
        picks: PortPalette.canvasBackgroundPicks, which: .background, isOpen: backgroundPicker,
        onPick: { doc.setBackground($0) }, onToggle: { backgroundPicker.toggle() }, showsTitle: false
      )
      .padding(.horizontal, 10)
      .frame(width: 196)
      .overlay(alignment: .topLeading) {
        if backgroundPicker {
          ColorPickerPopover(
            dark: dark, value: doc.scene.viewBackgroundColor, palette: PortPalette.backgroundPalette, isBackground: true,
            onChange: { doc.setBackground($0) }
          )
          .islandStyle(dark: dark, padding: 12)
          .fixedSize()
          .offset(x: 196 + 24, y: -40)
        }
      }
    }
  }
}

/// Shortcut text the way Excalidraw prints it on macOS ("⌘⇧E").
enum Shortcut {
  static func text(_ action: String) -> String? {
    PortShortcuts.first(action).map(format)
  }

  static func format(_ glyph: String) -> String {
    var out = ""
    var rest = Substring(glyph)
    while let plus = rest.firstIndex(of: "+"), plus != rest.startIndex {
      switch rest[..<plus] {
      case "Cmd": out += "⌘"
      case "Shift": out += "⇧"
      case "Option": out += "⌥"
      case "Ctrl": out += "⌃"
      default: out += rest[..<plus]
      }
      rest = rest[rest.index(after: plus)...]
    }
    switch rest {
    case "Delete": out += "⌫"
    case "Enter": out += "↵"
    case "Escape": out += "⎋"
    default: out += rest.uppercased()
    }
    return out
  }
}


