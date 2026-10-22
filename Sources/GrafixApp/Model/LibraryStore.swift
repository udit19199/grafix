import AppKit
import CoreGraphics
import GrafixCore
import GrafixRender
import Observation

/// Observable personal library (Excalidraw's `Library` class), one per
/// workspace root so every window shares the same items. Persists to
/// `<root>/.grafix/library.excalidrawlib` after each change and renders
/// tile thumbnails off the main thread, cached by item id + theme.
@MainActor @Observable
final class LibraryStore {
  private(set) var items: [ShapeLibraryItem]
  private(set) var thumbs: [String: CGImage] = [:]
  @ObservationIgnored let workspace: Workspace
  @ObservationIgnored private var inFlight: Set<String> = []
  @ObservationIgnored private var thumbKeys: [String: String] = [:]

  private static var stores: [String: LibraryStore] = [:]

  /// The shared store for a workspace root.
  static func shared(for workspace: Workspace) -> LibraryStore {
    let key = workspace.root.standardizedFileURL.path
    if let s = stores[key] { return s }
    let s = LibraryStore(workspace: workspace)
    stores[key] = s
    return s
  }

  private init(workspace: Workspace) {
    self.workspace = workspace
    self.items = Library.load(from: workspace).items
  }

  func item(_ id: String) -> ShapeLibraryItem? { items.first { $0.id == id } }

  func save() {
    try? Library(items: items).save(to: workspace)
  }

  // MARK: Mutations (each persists)

  @discardableResult
  func add(from scene: Scene, ids: Set<String>) -> ShapeLibraryItem? {
    guard let item = Library.item(from: scene, ids: ids) else { return nil }
    items.insert(item, at: 0)
    save()
    return item
  }

  func remove(_ ids: Set<String>) {
    items.removeAll { ids.contains($0.id) }
    for id in ids { thumbs[id] = nil; thumbKeys[id] = nil }
    save()
  }

  func removeAll() {
    items = []
    thumbs = [:]
    thumbKeys = [:]
    save()
  }

  func rename(_ id: String, to name: String) {
    guard let i = items.firstIndex(where: { $0.id == id }) else { return }
    let trimmed = name.trimmingCharacters(in: .whitespaces)
    items[i].name = trimmed.isEmpty ? nil : trimmed
    save()
  }

  /// Merges a `.excalidrawlib` file (v1 or v2); returns the number added.
  @discardableResult
  func importLibrary(from url: URL) -> Int {
    guard let data = try? Data(contentsOf: url), let lib = try? Library(data: data) else { return 0 }
    let known = Set(items.map(\.id))
    let fresh = lib.items.filter { !known.contains($0.id) }
    items.append(contentsOf: fresh)
    save()
    return fresh.count
  }

  func export(to url: URL) throws {
    try Library(items: items).encoded().write(to: url, options: .atomic)
  }

  // MARK: Thumbnails

  func thumbnail(_ item: ShapeLibraryItem, dark: Bool) -> CGImage? { thumbs[item.id] }

  private func key(_ item: ShapeLibraryItem, _ dark: Bool) -> String { "\(item.elements.count)-\(dark)" }

  /// Renders missing / stale thumbnails off-main.
  func renderThumbnails(dark: Bool, files: [String: JSONValue]) {
    for item in items {
      let k = key(item, dark)
      if thumbKeys[item.id] == k || inFlight.contains(item.id) { continue }
      inFlight.insert(item.id)
      let id = item.id
      let scene = Scene(elements: item.elements, files: files)
      Task {
        let img = await Task.detached(priority: .utility) {
          SceneRenderer.image(scene, scale: 2, maxWidth: 120, padding: 8, dark: dark, background: false)
        }.value
        inFlight.remove(id)
        if let img { thumbs[id] = img; thumbKeys[id] = k }
      }
    }
  }
}
