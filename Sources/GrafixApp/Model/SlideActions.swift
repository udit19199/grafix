import CoreGraphics
import Foundation
import GrafixCore

/// Slide operations (Excalidraw+ presentation sidebar). One frame = one slide;
/// order lives in frame customData.slidesOrder.
extension EditorDocument {
  /// Appends a slide and zooms to it. Returns its frame id.
  @discardableResult
  func addSlide(name: String? = nil) -> String {
    var id = ""
    commit { id = $0.addSlide(name: name ?? "Slide \($0.slideFrames.count + 1)") }
    focusSlide(id)
    return id
  }

  /// Selects the frame and zooms the canvas to it.
  func focusSlide(_ id: String) {
    guard let f = scene.element(id) else { return }
    select([id])
    zoom(toFit: f.rect, viewSize: viewSize, padding: 80, maxZoom: 2)
  }

  func renameSlide(_ id: String, to name: String) {
    guard scene.element(id)?.name != name else { return }
    commit { s in s.update(id) { $0.name = name.isEmpty ? nil : name } }
  }

  /// Merges into customData, keeping slidesOrder.
  func setSlideNotes(_ id: String, _ notes: String) {
    guard (scene.element(id)?.presenterNotes ?? "") != notes else { return }
    commit { s in s.update(id) { $0.presenterNotes = notes.isEmpty ? nil : notes } }
  }

  func reorderSlides(_ ids: [String]) {
    commit { $0.setSlideOrder(ids) }
  }

  func moveSlide(_ id: String, by delta: Int) {
    var order = scene.slideFrames.map(\.id)
    guard let i = order.firstIndex(of: id) else { return }
    let j = max(0, min(order.count - 1, i + delta))
    guard i != j else { return }
    order.swapAt(i, j)
    reorderSlides(order)
  }

  /// Copies the frame and its children, placed after the last slide.
  @discardableResult
  func duplicateSlide(_ id: String) -> String? {
    guard let frame = scene.element(id), frame.isFrame else { return nil }
    var newID: String?
    commit { s in
      let last = s.slideFrames.last ?? frame
      let kids = Set(s.elements.filter { $0.frameId == id && !$0.isDeleted }.map(\.id))
      let off = CGPoint(
        x: last.x + last.width + Presentation.spacing - frame.x, y: last.y - frame.y)
      let created = s.duplicate(kids.union([id]), offset: off)
      newID = created.first { s.element($0)?.isFrame == true }
      if let n = newID {
        s.update(n) { $0.name = (frame.name ?? "Slide") + " copy" }
        s.setSlideOrder(s.slideFrames.map(\.id).filter { $0 != n } + [n])
      }
    }
    if let newID { focusSlide(newID) }
    return newID
  }

  func deleteSlide(_ id: String) {
    commit { $0.delete([id]) }
    selection = []
    let order = scene.slideFrames.map(\.id)
    commit { $0.setSlideOrder(order) }
  }

  /// Cheap per-slide content signatures (one pass over the scene): a slide's
  /// signature changes when its frame or any child element changes.
  func slideSignatures() -> [String: Int] {
    let ids = Set(scene.slideFrames.map(\.id))
    var hashers: [String: Hasher] = [:]
    for e in scene.elements {
      let owner = ids.contains(e.id) ? e.id : e.frameId
      guard let owner, ids.contains(owner) else { continue }
      hashers[owner, default: Hasher()].combine(e.id)
      hashers[owner]!.combine(e.version)
      hashers[owner]!.combine(e.isDeleted)
    }
    var out: [String: Int] = [:]
    for (k, var h) in hashers {
      h.combine(scene.viewBackgroundColor)
      h.combine(true)
      out[k] = h.finalize()
    }
    return out
  }
}
