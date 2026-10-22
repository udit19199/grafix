import AppKit
import GrafixCore
import GrafixPort
import SwiftUI
import UniformTypeIdentifiers

/// Excalidraw's Library sidebar (`LibraryMenu` / `LibraryMenuItems` /
/// `LibraryMenuHeaderContent`): header with a "…" menu, an "Add to library"
/// button, a 4-up grid of tiles, and the empty-state hint.
struct LibraryPanel: View {
  @Bindable var model: AppModel
  @State private var store: LibraryStore
  @State private var picked: Set<String> = []
  @State private var confirmRemoveAll = false
  @State private var renaming: ShapeLibraryItem?
  @State private var renameText = ""
  @State private var toast: String?

  init(model: AppModel) {
    self.model = model
    _store = State(initialValue: LibraryStore.shared(for: model.workspace))
  }

  var body: some View {
    let doc = model.document
    let dark = true
    let p = Theme.palette(dark)
    let _ = doc.revision
    VStack(spacing: 0) {
      header(p)
      Rectangle().fill(p.border).frame(height: 1)
      addButton(doc, p)
      if store.items.isEmpty {
        emptyState(p)
      } else {
        grid(doc, dark: dark, p)
      }
      if !picked.isEmpty { selectionBar(doc, p) }
    }
    .background(p.island)
    .overlay(alignment: .leading) { Rectangle().fill(p.border).frame(width: 1) }
    .overlay(alignment: .bottom) {
      if let toast {
        Text(toast).font(Theme.font(13, .medium)).foregroundStyle(p.text)
          .padding(.horizontal, 12).padding(.vertical, 8)
          .background(RoundedRectangle(cornerRadius: 8).fill(p.surfaceHigh))
          .padding(.bottom, 12).transition(.opacity)
      }
    }
    .onAppear { store.renderThumbnails(dark: dark, files: doc.scene.files) }
    .onChange(of: dark) { store.renderThumbnails(dark: dark, files: doc.scene.files) }
    .onChange(of: store.items.count) { store.renderThumbnails(dark: dark, files: doc.scene.files) }
    .onReceive(NotificationCenter.default.publisher(for: .grafixAddToLibrary)) { n in
      if (n.object as? EditorDocument) === doc { addSelection(doc) }
    }
    .confirmationDialog(
      PortStrings.text("alerts.resetLibrary"), isPresented: $confirmRemoveAll, titleVisibility: .visible
    ) {
      Button("Remove all", role: .destructive) { store.removeAll(); picked = [] }
    }
    .alert("Rename item", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
      TextField("Name", text: $renameText)
      Button("Rename") { if let r = renaming { store.rename(r.id, to: renameText) }; renaming = nil }
      Button("Cancel", role: .cancel) { renaming = nil }
    }
  }

  // MARK: Header

  private func header(_ p: ChromePalette) -> some View {
    HStack(spacing: 4) {
      Text(PortStrings.text("toolBar.library")).font(Theme.font(18, .bold)).foregroundStyle(p.primary)
      Spacer()
      Menu {
        Button("Import from file…") { importFile() }
        Button("Export to file…") { exportFile() }.disabled(store.items.isEmpty)
        Divider()
        Button("Browse libraries") {
          if let u = URL(string: "https://libraries.excalidraw.com") { NSWorkspace.shared.open(u) }
        }
        Divider()
        Button("Remove all", role: .destructive) { confirmRemoveAll = true }.disabled(store.items.isEmpty)
      } label: {
        PortIconView(name: "dots", size: 16, color: p.iconFill).frame(width: 32, height: 32)
      }
      .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
      Button { model.rightPanel = nil } label: {
        PortIconView(name: "cross", size: 16, color: p.iconFill).frame(width: 32, height: 32)
      }.buttonStyle(.plain)
    }
    .padding(.horizontal, 12).padding(.vertical, 8)
  }

  private func addButton(_ doc: EditorDocument, _ p: ChromePalette) -> some View {
    let enabled = doc.hasSelection
    return Button { addSelection(doc) } label: {
      HStack(spacing: 6) {
        PortIconView(name: "plus", size: 14, color: enabled ? p.primary : p.disabled)
        Text(PortStrings.text("labels.addToLibrary")).font(Theme.font(14, .semibold))
      }
      .foregroundStyle(enabled ? p.primary : p.disabled)
      .frame(maxWidth: .infinity, minHeight: 36)
      .background(RoundedRectangle(cornerRadius: 8).fill(enabled ? p.selectedBg : p.surfaceMid))
    }
    .buttonStyle(.plain).disabled(!enabled)
    .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 4)
  }

  // MARK: Body

  private func emptyState(_ p: ChromePalette) -> some View {
    VStack(spacing: 4) {
      Spacer()
      Text("No items added yet").font(Theme.font(18, .bold)).foregroundStyle(p.primary)
      Text("Select an item on canvas to add it here")
        .font(Theme.font(14)).foregroundStyle(p.keybinding).multilineTextAlignment(.center)
      Text("or install a library from the public repository, below.")
        .font(Theme.font(12)).foregroundStyle(p.keybinding).padding(.top, 8)
      Button("Browse libraries") {
        if let u = URL(string: "https://libraries.excalidraw.com") { NSWorkspace.shared.open(u) }
      }.buttonStyle(.link).font(Theme.font(13, .semibold))
      Spacer()
    }
    .padding(.horizontal, 24).frame(maxWidth: .infinity)
  }

  private func grid(_ doc: EditorDocument, dark: Bool, _ p: ChromePalette) -> some View {
    let cols = Array(repeating: GridItem(.flexible(), spacing: 16), count: 4)
    return ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        HStack {
          Text("Personal Library").font(Theme.font(18, .bold)).foregroundStyle(p.primary)
          Spacer()
          Text("\(store.items.count)").font(Theme.font(12)).foregroundStyle(p.keybinding)
        }.padding(.top, 12).padding(.bottom, 12)
        LazyVGrid(columns: cols, spacing: 8) {
          ForEach(store.items) { item in tile(item, doc: doc, dark: dark, p) }
        }
        Text("Shift-click to select several items").font(Theme.font(10)).foregroundStyle(p.keybinding)
          .padding(.top, 12)
      }
      .padding(.horizontal, 12).padding(.bottom, 16)
    }
  }

  private func tile(_ item: ShapeLibraryItem, doc: EditorDocument, dark: Bool, _ p: ChromePalette) -> some View {
    LibraryUnit(
      item: item, thumbnail: store.thumbnail(item, dark: dark), selected: picked.contains(item.id),
      palette: p, radius: 8)
      .onTapGesture {
        if NSEvent.modifierFlags.contains(.shift) {
          if picked.contains(item.id) { picked.remove(item.id) } else { picked.insert(item.id) }
        } else if picked.isEmpty {
          insert([item], into: doc)
        } else {
          picked = []
        }
      }
      .draggable(dragPayload(item)) {
        Text(item.name ?? "Library item").padding(6)
      }
      .contextMenu {
        Button("Add to canvas") { insert([item], into: doc) }
        Button("Rename…") { renameText = item.name ?? ""; renaming = item }
        Divider()
        Button("Remove", role: .destructive) { store.remove([item.id]); picked.remove(item.id) }
      }
  }

  private func selectionBar(_ doc: EditorDocument, _ p: ChromePalette) -> some View {
    HStack(spacing: 8) {
      Text("\(picked.count) selected").font(Theme.font(13)).foregroundStyle(p.keybinding)
      Spacer()
      Button("Add to canvas") { insert(store.items.filter { picked.contains($0.id) }, into: doc) }
        .buttonStyle(.bordered)
      Button("Remove", role: .destructive) { store.remove(picked); picked = [] }
        .buttonStyle(.bordered)
    }
    .padding(12)
    .overlay(alignment: .top) { Rectangle().fill(p.border).frame(height: 1) }
  }

  // MARK: Actions

  /// Dragging a selected tile drags the whole picked set.
  private func dragPayload(_ item: ShapeLibraryItem) -> String {
    let ids = picked.contains(item.id) ? store.items.map(\.id).filter(picked.contains) : [item.id]
    return "grafix-library:" + ids.joined(separator: ",")
  }

  private func addSelection(_ doc: EditorDocument) {
    guard doc.hasSelection, store.add(from: doc.scene, ids: doc.selection) != nil else { return }
    store.renderThumbnails(dark: true, files: doc.scene.files)
    flash(PortStrings.text("toast.addedToLibrary"))
  }

  private func insert(_ items: [ShapeLibraryItem], into doc: EditorDocument) {
    let centre = doc.sceneCoordinates(CGPoint(x: doc.viewSize.width / 2, y: doc.viewSize.height / 2))
    var created: [String] = []
    var offset: CGFloat = 0
    doc.commit { scene in
      for item in items {
        created += scene.insert(item, at: CGPoint(x: centre.x + offset, y: centre.y + offset))
        offset += 30
      }
    }
    doc.select(Set(created))
    picked = []
  }

  private func flash(_ text: String) {
    withAnimation { toast = text }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { withAnimation { toast = nil } }
  }

  private func importFile() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [UTType(filenameExtension: "excalidrawlib") ?? .json, .json]
    panel.allowsMultipleSelection = true
    guard panel.runModal() == .OK else { return }
    var n = 0
    for u in panel.urls { n += store.importLibrary(from: u) }
    flash(n == 0 ? "Nothing new to import" : "Imported \(n) item(s)")
  }

  private func exportFile() {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "library.excalidrawlib"
    panel.allowedContentTypes = [UTType(filenameExtension: "excalidrawlib") ?? .json]
    guard panel.runModal() == .OK, let u = panel.url else { return }
    try? store.export(to: u)
  }
}
