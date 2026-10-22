import Darwin
import Foundation

/// Local storage for collections and scenes. Plain files, so agents and other
/// tools can read them directly:
///
///     ~/Documents/Grafix/                 workspace root
///       <Collection>/                     a collection is a folder
///         <Scene>.excalidraw              a scene is an Excalidraw file
///       .grafix/editor.json               what the app has open (for agents)
///       .grafix/lock                      flock held during read-modify-write
///
/// Scene ids are "<Collection>/<Scene>" (no extension). They change if a scene
/// is renamed or moved; that keeps them human readable for agents.
public struct Workspace: Sendable {
  public let root: URL

  public init(root: URL = Workspace.defaultRoot) {
    self.root = root.standardizedFileURL
  }

  public static var defaultRoot: URL {
    if let custom = ProcessInfo.processInfo.environment["GRAFIX_ROOT"], !custom.isEmpty {
      return URL(fileURLWithPath: NSString(string: custom).expandingTildeInPath, isDirectory: true)
    }
    return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Grafix", isDirectory: true)
  }

  public static let sceneExtension = "excalidraw"
  public static let defaultCollection = "Personal"

  // MARK: - Collections

  public struct Collection: Equatable, Sendable, Identifiable {
    public var id: String { name }
    public var name: String
    public var sceneCount: Int
    public var modified: Date?
  }

  public func listCollections() throws -> [Collection] {
    try ensureRoot()
    let fm = FileManager.default
    let dirs = try fm.contentsOfDirectory(
      at: root, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
      options: .skipsHiddenFiles)
    return try dirs.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
      .filter { $0.lastPathComponent != "Recovery" }
      .map { url in
        let scenes = try listScenes(in: url.lastPathComponent)
        return Collection(
          name: url.lastPathComponent, sceneCount: scenes.count,
          modified: scenes.compactMap(\.modified).max())
      }
      .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }

  @discardableResult
  public func createCollection(_ name: String) throws -> Collection {
    let url = try collectionURL(name)
    if FileManager.default.fileExists(atPath: url.path) { throw WorkspaceError.alreadyExists(name) }
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return Collection(name: name, sceneCount: 0, modified: Date())
  }

  public func renameCollection(_ name: String, to newName: String) throws {
    try withLock { try _renameCollection(name, to: newName) }
  }

  func _renameCollection(_ name: String, to newName: String) throws {
    let from = try existingCollectionURL(name)
    let to = try collectionURL(newName)
    if FileManager.default.fileExists(atPath: to.path) { throw WorkspaceError.alreadyExists(newName) }
    try FileManager.default.moveItem(at: from, to: to)
  }

  /// Moves the collection folder to the macOS Trash (recoverable).
  public func trashCollection(_ name: String) throws {
    try FileManager.default.trashItem(at: try existingCollectionURL(name), resultingItemURL: nil)
  }

  // MARK: - Scenes

  public struct SceneInfo: Equatable, Sendable, Identifiable {
    /// "<Collection>/<Scene>"
    public var id: String
    public var collection: String
    public var name: String
    public var url: URL
    public var modified: Date?
  }

  public func listScenes(in collection: String) throws -> [SceneInfo] {
    let dir = try existingCollectionURL(collection)
    let files = try FileManager.default.contentsOfDirectory(
      at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
      options: .skipsHiddenFiles)
    return files.filter { $0.pathExtension == Workspace.sceneExtension }
      .map { url in
        let name = url.deletingPathExtension().lastPathComponent
        return SceneInfo(
          id: "\(collection)/\(name)", collection: collection, name: name, url: url,
          modified: try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
      }
      .sorted { ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) }
  }

  public func allScenes() throws -> [SceneInfo] {
    try listCollections().flatMap { try listScenes(in: $0.name) }
      .sorted { ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) }
  }

  public func info(_ sceneID: String) throws -> SceneInfo {
    let (collection, name) = try split(sceneID)
    let url = try sceneURL(collection: collection, name: name)
    guard FileManager.default.fileExists(atPath: url.path) else { throw WorkspaceError.sceneNotFound(sceneID) }
    return SceneInfo(
      id: sceneID, collection: collection, name: name, url: url,
      modified: try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
  }

  /// Creates a scene file. Picks a unique name ("Untitled 2") if `unique` is set.
  @discardableResult
  public func createScene(
    in collection: String, name: String, scene: Scene = Scene(), unique: Bool = false
  ) throws -> SceneInfo {
    try ensureCollection(collection)
    var finalName = name
    var url = try sceneURL(collection: collection, name: finalName)
    var n = 2
    while FileManager.default.fileExists(atPath: url.path) {
      guard unique else { throw WorkspaceError.alreadyExists("\(collection)/\(name)") }
      finalName = "\(name) \(n)"
      url = try sceneURL(collection: collection, name: finalName)
      n += 1
    }
    try write(scene, to: url)
    return try info("\(collection)/\(finalName)")
  }

  public func load(_ sceneID: String) throws -> Scene {
    let info = try info(sceneID)
    return try Scene(data: Data(contentsOf: info.url))
  }

  /// Writes a scene atomically.
  public func save(_ scene: Scene, to sceneID: String) throws {
    let (collection, name) = try split(sceneID)
    try ensureCollection(collection)
    try write(scene, to: try sceneURL(collection: collection, name: name))
  }

  /// Load, change and save under the workspace lock, so concurrent writers
  /// (the app and agents) never lose each other's edits. Returns the new scene.
  @discardableResult
  public func modify<T>(_ sceneID: String, _ change: (inout Scene) throws -> T) throws -> (Scene, T) {
    try withLock {
      var scene = try load(sceneID)
      let result = try change(&scene)
      try save(scene, to: sceneID)
      return (scene, result)
    }
  }

  public func renameScene(_ sceneID: String, to newName: String) throws -> SceneInfo {
    try withLock { try _renameScene(sceneID, to: newName) }
  }

  func _renameScene(_ sceneID: String, to newName: String) throws -> SceneInfo {
    let old = try info(sceneID)
    let target = try sceneURL(collection: old.collection, name: newName)
    if FileManager.default.fileExists(atPath: target.path) { throw WorkspaceError.alreadyExists(newName) }
    try FileManager.default.moveItem(at: old.url, to: target)
    return try info("\(old.collection)/\(newName)")
  }

  public func moveScene(_ sceneID: String, toCollection collection: String) throws -> SceneInfo {
    try withLock { try _moveScene(sceneID, toCollection: collection) }
  }

  func _moveScene(_ sceneID: String, toCollection collection: String) throws -> SceneInfo {
    let old = try info(sceneID)
    try ensureCollection(collection)
    let target = try sceneURL(collection: collection, name: old.name)
    if FileManager.default.fileExists(atPath: target.path) { throw WorkspaceError.alreadyExists(old.name) }
    try FileManager.default.moveItem(at: old.url, to: target)
    return try info("\(collection)/\(old.name)")
  }

  public func duplicateScene(_ sceneID: String) throws -> SceneInfo {
    let old = try info(sceneID)
    return try createScene(in: old.collection, name: old.name + " copy", scene: load(sceneID), unique: true)
  }

  /// Moves the scene file to the macOS Trash (recoverable).
  public func trashScene(_ sceneID: String) throws {
    try FileManager.default.trashItem(at: try info(sceneID).url, resultingItemURL: nil)
  }

  // MARK: - Editor state shared with agents

  /// What the app currently shows, so agents can act on "the open scene" or
  /// "the selection". Written by the app, read by grafix-mcp.
  public struct EditorState: Codable, Equatable, Sendable {
    public var openSceneID: String?
    public var selectedElementIDs: [String]
    /// Visible scene rectangle [x, y, width, height].
    public var viewport: [Double]?
    public var updated: Date
    public init(openSceneID: String?, selectedElementIDs: [String], viewport: [Double]?) {
      self.openSceneID = openSceneID
      self.selectedElementIDs = selectedElementIDs
      self.viewport = viewport
      self.updated = Date()
    }
  }

  public var editorStateURL: URL { root.appendingPathComponent(".grafix/editor.json") }

  public func writeEditorState(_ state: EditorState) {
    try? FileManager.default.createDirectory(
      at: editorStateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    try? encoder.encode(state).write(to: editorStateURL, options: .atomic)
  }

  public func readEditorState() -> EditorState? {
    guard let data = try? Data(contentsOf: editorStateURL) else { return nil }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try? decoder.decode(EditorState.self, from: data)
  }

  // MARK: - Locking

  /// Runs `body` while holding an exclusive flock on `.grafix/lock`.
  /// Reentrant on the same thread (nested calls don't re-lock).
  public func withLock<T>(_ body: () throws -> T) throws -> T {
    let depthKey = "grafix.lock.depth"
    let depth = Thread.current.threadDictionary[depthKey] as? Int ?? 0
    if depth > 0 {
      Thread.current.threadDictionary[depthKey] = depth + 1
      defer { Thread.current.threadDictionary[depthKey] = depth }
      return try body()
    }
    Thread.current.threadDictionary[depthKey] = 1
    defer { Thread.current.threadDictionary[depthKey] = 0 }
    let lockURL = root.appendingPathComponent(".grafix/lock")
    try FileManager.default.createDirectory(
      at: lockURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let fd = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
    guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    defer { close(fd) }
    guard flock(fd, LOCK_EX) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    defer { flock(fd, LOCK_UN) }
    return try body()
  }

  // MARK: - Paths

  public func split(_ sceneID: String) throws -> (String, String) {
    var id = sceneID
    if id.hasSuffix(".\(Workspace.sceneExtension)") { id.removeLast(Workspace.sceneExtension.count + 1) }
    let parts = id.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    guard parts.count == 2 else { throw WorkspaceError.invalidID(sceneID) }
    return (parts[0], parts[1])
  }

  func validate(_ component: String) throws {
    guard !component.isEmpty, component != ".", component != "..", !component.hasPrefix("."),
      !component.contains("/"), !component.contains("\\"), !component.contains("\0"),
      component.count <= 200
    else { throw WorkspaceError.invalidName(component) }
  }

  func collectionURL(_ name: String) throws -> URL {
    try validate(name)
    return root.appendingPathComponent(name, isDirectory: true)
  }

  func existingCollectionURL(_ name: String) throws -> URL {
    let url = try collectionURL(name)
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
      throw WorkspaceError.notFound(name)
    }
    return url
  }

  func sceneURL(collection: String, name: String) throws -> URL {
    try validate(name)
    return try collectionURL(collection).appendingPathComponent("\(name).\(Workspace.sceneExtension)")
  }

  func ensureRoot() throws {
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }

  func ensureCollection(_ name: String) throws {
    try FileManager.default.createDirectory(at: try collectionURL(name), withIntermediateDirectories: true)
  }

  func write(_ scene: Scene, to url: URL) throws {
    let data = scene.encoded()
    // Never replace a drawing with an empty file.
    guard !data.isEmpty else { throw SceneError.notExcalidraw }
    try data.write(to: url, options: .atomic)
  }
}

public enum WorkspaceError: Error, LocalizedError, Equatable {
  case invalidName(String), invalidID(String), notFound(String), sceneNotFound(String), alreadyExists(String)
  public var errorDescription: String? {
    switch self {
    case .invalidName(let n): "Invalid name '\(n)'. Names cannot be empty, start with '.', or contain '/'."
    case .invalidID(let id): "Invalid scene id '\(id)'. Scene ids look like 'Collection/Scene name'."
    case .notFound(let n): "Collection '\(n)' was not found. Call list_collections to see names."
    case .sceneNotFound(let id): "No scene '\(id)'. Call list_scenes to see ids (they look like 'Collection/Scene')."
    case .alreadyExists(let n): "'\(n)' already exists."
    }
  }
}
