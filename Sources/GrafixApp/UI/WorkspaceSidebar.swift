import AppKit
import GrafixCore
import GrafixPort
import SwiftUI

/// The workspace sidebar: Grafix's take on the Excalidraw+ dashboard. A header
/// (title, new scene, collapse), a search field, the collections list and the
/// scenes of the current collection with thumbnails. Styled after
/// components/Sidebar/Sidebar.scss (260pt wide, 1px border, 8px radii).
struct WorkspaceSidebar: View {
  @Bindable var model: AppModel
  @State private var query = ""
  @State private var allScenes: [Workspace.SceneInfo] = []
  @State private var renamingScene: String?
  @State private var renamingCollection: String?
  @State private var creatingCollection = false
  @State private var pendingTrash: TrashTarget?
  @State private var signature = ""

  private enum TrashTarget: Identifiable {
    case scene(Workspace.SceneInfo)
    case collection(String)
    var id: String {
      switch self {
      case .scene(let s): "s:" + s.id
      case .collection(let c): "c:" + c
      }
    }
  }

  private var style: SidebarStyle { SidebarStyle(dark: true) }
  private var searching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

  var body: some View {
    let style = style
    VStack(spacing: 0) {
      header(style)
      searchField(style)
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          if searching {
            searchResults(style)
          } else {
            collectionsSection(style)
            scenesSection(style)
          }
        }
        .padding(.bottom, 16)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(style.background)
    .overlay(alignment: .trailing) { Rectangle().fill(style.border).frame(width: 1) }
    .task { await watchDisk() }
    .alert(item: $pendingTrash) { target in
      switch target {
      case .scene(let s):
        Alert(
          title: Text("Move “\(s.name)” to Trash?"), message: Text("You can restore it from the Trash."),
          primaryButton: .destructive(Text("Move to Trash")) { model.trashScene(s.id) }, secondaryButton: .cancel())
      case .collection(let c):
        Alert(
          title: Text("Move collection “\(c)” to Trash?"),
          message: Text("All scenes inside it move to the Trash too."),
          primaryButton: .destructive(Text("Move to Trash")) { model.trashCollection(c) }, secondaryButton: .cancel())
      }
    }
  }

  // MARK: Header and search

  private func header(_ style: SidebarStyle) -> some View {
    HStack(spacing: 0) {
      Text("Grafix")
        .font(.system(size: 20, weight: .bold))
        .foregroundStyle(style.primary)
      Spacer()
      SidebarIconButton(icon: "plus", help: "New scene", style: style) { model.newScene() }
      SidebarIconButton(icon: "sidebar", help: "Hide sidebar (⌘B)", style: style) {
        withAnimation(.easeOut(duration: 0.15)) { model.showWorkspace = false }
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 12)
  }

  private func searchField(_ style: SidebarStyle) -> some View {
    HStack(spacing: 6) {
      PortIconView(name: "search", size: 14, color: style.muted)
      TextField("Search scenes", text: $query)
        .textFieldStyle(.plain)
        .font(.system(size: 13))
        .foregroundStyle(style.text)
      if searching {
        Button { query = "" } label: {
          Image(systemName: "xmark.circle.fill").foregroundStyle(style.muted)
        }.buttonStyle(.plain)
      }
    }
    .padding(.horizontal, 8)
    .frame(height: 30)
    .background(
      RoundedRectangle(cornerRadius: SidebarStyle.radius).fill(style.inputBackground)
        .overlay(RoundedRectangle(cornerRadius: SidebarStyle.radius).stroke(style.inputBorder, lineWidth: 1))
    )
    .padding(.horizontal, 12)
    .padding(.bottom, 4)
  }

  // MARK: Collections

  private func collectionsSection(_ style: SidebarStyle) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      SidebarSectionTitle(title: "Collections", style: style) {
        SidebarIconButton(icon: "plus", help: "New collection", style: style) { creatingCollection = true }
          .scaleEffect(0.8).frame(width: 24, height: 24)
      }
      ForEach(model.collections) { c in
        CollectionRow(
          name: c.name, count: c.sceneCount, style: style, selected: c.name == model.currentCollection,
          renaming: renamingCollection == c.name,
          onSelect: { model.selectCollection(c.name) },
          onRename: { newName in
            renamingCollection = nil
            if newName != c.name { model.renameCollection(c.name, to: newName) }
          },
          onCancelRename: { renamingCollection = nil },
          onDropScene: { id in dropScene(id, onto: c.name) }
        )
        .contextMenu {
          Button("Rename") { renamingCollection = c.name }
          Button("New scene here") { model.newScene(in: c.name) }
          Divider()
          Button("Move to Trash…", role: .destructive) { pendingTrash = .collection(c.name) }
        }
      }
      if creatingCollection {
        HStack(spacing: 8) {
          Image(systemName: "folder.badge.plus").font(.system(size: 13)).foregroundStyle(style.primary).frame(width: 18)
          InlineNameField(
            text: "", style: style, placeholder: "Collection name",
            onCommit: { name in
              creatingCollection = false
              model.newCollection(name)
            }, onCancel: { creatingCollection = false })
        }
        .padding(.horizontal, 14).frame(height: 30)
      } else {
        Button { creatingCollection = true } label: {
          HStack(spacing: 8) {
            PortIconView(name: "plus", size: 12, color: style.muted).frame(width: 18)
            Text("New collection").font(.system(size: 13)).foregroundStyle(style.muted)
            Spacer()
          }
          .padding(.horizontal, 14).frame(height: 28).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
    }
  }

  private func dropScene(_ id: String, onto collection: String) -> Bool {
    guard id.contains("/"), !id.hasPrefix(collection + "/") else { return false }
    model.moveScene(id, to: collection)
    return true
  }

  // MARK: Scenes

  @ViewBuilder
  private func scenesSection(_ style: SidebarStyle) -> some View {
    SidebarSectionTitle(title: model.currentCollection, style: style) {
      Text("\(model.scenes.count)").font(.system(size: 11, weight: .medium)).foregroundStyle(style.muted)
    }
    if model.scenes.isEmpty {
      emptyState(
        style, title: "No scenes yet", message: "Create one here, or ask an agent to draw something.",
        action: ("New scene", { model.newScene() }))
    } else {
      ForEach(model.scenes) { s in sceneRow(s, style, showCollection: false) }
    }
  }

  @ViewBuilder
  private func searchResults(_ style: SidebarStyle) -> some View {
    let q = query.trimmingCharacters(in: .whitespaces)
    let hits = allScenes.filter {
      $0.name.localizedCaseInsensitiveContains(q) || $0.collection.localizedCaseInsensitiveContains(q)
    }
    SidebarSectionTitle(title: "Results", style: style) {
      Text("\(hits.count)").font(.system(size: 11, weight: .medium)).foregroundStyle(style.muted)
    }
    if hits.isEmpty {
      emptyState(style, title: "Nothing found", message: "No scene matches “\(q)”.", action: nil)
    } else {
      ForEach(hits) { s in sceneRow(s, style, showCollection: true) }
    }
  }

  private func sceneRow(_ s: Workspace.SceneInfo, _ style: SidebarStyle, showCollection: Bool) -> some View {
    SceneRow(
      info: s, style: style, isOpen: model.document.sceneID == s.id, renaming: renamingScene == s.id,
      showCollection: showCollection,
      onOpen: { model.open(s.id) },
      onStartRename: { renamingScene = s.id },
      onRename: { name in
        renamingScene = nil
        if name != s.name { model.renameScene(s.id, to: name) }
      },
      onCancelRename: { renamingScene = nil }
    )
    .draggable(s.id)
    .contextMenu {
      Button("Open") { model.open(s.id) }
      Button("Rename") { renamingScene = s.id }
      Button("Duplicate") { model.duplicateScene(s.id) }
      Menu("Move to collection") {
        ForEach(model.collections.filter { $0.name != s.collection }) { c in
          Button(c.name) { model.moveScene(s.id, to: c.name) }
        }
      }
      Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([s.url]) }
      Divider()
      Button("Move to Trash…", role: .destructive) { pendingTrash = .scene(s) }
    }
  }

  private func emptyState(
    _ style: SidebarStyle, title: String, message: String, action: (String, () -> Void)?
  ) -> some View {
    VStack(spacing: 6) {
      Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(style.text)
      Text(message).font(.system(size: 12)).foregroundStyle(style.muted).multilineTextAlignment(.center)
      if let action {
        Button(action: action.1) {
          Text(action.0).font(.system(size: 12, weight: .semibold)).foregroundStyle(style.onPrimary)
            .padding(.horizontal, 12).frame(height: 28)
            .background(RoundedRectangle(cornerRadius: SidebarStyle.radius).fill(style.primary))
        }
        .buttonStyle(.plain).padding(.top, 4)
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.horizontal, 20).padding(.vertical, 24)
  }

  // MARK: Live refresh

  /// Polls the workspace every ~2s (a directory listing is cheap) and refreshes
  /// the model only when a file or folder actually changed, e.g. an agent
  /// created a scene through MCP.
  private func watchDisk() async {
    let workspace = model.workspace
    while !Task.isCancelled {
      let scenes = await Task.detached(priority: .utility) { (try? workspace.allScenes()) ?? [] }.value
      let sig = scenes.map { "\($0.id)@\($0.modified?.timeIntervalSince1970 ?? 0)" }.joined(separator: ";")
      if sig != signature {
        let first = signature.isEmpty && allScenes.isEmpty
        signature = sig
        allScenes = scenes
        if !first { model.refresh() }
      }
      try? await Task.sleep(for: .seconds(2))
    }
  }
}
