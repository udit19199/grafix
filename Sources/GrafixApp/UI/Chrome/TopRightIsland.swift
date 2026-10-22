import GrafixPort
import SwiftUI

/// Top-right buttons in Excalidraw's `.sidebar-trigger` style (the "Library"
/// button): 36pt tall, icon plus a 12px label, `filledButtonOnCanvas` surface.
struct TopRightIsland: View {
  @Bindable var model: AppModel

  var body: some View {
    let doc = model.document
    let dark = true
    let _ = doc.revision
    let compact = doc.viewSize.width < 1100
    let hasSlides = !doc.scene.slideFrames.isEmpty
    HStack(spacing: compact ? 8 : 12) {
      TriggerButton(dark: dark, compact: compact, icon: "frame", label: "Slides", active: model.rightPanel == "slides") {
        model.rightPanel = model.rightPanel == "slides" ? nil : "slides"
      }
      TriggerButton(dark: dark, compact: compact, icon: "present", label: "Present", active: false, disabled: !hasSlides) {
        model.presentingSlide = 0
        model.presenting = true
      }
      TriggerButton(dark: dark, compact: compact, icon: "messagecircle", label: "Chat", active: model.showChat) { model.showChat.toggle() }
      TriggerButton(dark: dark, compact: compact, icon: "library", label: PortStrings.text("toolBar.library"), active: model.rightPanel == "library") {
        model.rightPanel = model.rightPanel == "library" ? nil : "library"
      }
    }
  }
}

private struct TriggerButton: View {
  let dark: Bool
  var compact = false
  let icon: String
  let label: String
  let active: Bool
  var disabled = false
  let action: () -> Void

  var body: some View {
    let p = Theme.palette(dark)
    Button(action: action) { Color.clear }
      .chromeStyle { hover, pressed in
        HStack(spacing: 8) {
          ChromeIcon(name: icon, color: active ? p.selectedFg : (disabled ? p.disabled : p.iconFill))
          if !compact { Text(label).font(Theme.font(12)).tracking(0.4).foregroundStyle(active ? p.selectedFg : (disabled ? p.disabled : p.text)) }
        }
        .padding(.horizontal, compact ? 9 : 10)
        .frame(height: 36)
        .background(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(active ? p.selectedBg : (hover && !disabled ? p.hover : p.surfaceLow))
        )
        .overlay(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(pressed && !disabled ? p.brandActive : p.surfaceLowest, lineWidth: 1).padding(-1)
        )
      }
      .disabled(disabled)
      .help(label)
      .accessibilityLabel(label)
  }
}
