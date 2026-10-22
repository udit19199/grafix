import GrafixPort
import SwiftUI

extension View {
  /// Shows `content` as a floating dropdown anchored to this view and dismisses it
  /// on any click outside (Excalidraw's `DropdownMenu.Content` + click-outside).
  func chromeDropdown<Content: View>(
    isPresented: Binding<Bool>, alignment: Alignment = .bottomLeading, offset: CGSize = .zero,
    @ViewBuilder content: @escaping () -> Content
  ) -> some View {
    self
      .overlay {
        if isPresented.wrappedValue {
          Color.black.opacity(0.001)
            .frame(width: 6000, height: 6000)
            .onTapGesture { isPresented.wrappedValue = false }
        }
      }
      .overlay(alignment: alignment) {
        if isPresented.wrappedValue {
          content()
            .fixedSize()
            .offset(offset)
        }
      }
  }
}

/// A menu row: `.dropdown-menu-item` (32pt, 14px text, 16px icon, 10px gap).
struct DropdownRow: View {
  let dark: Bool
  var icon: String?
  var iconView: AnyView?
  let title: String
  var shortcut: String?
  var font: Font?
  var selected = false
  var disabled = false
  var trailing: AnyView?
  let action: () -> Void

  var body: some View {
    let p = Theme.palette(dark)
    Button(action: action) { Color.clear }
      .chromeStyle { hover, pressed in
        HStack(spacing: 10) {
          if let iconView {
            iconView
          } else if let icon {
            ChromeIcon(name: icon, size: 16, color: selected ? p.primaryDarker : p.iconFill)
          }
          Text(title).font(font ?? Theme.font(14)).foregroundStyle(p.text).lineLimit(1)
          Spacer(minLength: 12)
          if let trailing { trailing }
          if let shortcut {
            Text(shortcut).font(Theme.font(14)).foregroundStyle(p.text.opacity(0.5))
          }
        }
        .padding(.horizontal, 8)
        .frame(height: 32)
        .background(
          RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(selected ? p.primaryLight : (hover ? p.hover : .clear))
        )
        .overlay(
          RoundedRectangle(cornerRadius: 6, style: .continuous)
            .strokeBorder(pressed ? p.brandActive : .clear, lineWidth: 1)
        )
        .opacity(disabled ? 0.5 : 1)
      }
      .disabled(disabled)
  }
}

/// The dropdown surface: island background with 8pt padding, 1pt gaps.
struct DropdownSurface<Content: View>: View {
  let dark: Bool
  var minWidth: CGFloat = 0
  @ViewBuilder var content: () -> Content

  var body: some View {
    VStack(alignment: .leading, spacing: 1) { content() }
      .frame(minWidth: minWidth, alignment: .leading)
      .islandStyle(dark: dark, padding: 8)
      .overlay(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .strokeBorder(dark ? Color.black.opacity(0.15) : .clear, lineWidth: 1)
      )
  }
}

/// `.dropdown-menu-item` separator: a 1pt rule with 6pt margins.
struct DropdownDivider: View {
  let dark: Bool
  var body: some View {
    Rectangle().fill(Theme.palette(dark).border).frame(height: 1).padding(.vertical, 4)
  }
}
