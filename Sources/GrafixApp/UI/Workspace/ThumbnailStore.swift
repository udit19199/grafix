import AppKit
import Foundation
import GrafixCore
import GrafixRender

/// Scene thumbnails for the workspace sidebar. Rendering runs on a small
/// background queue; results are cached in memory (NSCache) and on disk under
/// ~/Library/Caches/Grafix/thumbnails/, keyed by scene id + modification date,
/// so a scene is only re-rendered when its file changed.
final class ThumbnailStore: @unchecked Sendable {
  static let shared = ThumbnailStore()

  struct Entry: @unchecked Sendable {
    let image: NSImage?
    let slides: Int
  }

  private final class Box {
    let entry: Entry
    init(_ entry: Entry) { self.entry = entry }
  }

  private let memory = NSCache<NSString, Box>()
  private let queue: OperationQueue = {
    let q = OperationQueue()
    q.name = "grafix.thumbnails"
    q.maxConcurrentOperationCount = 2
    q.qualityOfService = .utility
    return q
  }()
  private let directory: URL = {
    let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    let dir = base.appendingPathComponent("Grafix/thumbnails", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }()

  private init() { memory.countLimit = 600 }

  static func key(_ info: Workspace.SceneInfo, dark: Bool) -> String {
    let t = info.modified?.timeIntervalSince1970 ?? 0
    return "\(info.id)|\(t)|\(dark ? "d" : "l")"
  }

  func cached(_ key: String) -> Entry? { memory.object(forKey: key as NSString)?.entry }

  /// Returns the thumbnail for the file at `url`, rendering it if needed.
  func load(url: URL, key: String, dark: Bool) async -> Entry? {
    if let hit = cached(key) { return hit }
    return await withCheckedContinuation { (cont: CheckedContinuation<Entry?, Never>) in
      queue.addOperation { [self] in
        if let hit = cached(key) { return cont.resume(returning: hit) }
        let entry = fromDisk(key) ?? render(url: url, key: key, dark: dark)
        if let entry { memory.setObject(Box(entry), forKey: key as NSString) }
        cont.resume(returning: entry)
      }
    }
  }

  private func file(_ key: String, _ ext: String) -> URL {
    // FNV-1a: a stable file name for the key.
    var h: UInt64 = 0xcbf2_9ce4_8422_2325
    for b in key.utf8 { h = (h ^ UInt64(b)) &* 0x100_0000_01b3 }
    return directory.appendingPathComponent(String(h, radix: 16) + "." + ext)
  }

  private func fromDisk(_ key: String) -> Entry? {
    guard let meta = try? String(contentsOf: file(key, "meta"), encoding: .utf8), let slides = Int(meta) else {
      return nil
    }
    let png = file(key, "png")
    guard FileManager.default.fileExists(atPath: png.path) else { return Entry(image: nil, slides: slides) }
    guard let src = CGImageSourceCreateWithURL(png as CFURL, nil),
      let cg = CGImageSourceCreateImageAtIndex(src, 0, nil)
    else { return nil }
    return Entry(image: Self.nsImage(cg), slides: slides)
  }

  private func render(url: URL, key: String, dark: Bool) -> Entry? {
    guard let data = try? Data(contentsOf: url), let scene = try? Scene(data: data) else { return nil }
    let slides = scene.slideFrames.count
    let cg = SceneRenderer.image(scene, scale: 2, maxWidth: 220, padding: 10, dark: dark)
    if let cg, let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
      try? png.write(to: file(key, "png"), options: .atomic)
    }
    try? String(slides).write(to: file(key, "meta"), atomically: true, encoding: .utf8)
    return Entry(image: cg.map(Self.nsImage), slides: slides)
  }

  private static func nsImage(_ cg: CGImage) -> NSImage {
    NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width) / 2, height: CGFloat(cg.height) / 2))
  }
}
