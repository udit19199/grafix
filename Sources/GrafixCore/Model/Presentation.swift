import CoreGraphics
import Foundation

/// Presentations, compatible with Excalidraw+: one frame = one slide.
///
/// Excalidraw+ stores slide order and notes on the frame:
///     "customData": { "slidesOrder": 0, "presenterNotes": "- point" }
/// `slidesOrder` is 0-based. Frames without it come after ordered frames, in
/// z-order. New slides default to 854x480 (16:9), placed 350px to the right of
/// the previous slide; content should stay inside a 64px safe area.
public struct Slide: Equatable, Sendable {
  public var frameID: String
  public var name: String
  public var number: Int
  public var bounds: CGRect
  public var notes: String?
  public var safeArea: CGRect { bounds.insetBy(dx: Presentation.safeInset, dy: Presentation.safeInset) }
}

public enum Presentation {
  public static let defaultSize = CGSize(width: 854, height: 480)
  public static let spacing: CGFloat = 350
  public static let safeInset: CGFloat = 64
  public static let origin = CGPoint(x: 80, y: 80)
}

extension Scene {
  /// Frames in presentation order.
  public var slideFrames: [Element] {
    let frames = elements.enumerated().filter { $0.element.isFrame && !$0.element.isDeleted }
    return frames.sorted { a, b in
      switch (a.element.slidesOrder, b.element.slidesOrder) {
      case let (x?, y?): x == y ? a.offset < b.offset : x < y
      case (_?, nil): true
      case (nil, _?): false
      case (nil, nil): a.offset < b.offset
      }
    }.map(\.element)
  }

  public var slides: [Slide] {
    slideFrames.enumerated().map { i, f in
      Slide(frameID: f.id, name: f.name ?? "", number: i + 1, bounds: f.rect, notes: f.presenterNotes)
    }
  }

  /// Writes 0..n-1 `slidesOrder` for the given frame order.
  public mutating func setSlideOrder(_ frameIDs: [String]) {
    for (n, id) in frameIDs.enumerated() {
      update(id) { $0.slidesOrder = Double(n) }
    }
  }

  /// Appends a slide frame after the last slide. Returns its id.
  @discardableResult
  public mutating func addSlide(name: String? = nil, size: CGSize? = nil, notes: String? = nil) -> String {
    let existing = slideFrames
    let last = existing.last
    let size = size ?? last.map { CGSize(width: $0.width, height: $0.height) } ?? Presentation.defaultSize
    let origin =
      last.map { CGPoint(x: $0.x + $0.width + Presentation.spacing, y: $0.y) } ?? defaultSlideOrigin()
    var frame = Element.make(.frame, x: origin.x, y: origin.y, width: size.width, height: size.height)
    frame.strokeColor = "#1e1e1e"  // what Excalidraw+'s create_slide writes
    frame.roughness = 1
    frame.name = name
    frame.customData = ["slidesOrder": .number(Double(existing.count))]
    if let notes { frame.presenterNotes = notes }
    // Frames go below everything so their children draw on top.
    elements.insert(frame, at: 0)
    FractionalIndex.sync(&elements)
    return frame.id
  }

  /// Where the first slide goes: the top-left default, or below existing content.
  func defaultSlideOrigin() -> CGPoint {
    let visible = visibleElements
    guard !visible.isEmpty else { return Presentation.origin }
    let all = visible.map(\.bounds).reduce(visible[0].bounds) { $0.union($1) }
    return CGPoint(x: all.minX, y: all.maxY + 200)
  }

  /// Moves a slide to a 1-based position.
  public mutating func moveSlide(_ frameID: String, to number: Int) {
    var order = slideFrames.map(\.id)
    guard let from = order.firstIndex(of: frameID) else { return }
    order.remove(at: from)
    order.insert(frameID, at: max(0, min(order.count, number - 1)))
    setSlideOrder(order)
  }
}
