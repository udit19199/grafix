import AppKit
import GrafixCore
import GrafixRender
import Observation

/// State and slide rendering for a running presentation. Renders each slide at
/// screen pixel size off-main and keeps the neighbours pre-rendered.
@MainActor @Observable
final class PresentationController {
  let scene: Scene
  let slides: [Slide]
  let dark: Bool
  /// Slide whose image is on screen (changes after the target is rendered).
  private(set) var shown: Int
  private(set) var target: Int
  private(set) var images: [Int: CGImage] = [:]
  var laser = false
  var showNotes = false
  var trail: [(point: CGPoint, time: TimeInterval)] = []
  @ObservationIgnored private var renderSize = CGSize.zero
  @ObservationIgnored private var scale: CGFloat = 2
  @ObservationIgnored private var inflight: Set<Int> = []
  @ObservationIgnored var onChange: ((Int) -> Void)?

  init(scene: Scene, dark: Bool, start: Int) {
    self.scene = scene
    self.slides = scene.slides
    self.dark = dark
    let i = max(0, min(start, max(0, slides.count - 1)))
    shown = i
    target = i
  }

  var count: Int { slides.count }
  var current: Slide? { slides.indices.contains(shown) ? slides[shown] : nil }

  /// Fit scale (points per scene unit) of slide `i` in the current view.
  func fit(_ i: Int, in size: CGSize) -> CGFloat {
    let r = slides[i].bounds
    guard r.width > 0, r.height > 0 else { return 1 }
    return min(size.width / r.width, size.height / r.height)
  }

  func configure(size: CGSize, backing: CGFloat) {
    guard size.width > 0, size != renderSize else { return }
    renderSize = size
    scale = backing
    images = [:]
    inflight = []
    guard !slides.isEmpty else { return }
    ensure(target) { [weak self] in
      guard let self else { return }
      shown = target
      for n in [target + 1, target - 1] { ensure(n) }
    }
  }

  func go(to i: Int) {
    guard !slides.isEmpty else { return }
    let n = max(0, min(slides.count - 1, i))
    guard n != target else { return }
    target = n
    onChange?(n)
    ensure(n) { [weak self] in
      guard let self, target == n else { return }
      shown = n
      for k in [n + 1, n - 1, n + 2] { ensure(k) }
      images = images.filter { abs($0.key - n) <= 2 }
    }
  }

  func next() { go(to: target + 1) }
  func previous() { go(to: target - 1) }

  /// Renders slide `i` (if needed) and calls `done` on the main actor when ready.
  private func ensure(_ i: Int, done: (@MainActor () -> Void)? = nil) {
    guard slides.indices.contains(i), renderSize.width > 0 else { return }
    if images[i] != nil { done?(); return }
    guard !inflight.contains(i) else {
      // Already rendering: poll until the image lands.
      if let done { Task { @MainActor in
        for _ in 0..<100 where self.images[i] == nil { try? await Task.sleep(for: .milliseconds(30)) }
        done()
      } }
      return
    }
    inflight.insert(i)
    let scene = scene, id = slides[i].frameID, dark = dark
    let s = fit(i, in: renderSize) * scale
    let size = renderSize
    Task {
      let img = await Task.detached(priority: .userInitiated) {
        SceneRenderer.image(scene, frameID: id, scale: s, maxWidth: 6000, maxHeight: 6000, padding: 0, dark: dark)
      }.value
      inflight.remove(i)
      guard size == renderSize else { return }
      images[i] = img
      done?()
    }
  }

  func addTrailPoint(_ p: CGPoint) {
    let now = ProcessInfo.processInfo.systemUptime
    trail.append((p, now))
    trail.removeAll { now - $0.time > 0.7 }
  }
}
