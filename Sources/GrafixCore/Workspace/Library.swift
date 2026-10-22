import CoreGraphics
import Foundation

/// The personal shape library (Excalidraw's Library), stored as an
/// Excalidraw `.excalidrawlib` v2 file at `<root>/.grafix/library.excalidrawlib`
/// so it can be exported to / imported from excalidraw.com.
public struct ShapeLibraryItem: Identifiable, Equatable, Sendable {
  public var id: String
  public var name: String?
  public var created: Double
  public var elements: [Element]

  public init(id: String = Element.newID(), name: String? = nil, elements: [Element]) {
    self.id = id
    self.name = name
    self.created = Element.now()
    self.elements = elements
  }

  public var json: JSONValue {
    var o: [String: JSONValue] = [
      "id": .string(id), "status": "unpublished", "created": .number(created),
      "elements": .array(elements.map { .object($0.json) }),
    ]
    if let name { o["name"] = .string(name) }
    return .object(o)
  }

  public init?(json: JSONValue) {
    guard let o = json.object else { return nil }
    let raw = o["elements"]?.array ?? []
    let elements = raw.compactMap(\.object).map(Element.init(json:)).filter { !$0.isDeleted }
    guard !elements.isEmpty else { return nil }
    self.id = o["id"]?.string ?? Element.newID()
    self.name = o["name"]?.string
    self.created = o["created"]?.number ?? Element.now()
    self.elements = elements
  }
}

public struct Library: Sendable {
  public var items: [ShapeLibraryItem] = []
  public init(items: [ShapeLibraryItem] = []) { self.items = items }

  public static func url(in workspace: Workspace) -> URL {
    workspace.root.appendingPathComponent(".grafix/library.excalidrawlib")
  }

  /// Parses `.excalidrawlib` v2 (`libraryItems`) and v1 (`library`: [[elements]]).
  public init(data: Data) throws {
    guard let o = try JSONValue.parse(data).object else { throw SceneError.notExcalidraw }
    if let items = o["libraryItems"]?.array {
      self.items = items.compactMap(ShapeLibraryItem.init(json:))
    } else if let v1 = o["library"]?.array {
      self.items = v1.compactMap { group in
        let els = group.array?.compactMap(\.object).map(Element.init(json:)) ?? []
        return els.isEmpty ? nil : ShapeLibraryItem(elements: els)
      }
    } else {
      throw SceneError.notExcalidraw
    }
  }

  public func encoded() -> Data {
    let root: JSONValue = [
      "type": "excalidrawlib", "version": 2, "source": "https://github.com/grafix",
      "libraryItems": .array(items.map(\.json)),
    ]
    return Data(root.serialized(pretty: true).utf8)
  }

  public static func load(from workspace: Workspace) -> Library {
    guard let data = try? Data(contentsOf: url(in: workspace)), let lib = try? Library(data: data) else { return Library() }
    return lib
  }

  public func save(to workspace: Workspace) throws {
    let u = Library.url(in: workspace)
    try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
    try encoded().write(to: u, options: .atomic)
  }

  /// Makes a library item from scene elements (labels and bindings kept).
  public static func item(from scene: Scene, ids: Set<String>, name: String? = nil) -> ShapeLibraryItem? {
    let all = scene.withLabels(scene.expandedSelection(ids))
    let elements = scene.elements.filter { all.contains($0.id) && !$0.isDeleted }
    guard !elements.isEmpty else { return nil }
    return ShapeLibraryItem(name: name, elements: elements)
  }
}

extension Scene {
  /// Inserts a library item centred at `point` with fresh ids. Returns the new top-level ids.
  @discardableResult
  public mutating func insert(_ item: ShapeLibraryItem, at point: CGPoint) -> [String] {
    var temp = Scene(elements: item.elements)
    let ids = Set(item.elements.map(\.id))
    guard let b = temp.bounds(of: ids) else { return [] }
    let created = temp.duplicate(ids, offset: CGPoint(x: point.x - b.midX, y: point.y - b.midY))
    let copies = temp.elements.filter { !ids.contains($0.id) }.map { e -> Element in
      var c = e
      c.frameId = nil
      return c
    }
    elements.append(contentsOf: copies)
    return created
  }
}
