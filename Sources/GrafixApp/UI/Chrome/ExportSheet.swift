import AppKit
import GrafixCore
import GrafixPort
import GrafixRender
import SwiftUI

/// "Export image" dialog. Ports Excalidraw's `ImageExportDialog`: a preview next
/// to background / dark mode / scale options and the export buttons.
struct ExportSheet: View {
  let document: EditorDocument
  @Environment(\.dismiss) private var dismiss
  @State private var background = true
  @State private var scale: CGFloat = 2
  @State private var selectionOnly: Bool
  @State private var preview: NSImage?
  @State private var copied = false

  init(document: EditorDocument) {
    self.document = document
    _selectionOnly = State(initialValue: document.hasSelection)
  }

  var body: some View {
    let ui = true
    let p = Theme.palette(ui)
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text(PortStrings.text("buttons.exportImage").replacingOccurrences(of: "...", with: ""))
          .font(Theme.font(20)).foregroundStyle(p.text)
        Spacer()
        Button { dismiss() } label: { Color.clear }
          .chromeStyle { hover, _ in
            ChromeIcon(name: "cross", size: 24, color: hover ? p.text : p.disabled).frame(width: 24, height: 24)
          }
          .accessibilityLabel("Close")
      }
      .padding(.bottom, 12)
      .overlay(alignment: .bottom) { Rectangle().fill(p.border).frame(height: 1) }
      .padding(.bottom, 20)

      HStack(alignment: .top, spacing: 24) {
        previewPane(p)
        VStack(alignment: .leading, spacing: 16) {
          option(p, "Background", toggle: $background)
          if document.hasSelection { option(p, "Only selected", toggle: $selectionOnly) }
          VStack(alignment: .leading, spacing: 6) {
            Text("Scale").font(Theme.font(14)).foregroundStyle(p.text)
            HStack(spacing: 8) {
              ForEach([1, 2, 3] as [CGFloat], id: \.self) { s in
                scaleButton(p, s)
              }
            }
          }
          Spacer(minLength: 8)
          actionButton(p, title: "PNG", icon: "png", primary: true) {
            dismiss()
            ExportActions.exportPNG(document, selectionOnly: selectionOnly && document.hasSelection, scale: scale, background: background)
          }
          actionButton(p, title: PortStrings.text("buttons.copyToClipboard"), icon: "copy", primary: false) { copyPNG() }
          if !document.scene.slideFrames.isEmpty {
            actionButton(p, title: "Slides as PDF", icon: "present", primary: false) {
              dismiss()
              ExportActions.exportPDF(document, slides: true)
            }
          }
        }
        .frame(width: 220)
      }
    }
    .padding(32)
    .frame(width: 780, height: 500)
    .background(p.island)
    .task(id: renderKey) { await renderPreview() }
  }

  private var renderKey: String { "\(background)-\(selectionOnly)-\(document.revision)" }

  private func previewPane(_ p: ChromePalette) -> some View {
    ZStack {
      PreviewChecker(dark: true)
      if let preview {
        Image(nsImage: preview).resizable().scaledToFit().padding(12)
      } else {
        Text("Cannot export empty canvas.").font(Theme.font(14)).foregroundStyle(p.disabled)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(p.border, lineWidth: 1))
  }

  private func option(_ p: ChromePalette, _ title: String, toggle: Binding<Bool>) -> some View {
    HStack {
      Text(title).font(Theme.font(14)).foregroundStyle(p.text)
      Spacer()
      ChromeToggle(dark: true, isOn: toggle)
    }
  }

  private func scaleButton(_ p: ChromePalette, _ s: CGFloat) -> some View {
    let on = scale == s
    return Button { scale = s } label: { Color.clear }
      .chromeStyle { hover, _ in
        Text("\(Int(s))×").font(Theme.font(14)).foregroundStyle(on ? p.selectedFg : p.text)
          .frame(width: 44, height: 32)
          .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(on ? p.selectedBg : (hover ? p.panelButtonHover : p.panelButtonBg)))
      }
  }

  private func actionButton(_ p: ChromePalette, title: String, icon: String, primary: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) { Color.clear }
      .chromeStyle { hover, pressed in
        HStack(spacing: 8) {
          ChromeIcon(name: icon, size: 16, color: primary ? .white : p.text)
          Text(title).font(Theme.font(14, .semibold)).foregroundStyle(primary ? .white : p.text)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 40)
        .background(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(primary ? (pressed ? p.primaryDarker : (hover ? p.brandHover : p.primary)) : (hover ? p.panelButtonHover : p.panelButtonBg))
        )
      }
  }

  // MARK: Rendering

  private func scene() -> GrafixCore.Scene { ExportActions.exportScene(document, selectionOnly: selectionOnly && document.hasSelection) }

  private func renderPreview() async {
    let scene = scene()
    let background = background
    let image = await Task.detached(priority: .userInitiated) { () -> NSImage? in
      guard let cg = SceneRenderer.image(scene, scale: 1, maxWidth: 1000, padding: 10, dark: true, background: background) else { return nil }
      return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }.value
    preview = image
  }

  private func copyPNG() {
    guard let img = SceneRenderer.image(scene(), scale: scale, padding: 10, dark: true, background: background),
      let png = SceneRenderer.pngData(img)
    else { return }
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setData(png, forType: .png)
    dismiss()
  }
}

private struct PreviewChecker: View {
  let dark: Bool
  var body: some View {
    Canvas { ctx, size in
      let cell: CGFloat = 10
      let a = dark ? Color(white: 0.14) : Color.white
      let b = dark ? Color(white: 0.18) : Color(white: 0.93)
      ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(a))
      var y: CGFloat = 0
      var r = 0
      while y < size.height {
        var x: CGFloat = 0
        var c = 0
        while x < size.width {
          if (r + c) % 2 == 0 { ctx.fill(Path(CGRect(x: x, y: y, width: cell, height: cell)), with: .color(b)) }
          x += cell
          c += 1
        }
        y += cell
        r += 1
      }
    }
  }
}

/// Excalidraw's `Switch`: a 40x20 pill with a 14pt thumb.
struct ChromeToggle: View {
  let dark: Bool
  @Binding var isOn: Bool

  var body: some View {
    let p = Theme.palette(dark)
    Button { isOn.toggle() } label: { Color.clear }
      .chromeStyle { _, _ in
        Capsule()
          .fill(isOn ? p.primary : p.panelButtonBg)
          .overlay(Capsule().strokeBorder(isOn ? p.primary : p.border, lineWidth: 1))
          .overlay(alignment: isOn ? .trailing : .leading) {
            Circle().fill(isOn ? .white : p.iconFill.opacity(0.7)).frame(width: 12, height: 12).padding(.horizontal, 3)
          }
          .frame(width: 36, height: 20)
      }
      .accessibilityAddTraits(.isToggle)
  }
}
