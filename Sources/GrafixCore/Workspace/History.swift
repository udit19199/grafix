import Foundation

/// Scene version history (Excalidraw+'s "History"): periodic snapshots under
/// `<root>/.grafix/history/<Collection>/<Scene>/<epoch-ms>.excalidraw`.
extension Workspace {
  public struct Revision: Identifiable, Equatable, Sendable {
    public var id: String { url.lastPathComponent }
    public var url: URL
    public var date: Date
  }

  public static let maxRevisions = 60

  func historyDirectory(_ sceneID: String) throws -> URL {
    let (collection, name) = try split(sceneID)
    return root.appendingPathComponent(".grafix/history", isDirectory: true)
      .appendingPathComponent(collection, isDirectory: true)
      .appendingPathComponent(name, isDirectory: true)
  }

  /// Saves a snapshot unless the newest one is identical. Keeps the newest `maxRevisions`.
  @discardableResult
  public func saveRevision(_ scene: Scene, of sceneID: String) throws -> Revision? {
    let dir = try historyDirectory(sceneID)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let data = scene.encoded()
    if let latest = try revisions(of: sceneID).first, (try? Data(contentsOf: latest.url)) == data { return nil }
    let ms = Int64(Date().timeIntervalSince1970 * 1000)
    let url = dir.appendingPathComponent("\(ms).excalidraw")
    try data.write(to: url, options: .atomic)
    for old in try revisions(of: sceneID).dropFirst(Workspace.maxRevisions) {
      try? FileManager.default.removeItem(at: old.url)
    }
    return Revision(url: url, date: Date(timeIntervalSince1970: Double(ms) / 1000))
  }

  /// Newest first.
  public func revisions(of sceneID: String) throws -> [Revision] {
    let dir = try historyDirectory(sceneID)
    guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
    return files.compactMap { url -> Revision? in
      guard url.pathExtension == Workspace.sceneExtension, let ms = Double(url.deletingPathExtension().lastPathComponent) else { return nil }
      return Revision(url: url, date: Date(timeIntervalSince1970: ms / 1000))
    }
    .sorted { $0.date > $1.date }
  }

  public func loadRevision(_ revision: Revision) throws -> Scene {
    try Scene(data: Data(contentsOf: revision.url))
  }
}
