import GrafixCore
import GrafixPort
import SwiftUI

/// One scene in the workspace sidebar: thumbnail, name, "edited X ago" and a
/// slides badge. Ports the look of Excalidraw+'s dashboard scene cards.
struct SceneRow: View {
  let info: Workspace.SceneInfo
  let style: SidebarStyle
  let isOpen: Bool
  let renaming: Bool
  /// Show the collection name instead of a plain time (search results).
  var showCollection = false
  let onOpen: () -> Void
  let onStartRename: () -> Void
  let onRename: (String) -> Void
  let onCancelRename: () -> Void
  @State private var hovering = false
  @State private var entry: ThumbnailStore.Entry?

  private var key: String { ThumbnailStore.key(info, dark: style.dark) }

  var body: some View {
    HStack(spacing: 10) {
      SceneThumbnail(entry: entry, style: style, selected: isOpen)
      VStack(alignment: .leading, spacing: 3) {
        if renaming {
          InlineNameField(text: info.name, style: style, onCommit: onRename, onCancel: onCancelRename)
        } else {
          Text(info.name)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isOpen ? style.selectedText : style.text)
            .lineLimit(1)
            .truncationMode(.tail)
            .onTapGesture(count: 2, perform: onStartRename)
        }
        Text(subtitle)
          .font(.system(size: 11))
          .foregroundStyle(isOpen ? style.selectedText.opacity(0.7) : style.muted)
          .lineLimit(1)
        SlidesBadge(count: entry?.slides ?? 0, style: style)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .background(
      RoundedRectangle(cornerRadius: SidebarStyle.radius)
        .fill(isOpen ? style.selected : (hovering ? style.hover : .clear))
    )
    .contentShape(RoundedRectangle(cornerRadius: SidebarStyle.radius))
    .onTapGesture(perform: onOpen)
    .onHover { hovering = $0 }
    .padding(.horizontal, 6)
    .task(id: key) {
      if let hit = ThumbnailStore.shared.cached(key) {
        entry = hit
      } else if let loaded = await ThumbnailStore.shared.load(url: info.url, key: key, dark: style.dark) {
        entry = loaded
      }
    }
  }

  private var subtitle: String {
    let when = info.modified.map(Self.relative) ?? "never"
    return showCollection ? "\(info.collection) · \(when)" : "Edited \(when)"
  }

  static func relative(_ date: Date) -> String {
    let seconds = -date.timeIntervalSinceNow
    if seconds < 60 { return "just now" }
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .short
    return f.localizedString(for: date, relativeTo: Date())
  }
}

/// Count of slide frames, shown only for scenes that have any.
private struct SlidesBadge: View {
  let count: Int
  let style: SidebarStyle

  var body: some View {
    if count > 0 {
      HStack(spacing: 3) {
        PortIconView(name: "present", size: 10, color: style.primary)
        Text("\(count) slide\(count == 1 ? "" : "s")")
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(style.primary)
      }
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(Capsule().fill(style.primary.opacity(0.14)))
    }
  }
}

/// Thumbnail tile: the rendered scene on a white (or dark) card.
private struct SceneThumbnail: View {
  let entry: ThumbnailStore.Entry?
  let style: SidebarStyle
  let selected: Bool

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 6).fill(style.thumbBackground)
      if let image = entry?.image {
        Image(nsImage: image).resizable().scaledToFit().padding(2)
      } else if entry == nil {
        PortIconView(name: "image", size: 14, color: style.muted.opacity(0.5))
      }
    }
    .frame(width: 76, height: 54)
    .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? style.primary : style.border, lineWidth: 1))
    .clipShape(RoundedRectangle(cornerRadius: 6))
  }
}
