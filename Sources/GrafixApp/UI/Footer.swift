import GrafixPort
import SwiftUI

/// Bottom bar. Ports Excalidraw's `Footer` (footer/Footer.tsx) with `ZoomActions`
/// and `UndoRedoActions` (components/Actions.tsx + Actions.scss), the help button
/// and the "Exit zen mode" button.
struct FooterBar: View {
  @Bindable var model: AppModel

  var body: some View {
    let doc = model.document
    let dark = true
    let zen = doc.view.zen
    HStack(alignment: .center, spacing: 0) {
      zoomGroup(doc, dark: dark, zen: zen)
      if !doc.view.viewMode && !zen {
        undoRedoGroup(doc, dark: dark).padding(.leading, 10)
      }
      if doc.view.viewMode {
        exitViewMode(doc, dark: dark).padding(.leading, 10)
      }
      Spacer(minLength: 0)
      if zen && !doc.view.viewMode {
        exitZen(doc, dark: dark)
      } else if !zen {
        helpButton(dark: dark)
      }
    }
  }

  // MARK: Zoom

  private func zoomGroup(_ doc: EditorDocument, dark: Bool, zen: Bool) -> some View {
    let p = Theme.palette(dark)
    let percent = Int((doc.view.zoom * 100).rounded())
    return HStack(spacing: 0) {
      if !zen {
        FooterButton(dark: dark, icon: "zoomout", title: "\(PortStrings.text("buttons.zoomOut")) — \(Shortcut.text("zoomOut") ?? "⌘−")",
          corners: .left) { doc.zoomOut() }
      }
      Button { doc.resetZoom() } label: { Color.clear }
        .chromeStyle { hover, pressed in
          Text("\(percent)%").font(Theme.font(14)).foregroundStyle(p.text)
            .frame(width: 60, height: 36)
            .background(
              UnevenRoundedRectangle(cornerRadii: zen ? .init(topLeading: 8, bottomLeading: 8, bottomTrailing: 8, topTrailing: 8) : .init())
                .fill(hover && !pressed ? p.hover : .clear))
        }
        .help("\(PortStrings.text("buttons.resetZoom")) — \(Shortcut.text("resetZoom") ?? "⌘0")")
        .accessibilityLabel(PortStrings.text("buttons.resetZoom"))
      if !zen {
        FooterButton(dark: dark, icon: "zoomin", title: "\(PortStrings.text("buttons.zoomIn")) — \(Shortcut.text("zoomIn") ?? "⌘+")",
          corners: .right) { doc.zoomIn() }
      }
    }
    .background(zen ? Color.clear : p.surfaceLow, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    .overlay {
      if !zen { RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(p.surfaceLowest, lineWidth: 1).padding(-1) }
    }
  }

  // MARK: Undo / redo

  private func undoRedoGroup(_ doc: EditorDocument, dark: Bool) -> some View {
    let p = Theme.palette(dark)
    return HStack(spacing: 0) {
      FooterButton(dark: dark, icon: "undo", title: "\(PortStrings.text("buttons.undo")) — ⌘Z", corners: .left, disabled: !doc.canUndo) { doc.undo() }
      FooterButton(dark: dark, icon: "redo", title: "\(PortStrings.text("buttons.redo")) — ⇧⌘Z", corners: .right, disabled: !doc.canRedo) { doc.redo() }
    }
    .background(p.surfaceLow, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(p.surfaceLowest, lineWidth: 1).padding(-1))
  }

  // MARK: Right side

  private func helpButton(dark: Bool) -> some View {
    let p = Theme.palette(dark)
    return Button { model.showHelp = true } label: { Color.clear }
      .chromeStyle { hover, pressed in
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(hover ? p.hover : p.surfaceLow)
          .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(pressed ? p.brandActive : p.surfaceLowest, lineWidth: 1).padding(-1))
          .overlay(ChromeIcon(name: "helpicon", color: p.iconFill))
          .frame(width: 36, height: 36)
      }
      .help("\(PortStrings.text("helpDialog.title")) — ?")
      .accessibilityLabel(PortStrings.text("helpDialog.title"))
  }

  /// `.disable-zen-mode`.
  private func exitZen(_ doc: EditorDocument, dark: Bool) -> some View {
    let p = Theme.palette(dark)
    return Button { doc.view.zen = false } label: { Color.clear }
      .chromeStyle { hover, pressed in
        Text(PortStrings.text("buttons.exitZenMode")).font(Theme.font(12, .medium))
          .foregroundStyle(p.text)
          .padding(10)
          .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hover ? p.hover : p.island))
          .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(pressed ? p.primary : p.border, lineWidth: 1))
      }
      .padding(.trailing, 0)
  }

  /// `.disable-view-mode`: the pencil button that leaves view mode.
  private func exitViewMode(_ doc: EditorDocument, dark: Bool) -> some View {
    let p = Theme.palette(dark)
    return Button { doc.view.viewMode = false } label: { Color.clear }
      .chromeStyle { hover, pressed in
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(hover ? p.primary : p.surfaceLow)
          .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(pressed ? p.brandActive : p.surfaceLowest, lineWidth: 1).padding(-1))
          .overlay(ChromeIcon(name: "pencil", size: 20, color: hover ? .white : p.iconFill))
          .frame(width: 36, height: 36)
      }
      .help("Exit view mode")
  }
}

/// A 36pt `ToolIcon` button of the footer groups (square inside the group, outer
/// corners rounded).
private struct FooterButton: View {
  enum Corners { case left, right }
  let dark: Bool
  let icon: String
  let title: String
  let corners: Corners
  var disabled = false
  let action: () -> Void

  var body: some View {
    let p = Theme.palette(dark)
    let r: CGFloat = 8
    let shape = UnevenRoundedRectangle(
      cornerRadii: corners == .left
        ? .init(topLeading: r, bottomLeading: r, bottomTrailing: 0, topTrailing: 0)
        : .init(topLeading: 0, bottomLeading: 0, bottomTrailing: r, topTrailing: r))
    Button(action: action) { Color.clear }
      .chromeStyle { hover, pressed in
        shape.fill(hover && !disabled ? p.hover : .clear)
          .overlay(shape.strokeBorder(pressed && !disabled ? p.brandActive : .clear, lineWidth: 1))
          .overlay(ChromeIcon(name: icon, color: disabled ? p.disabled : p.iconFill))
          .frame(width: 36, height: 36)
      }
      .disabled(disabled)
      .help(title)
      .accessibilityLabel(title)
  }
}
