import AppKit
import GrafixCore
import GrafixRender
import SwiftUI

/// SwiftUI wrapper. The canvas talks to the document directly (not through
/// SwiftUI state) so drags never trigger SwiftUI re-layout.
struct CanvasRepresentable: NSViewRepresentable {
  let document: EditorDocument
  func makeNSView(context: Context) -> CanvasView { CanvasView(document: document) }
  func updateNSView(_ view: CanvasView, context: Context) {
    if view.document !== document { view.attach(document) }
  }
}

/// The drawing surface: a static scene layer (rendered off-main) plus an
/// overlay layer for selection, handles and in-progress shapes.
@MainActor
final class CanvasView: NSView {
  private(set) var document: EditorDocument
  let staticLayer = StaticSceneLayer()
  let overlayLayer = CALayer()
  let overlayCache = RenderCache()
  var pointer = PointerState()
  var textEditor: TextEditorOverlay?
  var laserTrail: [(point: CGPoint, time: TimeInterval)] = []
  var laserTimer: Timer?
  /// Element ids hidden from the static layer because the overlay draws them live.
  var liveIDs: Set<String> = [] {
    didSet { if liveIDs != oldValue { requestRender() } }
  }
  var erasing: Set<String> = []
  /// Object-snapping guide lines shown while dragging.
  var snapLines: [(CGPoint, CGPoint)] = []
  /// Image being cropped, if any.
  var cropState: CropState?
  private var trackingArea: NSTrackingArea?
  var spaceDown = false
  var hoverPoint: CGPoint?

  /// The most recently created canvas (for debug scripting).
  static weak var current: CanvasView?

  init(document: EditorDocument) {
    self.document = document
    super.init(frame: .zero)
    CanvasView.current = self
    wantsLayer = true
    layer?.masksToBounds = true
    layerContentsRedrawPolicy = .never
    staticLayer.anchorPoint = .zero
    staticLayer.position = .zero
    layer?.addSublayer(staticLayer)
    overlayLayer.anchorPoint = .zero
    overlayLayer.position = .zero
    overlayLayer.delegate = overlayDelegate
    overlayLayer.needsDisplayOnBoundsChange = true
    overlayLayer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
    layer?.addSublayer(overlayLayer)
    overlayDelegate.canvas = self
    attach(document)
    registerForDraggedTypes([.fileURL, .png, .tiff, .string])  // .string: library tile drags
  }

  required init?(coder: NSCoder) { fatalError() }

  private let overlayDelegate = OverlayDelegate()

  func attach(_ document: EditorDocument) {
    self.document.onSceneChange = nil
    self.document.onOverlayChange = nil
    self.document = document
    document.onSceneChange = { [weak self] in self?.sceneChanged() }
    document.onOverlayChange = { [weak self] in self?.viewChanged() }
    requestRender()
  }

  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { true }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    window?.makeFirstResponder(self)
    window?.acceptsMouseMovedEvents = true
    requestRender(sync: true)
  }

  override func layout() {
    super.layout()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    overlayLayer.frame = bounds
    overlayLayer.contentsScale = window?.backingScaleFactor ?? 2
    CATransaction.commit()
    document.viewSize = bounds.size
    if document.pendingFit, bounds.width > 0 {
      document.pendingFit = false
      if !document.scene.visibleElements.isEmpty { document.zoomToFitAll() }
    }
    requestRender()
  }

  override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    requestRender()
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let trackingArea { removeTrackingArea(trackingArea) }
    let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect, .cursorUpdate, .mouseEnteredAndExited], owner: self)
    addTrackingArea(area)
    trackingArea = area
  }

  // MARK: - Rendering

  func sceneChanged() {
    // While dragging/drawing, the changing elements are drawn by the overlay
    // and hidden from the static layer, so the static bitmap stays valid.
    if document.isInteracting && !liveIDs.isEmpty {
      overlayLayer.setNeedsDisplay()
      return
    }
    requestRender()
    overlayLayer.setNeedsDisplay()
  }

  func viewChanged() {
    requestRender()
    overlayLayer.setNeedsDisplay()
    updateCursor()
  }

  func requestRender(sync: Bool = false) {
    guard bounds.width > 0, bounds.height > 0 else { return }
    var hidden = liveIDs
    if let editing = textEditor?.elementID { hidden.insert(editing) }
    let request = StaticSceneLayer.Request(
      scene: document.scene, zoom: document.view.zoom, scrollX: document.view.scrollX,
      scrollY: document.view.scrollY, size: bounds.size, scale: window?.backingScaleFactor ?? 2,
      dark: true, grid: document.view.grid, hidden: hidden, dimmed: erasing)
    if sync { staticLayer.renderNow(request) } else { staticLayer.update(request) }
    overlayLayer.setNeedsDisplay()
    textEditor?.reposition()
  }

  // MARK: - Coordinates

  func scenePoint(_ event: NSEvent) -> CGPoint {
    document.sceneCoordinates(convert(event.locationInWindow, from: nil))
  }

  // MARK: - Scroll & zoom (Excalidraw: wheel pans, ctrl/cmd+wheel zooms)

  override func scrollWheel(with event: NSEvent) {
    let screen = convert(event.locationInWindow, from: nil)
    if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) {
      let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 10
      let factor = exp(delta / 200)
      document.setZoom(document.view.zoom * factor, around: screen, viewSize: bounds.size)
      return
    }
    var dx = event.scrollingDeltaX
    var dy = event.scrollingDeltaY
    if !event.hasPreciseScrollingDeltas {
      dx *= 10
      dy *= 10
    }
    if event.modifierFlags.contains(.shift), dx == 0 {
      dx = dy
      dy = 0
    }
    document.scroll(by: CGPoint(x: dx, y: dy))
    viewChanged()
  }

  override func magnify(with event: NSEvent) {
    let screen = convert(event.locationInWindow, from: nil)
    document.setZoom(document.view.zoom * (1 + event.magnification), around: screen, viewSize: bounds.size)
  }

  override func smartMagnify(with event: NSEvent) {
    let screen = convert(event.locationInWindow, from: nil)
    document.setZoom(document.view.zoom < 1.5 ? 2 : 1, around: screen, viewSize: bounds.size)
  }

  // MARK: - Keyboard

  override func keyDown(with event: NSEvent) {
    if handleKey(event) { return }
    super.keyDown(with: event)
  }

  override func keyUp(with event: NSEvent) {
    if event.keyCode == 49 {  // space
      spaceDown = false
      updateCursor()
    }
    super.keyUp(with: event)
  }

  override func flagsChanged(with event: NSEvent) {
    super.flagsChanged(with: event)
    overlayLayer.setNeedsDisplay()
  }

  /// Plain-key shortcuts (Command shortcuts live in the menu bar).
  func handleKey(_ event: NSEvent) -> Bool {
    let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
    let doc = document
    switch event.keyCode {
    case 53:  // escape
      if cropState != nil {
        endCrop()
      } else if pointer.multiPointElement != nil {
        finishMultiPoint()
      } else if doc.editingGroupID != nil {
        doc.editingGroupID = nil
        doc.selection = []
      } else if doc.view.tool != .selection {
        doc.setTool(.selection)
      } else {
        doc.selection = []
      }
      return true
    case 51, 117:  // delete, forward delete
      if flags.contains(.command) { return false }
      doc.deleteSelected()
      return true
    case 36, 76:  // return
      if cropState != nil {
        endCrop()
        return true
      }
      if let e = doc.singleSelection, e.type == .image {
        beginCrop(e.id)
        return true
      }
      if pointer.multiPointElement != nil {
        finishMultiPoint()
        return true
      }
      if let e = doc.singleSelection {
        if e.isText { beginTextEditing(e.id) } else if e.canHaveLabel { beginLabelEditing(container: e.id) }
        return true
      }
      return false
    case 49:  // space: hold to pan
      if !event.isARepeat {
        spaceDown = true
        updateCursor()
      }
      return true
    case 123, 124, 125, 126:  // arrows: nudge
      guard doc.hasSelection, !flags.contains(.command) else { return false }
      let step: CGFloat = flags.contains(.shift) ? 5 : 1
      let delta: CGPoint =
        switch event.keyCode {
        case 123: CGPoint(x: -step, y: 0)
        case 124: CGPoint(x: step, y: 0)
        case 125: CGPoint(x: 0, y: step)
        default: CGPoint(x: 0, y: -step)
        }
      let ids = doc.selection
      doc.commit(coalesce: "nudge") { $0.move(ids, by: delta) }
      return true
    default:
      break
    }
    guard !flags.contains(.command), !flags.contains(.control), let chars = event.charactersIgnoringModifiers?.lowercased(),
      let ch = chars.first
    else { return false }
    if flags.contains(.shift) {
      switch ch {
      case "h": doc.flipSelected(horizontal: true); return true
      case "v": doc.flipSelected(horizontal: false); return true
      case "1", "!": doc.zoomToFitAll(); return true
      case "2", "@": doc.zoomToSelection(); return true
      case "/", "?": NotificationCenter.default.post(name: .grafixShowHelp, object: nil); return true
      default: break
      }
    }
    if flags.contains(.option), ch == "/" || ch == "÷" {
      doc.view.showStats.toggle()
      return true
    }
    if flags.contains(.option), ch == "s" || ch == "ß" {
      doc.view.snapToObjects.toggle()
      return true
    }
    if flags.contains(.option) { return false }
    if ch == "q" {
      doc.view.toolLocked.toggle()
      return true
    }
    if ch == "?" {
      NotificationCenter.default.post(name: .grafixShowHelp, object: nil)
      return true
    }
    if let tool = Tool.allCases.first(where: { $0.key == ch || $0.numberKey == ch }), !flags.contains(.shift) {
      if tool == .image {
        doc.insertImageFromPanel(at: doc.sceneCoordinates(CGPoint(x: bounds.midX, y: bounds.midY)))
        return true
      }
      doc.setTool(tool)
      return true
    }
    return false
  }

  // MARK: - Cursor

  override func cursorUpdate(with event: NSEvent) { updateCursor() }

  func updateCursor() {
    let cursor: NSCursor
    if spaceDown || document.view.tool == .hand {
      cursor = pointer.panning ? .closedHand : .openHand
    } else {
      switch document.view.tool {
      case .selection, .lasso:
        cursor = hoverCursor ?? .arrow
      case .text:
        cursor = .iBeam
      case .eraser, .laser:
        cursor = .crosshair
      default:
        cursor = .crosshair
      }
    }
    cursor.set()
  }

  var hoverCursor: NSCursor?
}

/// Draws the overlay layer by calling back into the canvas.
final class OverlayDelegate: NSObject, CALayerDelegate, @unchecked Sendable {
  nonisolated(unsafe) weak var canvas: CanvasView?
  func draw(_ layer: CALayer, in ctx: CGContext) {
    // CoreAnimation draws layer content on the main thread.
    nonisolated(unsafe) let context = ctx
    nonisolated(unsafe) let target = canvas
    MainActor.assumeIsolated {
      target?.drawOverlay(in: context)
    }
  }
  func action(for layer: CALayer, forKey event: String) -> CAAction? { NSNull() }
}

extension Notification.Name {
  static let grafixShowHelp = Notification.Name("grafix.showHelp")
}
