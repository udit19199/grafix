import GrafixCore
import SwiftUI

/// Excalidraw's command palette (components/CommandPalette): type to run any
/// action, tool or scene. Cmd+Shift+P / Cmd+/.
struct CommandPalette: View {
  @Bindable var model: AppModel
  @State private var query = ""
  @State private var highlighted = 0
  @FocusState private var focused: Bool

  struct Command: Identifiable {
    let id: String
    let title: String
    let category: String
    let shortcut: String?
    let run: @MainActor () -> Void
  }

  var commands: [Command] {
    let doc = model.document
    var list: [Command] = []
    func add(_ title: String, _ category: String, _ shortcut: String? = nil, _ run: @escaping @MainActor () -> Void) {
      list.append(Command(id: category + title, title: title, category: category, shortcut: shortcut, run: run))
    }
    for tool in Tool.allCases {
      add(tool.rawValue.capitalized, "Tools", tool.key.map { String($0).uppercased() }) { doc.setTool(tool) }
    }
    add("Undo", "Editor", "⌘Z") { doc.undo() }
    add("Redo", "Editor", "⇧⌘Z") { doc.redo() }
    add("Select all", "Editor", "⌘A") { doc.selectAll() }
    add("Duplicate selection", "Editor", "⌘D") { doc.duplicateSelected() }
    add("Delete selection", "Editor", "⌫") { doc.deleteSelected() }
    add("Group selection", "Editor", "⌘G") { doc.groupSelected() }
    add("Ungroup selection", "Editor", "⇧⌘G") { doc.ungroupSelected() }
    add("Bring to front", "Editor", "⌥⌘]") { doc.reorderSelected(.front) }
    add("Send to back", "Editor", "⌥⌘[") { doc.reorderSelected(.back) }
    add("Align left", "Editor") { doc.alignSelected(.left) }
    add("Align center", "Editor") { doc.alignSelected(.centerX) }
    add("Align right", "Editor") { doc.alignSelected(.right) }
    add("Align top", "Editor") { doc.alignSelected(.top) }
    add("Align middle", "Editor") { doc.alignSelected(.centerY) }
    add("Align bottom", "Editor") { doc.alignSelected(.bottom) }
    add("Distribute horizontally", "Editor") { doc.distributeSelected(horizontally: true) }
    add("Distribute vertically", "Editor") { doc.distributeSelected(horizontally: false) }
    add("Flip horizontal", "Editor", "⇧H") { doc.flipSelected(horizontal: true) }
    add("Flip vertical", "Editor", "⇧V") { doc.flipSelected(horizontal: false) }
    add("Lock / unlock selection", "Editor", "⇧⌘L") { doc.toggleLockSelected() }
    add("Add link", "Editor", "⌘K") { doc.editLinkOfSelection() }
    add("Copy styles", "Editor", "⌥⌘C") { doc.copyStyles() }
    add("Paste styles", "Editor", "⌥⌘V") { doc.pasteStyles() }
    add("Copy as PNG", "Export", "⇧⌥C") { ExportActions.copyPNG(doc, selectionOnly: doc.hasSelection) }
    add("Export image…", "Export", "⇧⌘E") { ExportActions.exportPNG(doc) }
    add("Export slides as PDF…", "Export") { ExportActions.exportPDF(doc, slides: true) }
    add("Save as .excalidraw…", "Export", "⇧⌘S") { ExportActions.exportExcalidraw(doc) }
    add("Zoom in", "View", "⌘+") { doc.zoomIn() }
    add("Zoom out", "View", "⌘-") { doc.zoomOut() }
    add("Reset zoom", "View", "⌘0") { doc.resetZoom() }
    add("Zoom to fit", "View", "⇧1") { doc.zoomToFitAll() }
    add("Zoom to selection", "View", "⇧2") { doc.zoomToSelection() }
    add("Toggle grid", "View", "⌘'") { doc.view.grid.toggle(); doc.onOverlayChange?() }
    add("Zen mode", "View", "⌥Z") { doc.view.zen.toggle() }
    add("View mode", "View", "⌥R") { doc.view.viewMode.toggle() }
    add("Workspace sidebar", "View", "⌘B") { model.showWorkspace.toggle() }
    add("Slides", "Presentation", "⇧⌘K") { model.rightPanel = model.rightPanel == "slides" ? nil : "slides" }
    add("Library", "View") { model.rightPanel = model.rightPanel == "library" ? nil : "library" }
    add("Present", "Presentation", "⇧⌘↩") {
      model.presentingSlide = 0
      model.presenting = true
    }
    add("Add slide", "Presentation") {
      var id: String?
      doc.commit { id = $0.addSlide() }
      if let id { doc.select([id]) }
    }
    add("AI chat", "AI", "⌘J") { model.showChat.toggle() }
    add("Find on canvas", "Editor", "⌘F") { model.showFind = true }
    add("New scene", "Scenes", "⌘N") { model.newScene() }
    add("Import .excalidraw…", "Scenes", "⌘O") { model.importFile() }
    add("Keyboard shortcuts", "Help", "?") { model.showHelp = true }
    for scene in model.scenes {
      add("Open \(scene.name)", "Scenes") { model.open(scene.id) }
    }
    return list
  }

  var filtered: [Command] {
    let q = query.lowercased().trimmingCharacters(in: .whitespaces)
    guard !q.isEmpty else { return commands }
    return commands.filter { fuzzy($0.title.lowercased(), q) || $0.category.lowercased().hasPrefix(q) }
  }

  private func fuzzy(_ text: String, _ q: String) -> Bool {
    if text.contains(q) { return true }
    var it = text.makeIterator()
    for c in q where c != " " {
      while let t = it.next(), t != c {}
      if it.next() == nil && !text.hasSuffix(String(c)) { return text.contains(c) && q.count <= 2 }
    }
    return false
  }

  var body: some View {
    let dark = true
    let items = filtered
    VStack(spacing: 0) {
      TextField("Search commands, tools, scenes…", text: $query)
        .textFieldStyle(.plain)
        .font(.system(size: 16))
        .padding(14)
        .focused($focused)
        .onSubmit { run(items) }
        .onChange(of: query) { _, _ in highlighted = 0 }
      Divider()
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, c in
              HStack {
                Text(c.title).font(.system(size: 13))
                Spacer()
                Text(c.category).font(.system(size: 11)).foregroundStyle(.secondary)
                if let s = c.shortcut {
                  Text(s).font(.system(size: 11, design: .rounded)).padding(.horizontal, 5).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.12)))
                }
              }
              .padding(.horizontal, 14).padding(.vertical, 7)
              .background(i == highlighted ? Color(red: 0.88, green: 0.87, blue: 1).opacity(0.25) : .clear)
              .contentShape(Rectangle())
              .onTapGesture {
                highlighted = i
                run(items)
              }
              .id(i)
            }
          }
        }
        .onChange(of: highlighted) { _, v in proxy.scrollTo(v) }
      }
      .frame(maxHeight: 360)
    }
    .frame(width: 560)
    .background(RoundedRectangle(cornerRadius: 12).fill(Color(red: 0.14, green: 0.14, blue: 0.16)))
    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.08)))
    .shadow(color: .black.opacity(0.18), radius: 24, y: 8)
    .onAppear { focused = true }
    .onKeyPress(.downArrow) {
      highlighted = min(highlighted + 1, max(0, items.count - 1))
      return .handled
    }
    .onKeyPress(.upArrow) {
      highlighted = max(highlighted - 1, 0)
      return .handled
    }
    .onKeyPress(.escape) {
      model.showCommandPalette = false
      return .handled
    }
  }

  private func run(_ items: [Command]) {
    guard items.indices.contains(highlighted) else { return }
    let command = items[highlighted]
    model.showCommandPalette = false
    DispatchQueue.main.async { command.run() }
  }
}

/// Find on canvas (Excalidraw's search, Cmd+F): matches text and labels,
/// Enter cycles through results and zooms to each.
struct FindBar: View {
  @Bindable var model: AppModel
  @State private var query = ""
  @State private var index = 0
  @FocusState private var focused: Bool

  var matches: [Element] {
    _ = model.document.revision
    let q = query.trimmingCharacters(in: .whitespaces)
    guard !q.isEmpty else { return [] }
    return model.document.scene.search(query: q, limit: 500)
  }

  var body: some View {
    let doc = model.document
    let found = matches
    HStack(spacing: 8) {
      TextField("Find on canvas", text: $query)
        .textFieldStyle(.plain)
        .focused($focused)
        .onSubmit { step(found, 1) }
        .frame(width: 220)
      Text(found.isEmpty ? (query.isEmpty ? "" : "No results") : "\(index + 1)/\(found.count)")
        .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
      Button { step(found, -1) } label: { Image(systemName: "chevron.up") }.buttonStyle(.plain).disabled(found.isEmpty)
      Button { step(found, 1) } label: { Image(systemName: "chevron.down") }.buttonStyle(.plain).disabled(found.isEmpty)
      Button { model.showFind = false } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
    }
    .padding(.horizontal, 12).padding(.vertical, 8)
    .background(RoundedRectangle(cornerRadius: 8).fill(true ? Color(red: 0.14, green: 0.14, blue: 0.16) : .white))
    .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
    .onAppear { focused = true }
    .onChange(of: query) { _, _ in
      index = 0
      focus(found: matches)
    }
    .onKeyPress(.escape) {
      model.showFind = false
      return .handled
    }
  }

  private func step(_ found: [Element], _ d: Int) {
    guard !found.isEmpty else { return }
    index = (index + d + found.count) % found.count
    focus(found: found)
  }

  private func focus(found: [Element]) {
    guard found.indices.contains(index) else { return }
    let e = found[index]
    let doc = model.document
    doc.select([e.id])
    doc.zoom(toFit: e.bounds, viewSize: doc.viewSize, padding: 120, maxZoom: max(doc.view.zoom, 1))
  }
}
