import CoreGraphics
import GrafixCore
import GrafixRender
import Observation

/// Off-main thumbnail cache for the slides panel, keyed by frame id and a
/// content signature so only edited slides re-render (debounced ~300ms).
@MainActor @Observable
final class SlideThumbnails {
  struct Entry { var signature: Int; var image: CGImage }
  private(set) var entries: [String: Entry] = [:]
  @ObservationIgnored private var pending: Task<Void, Never>?

  func image(_ id: String) -> CGImage? { entries[id]?.image }

  /// Re-renders stale slides after `delay` of quiet.
  func refresh(_ doc: EditorDocument, delay: Duration = .milliseconds(300)) {
    pending?.cancel()
    pending = Task { [weak self, weak doc] in
      try? await Task.sleep(for: delay)
      guard !Task.isCancelled, let self, let doc else { return }
      let sigs = doc.slideSignatures()
      let dark = true
      entries = entries.filter { sigs[$0.key] != nil }
      let stale = doc.scene.slideFrames.map(\.id).filter {
        entries[$0]?.signature != sigs[$0]
      }
      guard !stale.isEmpty else { return }
      let scene = doc.scene
      for id in stale {
        let sig = sigs[id]!
        let img = await Task.detached(priority: .utility) {
          SceneRenderer.image(scene, frameID: id, scale: 2, maxWidth: 260, padding: 0, dark: dark)
        }.value
        if Task.isCancelled { return }
        entries[id] = img.map { Entry(signature: sig, image: $0) }
      }
    }
  }
}
