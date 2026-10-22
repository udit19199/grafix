import GrafixPort
import SwiftUI

/// Excalidraw palette for the workspace sidebar (components/Sidebar/Sidebar.scss,
/// css/theme.scss tokens), resolved for the light or dark theme.
struct SidebarStyle {
  let dark: Bool
  var background: Color { token("sidebar-bg-color", dark ? Color(red: 0.137, green: 0.137, blue: 0.161) : .white) }
  var border: Color { token("sidebar-border-color", dark ? Color(white: 0.2) : Color(red: 0.945, green: 0.941, blue: 1)) }
  var text: Color { token("text-primary-color", dark ? Color(white: 0.9) : Color(white: 0.11)) }
  var muted: Color { dark ? Color(white: 0.62) : Color(white: 0.48) }
  var primary: Color { token("color-primary", Color(red: 0.412, green: 0.396, blue: 0.859)) }
  var onPrimary: Color { .white }
  var selected: Color { token("color-primary-light", Color(red: 0.89, green: 0.886, blue: 0.996)) }
  var selectedText: Color { token("color-on-primary-container", Color(red: 0.01, green: 0, blue: 0.39)) }
  var hover: Color { token("button-hover-bg", dark ? Color(white: 0.25) : Color(red: 0.945, green: 0.941, blue: 1)) }
  var inputBackground: Color { token("input-bg-color", dark ? Color(white: 0.07) : .white) }
  var inputBorder: Color { token("input-border-color", dark ? Color(white: 0.18) : Color(white: 0.8)) }
  var thumbBackground: Color { dark ? Color(white: 0.07) : .white }
  var danger: Color { token("color-danger", Color(red: 0.86, green: 0.41, blue: 0.4)) }

  static let radius: CGFloat = 8

  private func token(_ name: String, _ fallback: Color) -> Color {
    PortTheme.color(name, dark: dark) ?? fallback
  }
}

/// A 28pt icon button (Excalidraw's `.sidebar__header__buttons button`).
struct SidebarIconButton: View {
  let icon: String
  let help: String
  let style: SidebarStyle
  let action: () -> Void
  @State private var hovering = false

  var body: some View {
    Button(action: action) {
      PortIconView(name: icon, size: 16, color: style.text)
        .frame(width: 30, height: 30)
        .background(
          RoundedRectangle(cornerRadius: SidebarStyle.radius).fill(hovering ? style.hover : .clear))
    }
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
    .help(help)
  }
}

/// Small section caption with an optional trailing control.
struct SidebarSectionTitle<Trailing: View>: View {
  let title: String
  let style: SidebarStyle
  @ViewBuilder var trailing: Trailing

  var body: some View {
    HStack {
      Text(title.uppercased())
        .font(.system(size: 11, weight: .semibold))
        .tracking(0.5)
        .foregroundStyle(style.muted)
      Spacer()
      trailing
    }
    .padding(.horizontal, 14)
    .padding(.top, 14)
    .padding(.bottom, 4)
  }
}

/// A single-line text field for inline rename / create. Commits on Return or
/// when it loses focus, cancels on Escape.
struct InlineNameField: View {
  @State var text: String
  let style: SidebarStyle
  var placeholder = ""
  let onCommit: (String) -> Void
  let onCancel: () -> Void
  @FocusState private var focused: Bool
  @State private var finished = false

  var body: some View {
    TextField(placeholder, text: $text)
      .textFieldStyle(.plain)
      .font(.system(size: 13, weight: .medium))
      .foregroundStyle(style.text)
      .padding(.horizontal, 6)
      .padding(.vertical, 3)
      .background(
        RoundedRectangle(cornerRadius: 6).fill(style.inputBackground)
          .overlay(RoundedRectangle(cornerRadius: 6).stroke(style.primary, lineWidth: 1.5))
      )
      .focused($focused)
      .onSubmit { finish(commit: true) }
      .onExitCommand { finish(commit: false) }
      .onChange(of: focused) { _, now in if !now { finish(commit: true) } }
      .onAppear { focused = true }
  }

  private func finish(commit: Bool) {
    guard !finished else { return }
    finished = true
    let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if commit, !name.isEmpty { onCommit(name) } else { onCancel() }
  }
}
