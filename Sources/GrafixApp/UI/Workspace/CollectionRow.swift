import SwiftUI

/// One collection in the sidebar nav (name + scene count). Doubles as a drop
/// target for scene rows dragged onto it.
struct CollectionRow: View {
  let name: String
  let count: Int
  let style: SidebarStyle
  let selected: Bool
  let renaming: Bool
  let onSelect: () -> Void
  let onRename: (String) -> Void
  let onCancelRename: () -> Void
  let onDropScene: (String) -> Bool
  @State private var hovering = false
  @State private var targeted = false

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: selected ? "folder.fill" : "folder")
        .font(.system(size: 13))
        .foregroundStyle(selected ? style.primary : style.muted)
        .frame(width: 18)
      if renaming {
        InlineNameField(text: name, style: style, onCommit: onRename, onCancel: onCancelRename)
      } else {
        Text(name)
          .font(.system(size: 13, weight: selected ? .semibold : .medium))
          .foregroundStyle(selected ? style.selectedText : style.text)
          .lineLimit(1)
        Spacer(minLength: 4)
        Text("\(count)")
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(selected ? style.selectedText.opacity(0.7) : style.muted)
      }
    }
    .padding(.horizontal, 8)
    .frame(height: 30)
    .background(
      RoundedRectangle(cornerRadius: SidebarStyle.radius)
        .fill(targeted ? style.primary.opacity(0.18) : (selected ? style.selected : (hovering ? style.hover : .clear)))
    )
    .overlay(
      RoundedRectangle(cornerRadius: SidebarStyle.radius).stroke(style.primary, lineWidth: targeted ? 1.5 : 0)
    )
    .contentShape(RoundedRectangle(cornerRadius: SidebarStyle.radius))
    .onTapGesture(perform: onSelect)
    .onHover { hovering = $0 }
    .dropDestination(for: String.self) { ids, _ in
      guard let id = ids.first else { return false }
      return onDropScene(id)
    } isTargeted: { targeted = $0 }
    .padding(.horizontal, 6)
  }
}
