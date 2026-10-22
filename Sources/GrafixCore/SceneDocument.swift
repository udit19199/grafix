import CryptoKit
import Darwin
import Foundation

public enum JSONValue: Codable, Equatable, Sendable {
  case object([String: JSONValue])
  case array([JSONValue])
  case string(String)
  case number(Double)
  case bool(Bool)
  case null

  public init(from decoder: Decoder) throws {
    let value = try decoder.singleValueContainer()
    if value.decodeNil() {
      self = .null
    } else if let bool = try? value.decode(Bool.self) {
      self = .bool(bool)
    } else if let number = try? value.decode(Double.self) {
      self = .number(number)
    } else if let string = try? value.decode(String.self) {
      self = .string(string)
    } else if let array = try? value.decode([JSONValue].self) {
      self = .array(array)
    } else {
      self = .object(try value.decode([String: JSONValue].self))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var value = encoder.singleValueContainer()
    switch self {
    case .object(let object): try value.encode(object)
    case .array(let array): try value.encode(array)
    case .string(let string): try value.encode(string)
    case .number(let number): try value.encode(number)
    case .bool(let bool): try value.encode(bool)
    case .null: try value.encodeNil()
    }
  }

  public var objectValue: [String: JSONValue]? {
    if case .object(let value) = self { value } else { nil }
  }
  public var arrayValue: [JSONValue]? { if case .array(let value) = self { value } else { nil } }
  public var stringValue: String? { if case .string(let value) = self { value } else { nil } }
  public var doubleValue: Double? { if case .number(let value) = self { value } else { nil } }
  public var boolValue: Bool? { if case .bool(let value) = self { value } else { nil } }
}

public struct SceneDocument: Sendable {
  public var root: [String: JSONValue]
  fileprivate var originalData: Data?

  public init() {
    root = [
      "type": .string("excalidraw"), "version": .number(2), "source": .string("grafix"),
      "elements": .array([]), "appState": .object([:]), "files": .object([:]),
    ]
  }

  public init(data: Data) throws {
    root = try JSONDecoder().decode([String: JSONValue].self, from: data)
    guard root["type"]?.stringValue == "excalidraw",
      let elements = root["elements"]?.arrayValue,
      elements.allSatisfy({ $0.objectValue != nil })
    else {
      throw SceneStoreError.invalidDocument
    }
    originalData = data
  }

  public func copyForNewFile() -> SceneDocument {
    var copy = self
    copy.originalData = nil
    return copy
  }

  public func encoded() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(root)
  }

  public var revision: String {
    // Encoding only fails for non-JSON numbers introduced by a caller.
    guard let data = try? encoded() else { return "invalid" }
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  public var elements: [[String: JSONValue]] {
    get { root["elements"]?.arrayValue?.compactMap(\.objectValue) ?? [] }
    set { root["elements"] = .array(newValue.map(JSONValue.object)) }
  }
}

public enum SceneStoreError: Error, LocalizedError {
  case invalidName, unsafePath, changedOnDisk, invalidDocument
  public var errorDescription: String? {
    switch self {
    case .invalidDocument:
      "This is not a valid Excalidraw scene: expected an elements array of objects."
    case .invalidName: "Use a drawing name, not a path."
    case .unsafePath: "The drawing location points outside the collection."
    case .changedOnDisk:
      "This drawing changed on disk. Reopen it before saving to avoid overwriting changes."
    }
  }
}

public struct SceneStore: Sendable {
  public let directory: URL
  public init(directory: URL) { self.directory = directory.standardizedFileURL }

  public func list() throws -> [URL] {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: .skipsHiddenFiles
    )
    .filter {
      $0.pathExtension == "excalidraw"
        && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }
    .sorted {
      $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
    }
  }

  public func load(name: String) throws -> SceneDocument {
    try SceneDocument(data: Data(contentsOf: location(name)))
  }

  @discardableResult
  public func save(_ document: SceneDocument, name: String) throws -> SceneDocument {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let target = try location(name)
    // ponytail: one collection lock; use per-document locks if concurrent save throughput matters.
    let lock = open(
      directory.appendingPathComponent(".grafix.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW,
      S_IRUSR | S_IWUSR)
    guard lock >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    defer { close(lock) }
    guard flock(lock, LOCK_EX) == 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    defer { flock(lock, LOCK_UN) }
    let current =
      try FileManager.default.fileExists(atPath: target.path) ? Data(contentsOf: target) : nil
    guard current == document.originalData else { throw SceneStoreError.changedOnDisk }
    let data = try document.encoded()
    try data.write(to: target, options: .atomic)
    var saved = document
    saved.originalData = data
    return saved
  }

  private func location(_ name: String) throws -> URL {
    guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\\"),
      !name.contains("\0")
    else { throw SceneStoreError.invalidName }
    let filename = name.hasSuffix(".excalidraw") ? name : name + ".excalidraw"
    let target = directory.appendingPathComponent(filename)
    if (try? FileManager.default.attributesOfItem(atPath: target.path)[.type]) as? FileAttributeType
      == .typeSymbolicLink
    {
      throw SceneStoreError.unsafePath
    }
    guard
      target.resolvingSymlinksInPath().deletingLastPathComponent()
        == directory.resolvingSymlinksInPath()
    else { throw SceneStoreError.unsafePath }
    return target
  }
}
