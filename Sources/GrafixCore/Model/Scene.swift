import CoreGraphics
import Foundation

/// A whole `.excalidraw` document: elements, view state and embedded files.
///
/// `elements` is in z-order (first = bottom). Deleted elements stay in the array
/// with `isDeleted = true`, like Excalidraw, so merges and undo work; use
/// `visibleElements` for drawing.
public struct Scene: Equatable, Sendable {
  public var elements: [Element]
  /// Excalidraw appState subset (viewBackgroundColor, gridSize, ...), preserved.
  public var appState: [String: JSONValue]
  /// fileId -> {mimeType, id, dataURL, created, ...}
  public var files: [String: JSONValue]
  /// Unknown top-level keys, preserved.
  public var extra: [String: JSONValue]

  public init(
    elements: [Element] = [], appState: [String: JSONValue] = [:],
    files: [String: JSONValue] = [:], extra: [String: JSONValue] = [:]
  ) {
    self.elements = elements
    self.appState = appState
    self.files = files
    self.extra = extra
  }

  public var visibleElements: [Element] { elements.filter { !$0.isDeleted } }

  public var viewBackgroundColor: String {
    get { appState["viewBackgroundColor"]?.string ?? "#ffffff" }
    set { appState["viewBackgroundColor"] = .string(newValue) }
  }

  public func element(_ id: String) -> Element? {
    elements.first { $0.id == id }
  }

  public func indexOf(_ id: String) -> Int? {
    elements.firstIndex { $0.id == id }
  }

  /// Map of id -> array position. Build once per operation for O(1) lookups.
  public func positions() -> [String: Int] {
    var map: [String: Int] = [:]
    map.reserveCapacity(elements.count)
    for (i, e) in elements.enumerated() { map[e.id] = i }
    return map
  }

  /// Mutates one element by id and bumps its version. Returns false if missing.
  @discardableResult
  public mutating func update(_ id: String, _ change: (inout Element) -> Void) -> Bool {
    guard let i = indexOf(id) else { return false }
    change(&elements[i])
    elements[i].bump()
    return true
  }

  /// Frames, in presentation order (see Presentation.swift).
  public var frames: [Element] { visibleElements.filter(\.isFrame) }
}

// MARK: - File format

public enum SceneError: Error, LocalizedError, Equatable {
  case notExcalidraw
  case invalidElement(Int)
  public var errorDescription: String? {
    switch self {
    case .notExcalidraw: "Not an Excalidraw scene: expected {\"type\":\"excalidraw\", \"elements\": [...]}."
    case .invalidElement(let i): "Element at position \(i) is not a JSON object."
    }
  }
}

extension Scene {
  public init(data: Data) throws {
    guard let root = try JSONValue.parse(data).object else { throw SceneError.notExcalidraw }
    try self.init(root: root)
  }

  /// Accepts a full scene (`type: excalidraw`) or a bare `{elements: [...]}`.
  public init(root: [String: JSONValue]) throws {
    if let type = root["type"]?.string, type != "excalidraw" { throw SceneError.notExcalidraw }
    guard let raw = root["elements"]?.array else { throw SceneError.notExcalidraw }
    var elements: [Element] = []
    elements.reserveCapacity(raw.count)
    for (i, item) in raw.enumerated() {
      guard let o = item.object else { throw SceneError.invalidElement(i) }
      elements.append(Element(json: o))
    }
    self.init(
      elements: elements, appState: root["appState"]?.object ?? [:],
      files: root["files"]?.object ?? [:],
      extra: root.filter { !["type", "version", "source", "elements", "appState", "files"].contains($0.key) }
    )
  }

  public var root: [String: JSONValue] {
    var o = extra
    o["type"] = "excalidraw"
    o["version"] = 2
    o["source"] = "https://github.com/grafix"
    o["elements"] = .array(elements.map { .object($0.json) })
    o["appState"] = .object(appState)
    o["files"] = .object(files)
    return o
  }

  /// Pretty, sorted JSON like Excalidraw's "Save to file". Indices are synced first.
  public func encoded() -> Data {
    var copy = self
    FractionalIndex.sync(&copy.elements)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return (try? encoder.encode(JSONValue.object(copy.root))) ?? Data()
  }
}

// MARK: - Merging external edits

extension Scene {
  /// Merges another copy of this scene (e.g. edited by an agent on disk) the way
  /// Excalidraw reconciles collaborators: per element the higher `version` wins,
  /// ties go to the lower `versionNonce`. Order follows `other` for elements it
  /// has; local-only elements keep their relative position.
  ///
  /// `syncedIDs` are ids both copies shared at the last save/load. A local element
  /// missing from `other` is kept only if it is new (not in `syncedIDs`); otherwise
  /// the other side removed it.
  public func merged(with other: Scene, syncedIDs: Set<String> = []) -> Scene {
    let mine = Dictionary(elements.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    let theirsIDs = Set(other.elements.map(\.id))
    var result: [Element] = []
    result.reserveCapacity(max(elements.count, other.elements.count))
    for theirs in other.elements {
      if let local = mine[theirs.id] {
        let keepLocal =
          local.version > theirs.version
          || (local.version == theirs.version && local.versionNonce < theirs.versionNonce)
        result.append(keepLocal ? local : theirs)
      } else {
        result.append(theirs)
      }
    }
    // Local elements the other copy has never seen (created here since the last save).
    for (i, local) in elements.enumerated()
    where !theirsIDs.contains(local.id) && !syncedIDs.contains(local.id) {
      // Insert after the closest preceding element that exists in result.
      var anchor: Int? = nil
      var k = i - 1
      while k >= 0 {
        if let at = result.firstIndex(where: { $0.id == elements[k].id }) {
          anchor = at
          break
        }
        k -= 1
      }
      result.insert(local, at: (anchor ?? -1) + 1)
    }
    var merged = other
    merged.elements = result
    var files = other.files
    for (k, v) in self.files where files[k] == nil { files[k] = v }
    merged.files = files
    return merged
  }
}
