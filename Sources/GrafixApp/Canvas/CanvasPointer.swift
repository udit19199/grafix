import AppKit
import GrafixCore
import GrafixRender

/// Transform handles (Excalidraw transformHandles.ts).
enum Handle: String { case nw, n, ne, e, se, s, sw, w, rotation }

/// Everything about the current pointer gesture.
struct PointerState {
  enum Mode: Equatable {
    case idle, panning, boxSelect, lasso, moving, resizing(Handle), rotating, drawingShape, drawingLinear,
      drawingFreedraw, editingPoint(Int), erasing, laser
  }
  var mode: Mode = .idle
  var origin = CGPoint.zero
  var originScreen = CGPoint.zero
  var last = CGPoint.zero
  var didDrag = false
  var startSelection: Set<String> = []
  var draftID: String?
  /// Click-click line/arrow in progress.
  var multiPointElement: String?
  var originals: [String: Element] = [:]
  var startBounds = CGRect.zero
  var box: CGRect?
  var lassoPoints: [CGPoint] = []
  var panning = false
  var bindTarget: String?
  var shift = false
  var alt = false
  var hitOnDown: String?
  var startAngle: CGFloat = 0
}

extension CanvasView {
  var zoom: CGFloat { document.view.zoom }
  /// Hit tolerance in scene units (Excalidraw: 10px / zoom for mouse).
  var hitThreshold: CGFloat { 10 / zoom }

  // MARK: - Hit testing

  /// Topmost element under the point, respecting groups and locks.
  func hitElement(at p: CGPoint, includeLocked: Bool = false) -> Element? {
    let scene = document.scene
    for e in scene.elements.reversed() where !e.isDeleted {
      if e.locked && !includeLocked { continue }
      if e.isFrame {
        // Frames are picked by their name label or border, not their inside.
        let nameBox = CGRect(x: e.x, y: e.y - 20 / zoom, width: min(e.width, 200 / zoom), height: 20 / zoom)
        if nameBox.contains(p) { return e }
        let outer = e.rect.insetBy(dx: -hitThreshold, dy: -hitThreshold)
        let inner = e.rect.insetBy(dx: hitThreshold, dy: hitThreshold)
        if outer.contains(p) && !inner.contains(p) { return e }
        continue
      }
      if e.isText, let c = e.containerId {
        // Test the label first; only then look up its container.
        guard e.hitTest(p, threshold: 0) else { continue }
        if let container = scene.element(c), !container.isDeleted { return container }
        continue
      }
      if e.hitTest(p, threshold: hitThreshold) { return e }
    }
    return nil
  }

  /// Bindable shape under the point for arrow ends.
  func bindableElement(at p: CGPoint, excluding: Set<String>) -> Element? {
    for e in document.scene.elements.reversed() where !e.isDeleted && e.isBindable && !excluding.contains(e.id) {
      if e.isText && e.containerId != nil { continue }
      if e.containsExpanded(p, gap: 15 / zoom) { return e }
    }
    return nil
  }

  /// The ids a click on `e` selects: its outermost group, unless editing inside it.
  func selectionUnit(for e: Element) -> Set<String> {
    let scene = document.scene
    if let editing = document.editingGroupID, e.groupIds.contains(editing) {
      // Select the next group level inside the edited group, or the element.
      if let idx = e.groupIds.firstIndex(of: editing), idx > 0 {
        let inner = e.groupIds[idx - 1]
        return Set(scene.elements.filter { !$0.isDeleted && $0.groupIds.contains(inner) }.map(\.id))
      }
      return [e.id]
    }
    if let g = e.groupIds.last {
      return Set(scene.elements.filter { !$0.isDeleted && $0.groupIds.contains(g) }.map(\.id))
    }
    return [e.id]
  }

  // MARK: - Mouse

  override func mouseDown(with event: NSEvent) {
    window?.makeFirstResponder(self)
    textEditor?.commit()
    let p = scenePoint(event)
    let screen = convert(event.locationInWindow, from: nil)
    pointer.origin = p
    pointer.originScreen = screen
    pointer.last = p
    pointer.didDrag = false
    pointer.shift = event.modifierFlags.contains(.shift)
    pointer.alt = event.modifierFlags.contains(.option)
    pointer.startSelection = document.selection

    if cropState != nil {
      if cropMouseDown(at: p) {
        pointer.mode = .idle
        return
      }
    }
    if event.clickCount == 2 {
      handleDoubleClick(at: p)
      return
    }
    if spaceDown || document.view.tool == .hand || document.view.viewMode {
      pointer.mode = .panning
      pointer.panning = true
      updateCursor()
      return
    }
    if let id = pointer.multiPointElement {
      addMultiPoint(id, at: p)
      return
    }
    switch document.view.tool {
    case .selection, .lasso:
      selectionMouseDown(at: p, event: event)
    case .rectangle, .diamond, .ellipse, .frame, .embeddable:
      startShape(at: p)
    case .arrow, .line:
      startLinear(at: p)
    case .freedraw:
      startFreedraw(at: p, event: event)
    case .text:
      createText(at: p)
    case .image:
      document.insertImageFromPanel(at: p)
      if !document.view.toolLocked { document.setTool(.selection) }
    case .eraser:
      pointer.mode = .erasing
      erasing = []
      eraseAlong(from: p, to: p)
    case .laser:
      pointer.mode = .laser
      addLaserPoint(p)
    case .hand:
      break
    }
  }

  override func mouseDragged(with event: NSEvent) {
    let p = scenePoint(event)
    let screen = convert(event.locationInWindow, from: nil)
    if !pointer.didDrag, hypot(screen.x - pointer.originScreen.x, screen.y - pointer.originScreen.y) < 3 { return }
    pointer.didDrag = true
    if cropState?.corner != nil {
      cropDragged(to: p)
      return
    }
    pointer.shift = event.modifierFlags.contains(.shift)
    pointer.alt = event.modifierFlags.contains(.option)
    defer { pointer.last = p }
    switch pointer.mode {
    case .panning:
      document.scroll(by: CGPoint(x: event.deltaX, y: event.deltaY))
      viewChanged()
    case .boxSelect:
      updateBoxSelection(to: p)
    case .lasso:
      pointer.lassoPoints.append(p)
      updateLassoSelection()
    case .moving:
      dragSelection(to: p)
    case .resizing(let handle):
      resize(handle, to: p)
    case .rotating:
      rotate(to: p)
    case .drawingShape:
      updateShape(to: p)
    case .drawingLinear:
      updateLinear(to: p)
    case .drawingFreedraw:
      updateFreedraw(to: p, event: event)
    case .editingPoint(let index):
      dragPoint(index, to: p)
    case .erasing:
      eraseAlong(from: pointer.last, to: p)
    case .laser:
      addLaserPoint(p)
    case .idle:
      break
    }
  }

  override func mouseUp(with event: NSEvent) {
    let p = scenePoint(event)
    if cropState?.corner != nil {
      cropMouseUp()
      return
    }
    let mode = pointer.mode
    pointer.mode = .idle
    pointer.panning = false
    pointer.box = nil
    pointer.lassoPoints = []
    switch mode {
    case .moving, .resizing, .rotating, .editingPoint:
      liveIDs = []
      snapLines = []
      if case .editingPoint = mode, let id = document.singleSelection?.id { finishBinding(arrowID: id, point: p) }
      if case .moving = mode, !pointer.didDrag, let hit = pointer.hitOnDown, !pointer.shift {
        // Click (no drag) on an element in a multi-selection selects just it.
        document.select(selectionUnit(for: document.scene.element(hit)!))
      }
      if case .moving = mode, pointer.didDrag {
        let ids = document.selection
        document.updateInteraction { $0.adoptIntoFrames(ids) }
      }
      document.endInteraction()
    case .drawingShape:
      finishShape()
    case .drawingLinear:
      if pointer.didDrag {
        finishLinear(at: p)
      } else if let id = pointer.draftID {
        // Click without drag: continue as a multi-point line.
        pointer.multiPointElement = id
      }
    case .drawingFreedraw:
      finishFreedraw()
    case .erasing:
      let ids = erasing
      erasing = []
      if !ids.isEmpty { document.commit { $0.delete(ids) } }
      requestRender()
    case .laser, .panning, .boxSelect, .lasso, .idle:
      break
    }
    pointer.bindTarget = nil
    overlayLayer.setNeedsDisplay()
    updateCursor()
  }

  override func mouseMoved(with event: NSEvent) {
    let p = scenePoint(event)
    hoverPoint = p
    if let id = pointer.multiPointElement, let e = document.scene.element(id) {
      // Rubber-band the last point.
      document.updateInteraction { scene in
        scene.update(id) { el in
          var pts = el.points
          let local = CGPoint(x: p.x - e.x, y: p.y - e.y)
          if pts.count >= 2 { pts[pts.count - 1] = local }
          el.points = pts
          let r = CGRect(points: pts)
          el.width = r.width
          el.height = r.height
        }
      }
      pointer.bindTarget = document.view.tool == .arrow || e.type == .arrow ? bindableElement(at: p, excluding: [id])?.id : nil
      overlayLayer.setNeedsDisplay()
      return
    }
    if document.view.tool == .selection {
      let newCursor: NSCursor?
      if let h = handle(at: convert(event.locationInWindow, from: nil)) {
        newCursor = cursor(for: h)
      } else if hitElement(at: p) != nil || selectionBoundsContains(p) {
        newCursor = NSCursor.arrow
      } else {
        newCursor = nil
      }
      hoverCursor = newCursor
      updateCursor()
    }
    if document.view.tool == .arrow || document.view.tool == .line {
      let target = bindableElement(at: p, excluding: [])?.id
      if target != pointer.bindTarget {
        pointer.bindTarget = document.view.tool == .arrow ? target : nil
        overlayLayer.setNeedsDisplay()
      }
    }
  }

  override func rightMouseDown(with event: NSEvent) {
    let p = scenePoint(event)
    if let hit = hitElement(at: p), !document.selection.contains(hit.id) {
      document.select(selectionUnit(for: hit))
    } else if hitElement(at: p) == nil && !selectionBoundsContains(p) {
      document.selection = []
    }
    let menu = ContextMenuBuilder.menu(for: document, at: p, canvas: self)
    NSMenu.popUpContextMenu(menu, with: event, for: self)
  }

  override func otherMouseDown(with event: NSEvent) {
    pointer.mode = .panning
    pointer.panning = true
    updateCursor()
  }

  override func otherMouseDragged(with event: NSEvent) {
    document.scroll(by: CGPoint(x: event.deltaX, y: event.deltaY))
    viewChanged()
  }

  override func otherMouseUp(with event: NSEvent) {
    pointer.mode = .idle
    pointer.panning = false
    updateCursor()
  }

  // MARK: - Selection tool

  func selectionBoundsContains(_ p: CGPoint) -> Bool {
    guard document.selection.count > 0, let b = document.scene.bounds(of: document.selection) else { return false }
    if document.selection.count == 1, let e = document.singleSelection, e.angle != 0 {
      return CGRect(origin: .zero, size: CGSize(width: e.width, height: e.height)).insetBy(dx: -4 / zoom, dy: -4 / zoom).contains(e.toLocal(p))
    }
    return b.insetBy(dx: -4 / zoom, dy: -4 / zoom).contains(p)
  }

  func selectionMouseDown(at p: CGPoint, event: NSEvent) {
    let screen = convert(event.locationInWindow, from: nil)
    // 1. Transform handles of the current selection.
    if let h = handle(at: screen) {
      beginTransform(h, at: p)
      return
    }
    // 2. Point handles of a selected line/arrow.
    if let e = document.singleSelection, e.isLinear, !e.locked, let index = pointHandle(of: e, at: p) {
      pointer.mode = .editingPoint(index)
      pointer.originals = [e.id: e]
      document.beginInteraction()
      liveIDs = document.scene.withLabels([e.id])
      return
    }
    // 2b. Midpoint handles insert a new point (Excalidraw's linear editor).
    if let e = document.singleSelection, e.isLinear, !e.locked, !e.elbowed, let segment = midpointHandle(of: e, at: p) {
      document.beginInteraction()
      document.updateInteraction { scene in
        scene.update(e.id) { el in el.points.insert(el.toLocal(p), at: segment + 1) }
      }
      guard let updated = document.scene.element(e.id) else { return }
      pointer.mode = .editingPoint(segment + 1)
      pointer.originals = [e.id: updated]
      liveIDs = document.scene.withLabels([e.id])
      return
    }
    let hit = hitElement(at: p)
    pointer.hitOnDown = hit?.id
    // Cmd-click (or click on the link badge) opens an element's link.
    if let hit, let link = hit.link, event.modifierFlags.contains(.command) || linkBadgeContains(hit, p) {
      openLink(link)
      return
    }
    if document.view.tool == .lasso && hit == nil {
      pointer.mode = .lasso
      pointer.lassoPoints = [p]
      if !pointer.shift { document.selection = [] }
      return
    }
    if let hit {
      let unit = selectionUnit(for: hit)
      if pointer.shift {
        if unit.isSubset(of: document.selection) {
          document.selection.subtract(document.scene.withLabels(unit))
          pointer.mode = .idle
          return
        }
        document.select(document.selection.union(unit))
      } else if !document.selection.contains(hit.id) {
        document.select(unit)
      }
      beginMove(at: p)
      return
    }
    // 3. Inside the current selection's box: drag the selection.
    if selectionBoundsContains(p) && !pointer.shift {
      beginMove(at: p)
      return
    }
    // 4. Empty canvas: box select.
    if !pointer.shift {
      document.selection = []
      document.editingGroupID = nil
    }
    pointer.mode = .boxSelect
    pointer.box = CGRect(origin: p, size: .zero)
  }

  func beginMove(at p: CGPoint) {
    let movable = document.selection.filter { document.scene.element($0)?.locked == false }
    guard !movable.isEmpty else { return }
    pointer.mode = .moving
    document.beginInteraction()
    pointer.originals = Dictionary(uniqueKeysWithValues: document.scene.elements.filter { movable.contains($0.id) }.map { ($0.id, $0) })
    pointer.startBounds = document.scene.bounds(of: movable) ?? .zero
  }

  func dragSelection(to p: CGPoint) {
    var dx = p.x - pointer.origin.x
    var dy = p.y - pointer.origin.y
    if pointer.shift {
      // Lock to the dominant axis.
      if abs(dx) > abs(dy) { dy = 0 } else { dx = 0 }
    }
    if document.view.grid {
      let target = CGPoint(x: snap(pointer.startBounds.minX + dx), y: snap(pointer.startBounds.minY + dy))
      dx = target.x - pointer.startBounds.minX
      dy = target.y - pointer.startBounds.minY
    }
    // Snap to objects (Alt+S), or temporarily with Cmd held — like Excalidraw.
    snapLines = []
    if document.view.snapToObjects != NSEvent.modifierFlags.contains(.command) {
      let viewport = CGRect(
        x: -document.view.scrollX, y: -document.view.scrollY, width: bounds.width / zoom, height: bounds.height / zoom)
      let result = document.scene.snap(
        pointer.startBounds.offsetBy(dx: dx, dy: dy), excluding: liveSet(for: Set(pointer.originals.keys)),
        viewport: viewport, threshold: 8 / zoom)
      dx += result.offset.x
      dy += result.offset.y
      snapLines = result.lines
    }
    // Alt-drag duplicates once, leaving the originals in place.
    if pointer.alt, !pointer.originals.isEmpty, pointer.originals.keys.contains(where: { document.selection.contains($0) }) {
      let ids = Set(pointer.originals.keys)
      var created: [String] = []
      document.updateInteraction { created = $0.duplicate(ids, offset: .zero) }
      document.select(Set(created))
      pointer.originals = Dictionary(uniqueKeysWithValues: document.scene.elements.filter { document.selection.contains($0.id) }.map { ($0.id, $0) })
      pointer.alt = false
    }
    let ids = Set(pointer.originals.keys)
    liveIDs = liveSet(for: ids)
    let originals = pointer.originals
    document.updateInteraction { scene in
      // Reset to originals, then move once (avoids drift).
      for i in scene.elements.indices {
        if let o = originals[scene.elements[i].id] {
          scene.elements[i].x = o.x
          scene.elements[i].y = o.y
        }
      }
      scene.move(ids, by: CGPoint(x: dx, y: dy))
    }
  }

  /// Ids drawn live by the overlay during a transform: the elements, their
  /// labels, frame children and arrows bound to them.
  func liveSet(for ids: Set<String>) -> Set<String> {
    let scene = document.scene
    var set = scene.withLabels(ids)
    let frames = Set(ids.filter { scene.element($0)?.isFrame == true })
    set.formUnion(scene.withLabels(scene.frameChildren(frames)))
    for id in Array(set) {
      for b in scene.element(id)?.boundElements ?? [] where b.type == "arrow" {
        set.insert(b.id)
        if let t = scene.element(b.id)?.boundTextID { set.insert(t) }
      }
    }
    return set
  }

  func updateBoxSelection(to p: CGPoint) {
    let rect = CGRect(x: min(p.x, pointer.origin.x), y: min(p.y, pointer.origin.y), width: abs(p.x - pointer.origin.x), height: abs(p.y - pointer.origin.y))
    pointer.box = rect
    var ids = pointer.shift ? pointer.startSelection : []
    for e in document.scene.visibleElements where !e.locked && e.containerId == nil {
      if rect.contains(e.bounds) { ids.formUnion(selectionUnit(for: e)) }
    }
    document.select(ids)
    overlayLayer.setNeedsDisplay()
  }

  func updateLassoSelection() {
    let path = CGMutablePath()
    path.addLines(between: pointer.lassoPoints)
    path.closeSubpath()
    var ids = pointer.shift ? pointer.startSelection : []
    for e in document.scene.visibleElements where !e.locked && e.containerId == nil {
      let b = e.bounds
      let corners = [CGPoint(x: b.minX, y: b.minY), CGPoint(x: b.maxX, y: b.minY), CGPoint(x: b.minX, y: b.maxY), CGPoint(x: b.maxX, y: b.maxY)]
      if corners.allSatisfy({ path.contains($0) }) { ids.formUnion(selectionUnit(for: e)) }
    }
    document.select(ids)
    overlayLayer.setNeedsDisplay()
  }

  func handleDoubleClick(at p: CGPoint) {
    guard document.view.tool == .selection || document.view.tool == .text else { return }
    if let hit = hitElement(at: p) {
      if hit.isText {
        beginTextEditing(hit.id)
        return
      }
      if hit.isFrame {
        renameFrame(hit.id)
        return
      }
      if hit.type == .image {
        beginCrop(hit.id)
        return
      }
      // Double-click on a grouped element enters the group.
      if let g = hit.groupIds.last, document.editingGroupID != g {
        document.editingGroupID = g
        document.select(selectionUnit(for: hit))
        return
      }
    }
    // Like Excalidraw's getTextBindableContainerAtPosition: the whole shape
    // area counts, even when it has no fill.
    if let container = labelContainer(at: p) {
      beginLabelEditing(container: container.id, at: p)
      return
    }
    createText(at: p)
  }

  /// Frame (slide) title editing, like double-clicking a frame name in Excalidraw.
  func renameFrame(_ id: String) {
    guard let frame = document.scene.element(id) else { return }
    let alert = NSAlert()
    alert.messageText = "Rename frame"
    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
    field.stringValue = frame.name ?? "Frame"
    alert.accessoryView = field
    alert.addButton(withTitle: "Rename")
    alert.addButton(withTitle: "Cancel")
    alert.window.initialFirstResponder = field
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    let name = field.stringValue.trimmingCharacters(in: .whitespaces)
    document.commit { $0.update(id) { $0.name = name.isEmpty ? nil : name } }
  }

  /// Topmost shape or arrow that can hold a label and contains `p`.
  func labelContainer(at p: CGPoint) -> Element? {
    for e in document.scene.elements.reversed() where !e.isDeleted && !e.locked && e.canHaveLabel {
      if e.type == .arrow {
        if e.hitTest(p, threshold: hitThreshold) { return e }
      } else if e.localOutline.contains(e.toLocal(p)) || e.hitTest(p, threshold: hitThreshold) {
        return e
      }
    }
    return nil
  }

  func snap(_ v: CGFloat) -> CGFloat { (v / 20).rounded() * 20 }
  func snapPoint(_ p: CGPoint) -> CGPoint { document.view.grid ? CGPoint(x: snap(p.x), y: snap(p.y)) : p }

  // MARK: - Shapes

  func startShape(at p: CGPoint) {
    guard let type = document.view.tool.elementType else { return }
    let start = snapPoint(p)
    var e = Element.make(type, x: start.x, y: start.y, width: 0, height: 0, style: document.style)
    if type == .frame {
      e.name = "Frame"
    }
    pointer.origin = start
    pointer.draftID = e.id
    pointer.mode = .drawingShape
    document.beginInteraction()
    document.updateInteraction { scene in
      if type == .frame { scene.elements.insert(e, at: 0) } else { scene.elements.append(e) }
    }
    liveIDs = [e.id]
  }

  func updateShape(to raw: CGPoint) {
    guard let id = pointer.draftID else { return }
    let p = snapPoint(raw)
    var w = p.x - pointer.origin.x
    var h = p.y - pointer.origin.y
    if pointer.shift {
      let side = max(abs(w), abs(h))
      w = side * (w < 0 ? -1 : 1)
      h = side * (h < 0 ? -1 : 1)
    }
    var x = min(pointer.origin.x, pointer.origin.x + w)
    var y = min(pointer.origin.y, pointer.origin.y + h)
    if pointer.alt {
      x = pointer.origin.x - abs(w)
      y = pointer.origin.y - abs(h)
      w *= 2
      h *= 2
    }
    document.updateInteraction { scene in
      scene.update(id) { e in
        e.x = x
        e.y = y
        e.width = abs(w)
        e.height = abs(h)
      }
    }
    overlayLayer.setNeedsDisplay()
  }

  func finishShape() {
    defer {
      pointer.draftID = nil
      liveIDs = []
    }
    guard let id = pointer.draftID, let e = document.scene.element(id) else {
      document.endInteraction(commit: false)
      return
    }
    if e.width < 2 || e.height < 2 {
      document.endInteraction(commit: false)
      return
    }
    if e.isFrame {
      // A new frame adopts elements fully inside it.
      document.updateInteraction { scene in
        let candidates = Set(scene.visibleElements.filter { !$0.isFrame && $0.frameId == nil }.map(\.id))
        scene.adoptIntoFrames(candidates)
      }
    } else {
      document.updateInteraction { $0.adoptIntoFrames([id]) }
    }
    document.endInteraction()
    document.select([id])
    if !document.view.toolLocked { document.setTool(.selection) }
  }

  // MARK: - Lines and arrows

  func startLinear(at p: CGPoint) {
    guard let type = document.view.tool.elementType else { return }
    let start = snapPoint(p)
    var e = Element.make(type, x: start.x, y: start.y, width: 0, height: 0, style: document.style)
    e.points = [.zero, .zero]
    pointer.draftID = e.id
    pointer.mode = .drawingLinear
    document.beginInteraction()
    document.updateInteraction { $0.elements.append(e) }
    if type == .arrow, let target = bindableElement(at: p, excluding: [e.id]) {
      document.updateInteraction { $0.bind(arrowID: e.id, end: .start, to: target.id, at: p) }
    }
    liveIDs = [e.id]
  }

  func updateLinear(to raw: CGPoint) {
    guard let id = pointer.draftID, let e = document.scene.element(id) else { return }
    var p = snapPoint(raw)
    if pointer.shift {
      // Snap the angle to 15° steps (Excalidraw SHIFT_LOCKING_ANGLE).
      let o = CGPoint(x: e.x, y: e.y)
      let angle = atan2(p.y - o.y, p.x - o.x)
      let snapped = (angle / (.pi / 12)).rounded() * (.pi / 12)
      let len = hypot(p.x - o.x, p.y - o.y)
      p = CGPoint(x: o.x + cos(snapped) * len, y: o.y + sin(snapped) * len)
    }
    let local = CGPoint(x: p.x - e.x, y: p.y - e.y)
    let elbow = e.elbowed
    document.updateInteraction { scene in
      scene.update(id) { el in
        if elbow {
          el.setGlobalPoints(Scene.elbowRoute([CGPoint(x: el.x, y: el.y), p]))
        } else {
          el.points = [.zero, local]
          el.width = abs(local.x)
          el.height = abs(local.y)
        }
      }
      if e.startBinding != nil { scene.refreshArrow(id) }
    }
    pointer.bindTarget = e.type == .arrow ? bindableElement(at: raw, excluding: [id])?.id : nil
    overlayLayer.setNeedsDisplay()
  }

  func finishLinear(at p: CGPoint) {
    guard let id = pointer.draftID, let e = document.scene.element(id) else { return }
    pointer.draftID = nil
    liveIDs = []
    let length = hypot(e.width, e.height)
    if length < 4 && e.startBinding == nil {
      document.endInteraction(commit: false)
      return
    }
    finishBinding(arrowID: id, point: p)
    document.updateInteraction { $0.adoptIntoFrames([id]) }
    document.endInteraction()
    document.select([id])
    if !document.view.toolLocked { document.setTool(.selection) }
  }

  /// Binds the end of `arrowID` closest to `point` to the shape under it.
  func finishBinding(arrowID: String, point: CGPoint) {
    guard let e = document.scene.element(arrowID), e.type == .arrow, let last = e.points.last, let first = e.points.first else { return }
    let endGlobal = e.toScene(last)
    let startGlobal = e.toScene(first)
    let end: ArrowEnd = point.distance(to: endGlobal) <= point.distance(to: startGlobal) ? .end : .start
    let target = bindableElement(at: point, excluding: [arrowID])
    document.updateInteraction { scene in
      if let target {
        scene.bind(arrowID: arrowID, end: end, to: target.id, at: point)
      } else {
        scene.unbind(arrowID: arrowID, end: end)
      }
      scene.refreshArrow(arrowID)
    }
    pointer.bindTarget = nil
  }

  func addMultiPoint(_ id: String, at raw: CGPoint) {
    guard let e = document.scene.element(id) else {
      pointer.multiPointElement = nil
      return
    }
    let p = snapPoint(raw)
    let local = CGPoint(x: p.x - e.x, y: p.y - e.y)
    // Clicking the first point closes a line into a polygon.
    if e.type == .line, e.points.count >= 3, let first = e.points.first, local.distance(to: first) < 10 / zoom {
      document.updateInteraction { scene in
        scene.update(id) { el in
          el.points[el.points.count - 1] = first
          el.polygon = true
        }
      }
      finishMultiPoint()
      return
    }
    document.updateInteraction { scene in
      scene.update(id) { el in
        if el.points.count >= 2 { el.points[el.points.count - 1] = local }
        el.points.append(local)
      }
    }
    overlayLayer.setNeedsDisplay()
  }

  func finishMultiPoint() {
    guard let id = pointer.multiPointElement else { return }
    pointer.multiPointElement = nil
    // Drop the rubber-band point.
    document.updateInteraction { scene in
      scene.update(id) { el in
        if el.points.count > 2 { el.points.removeLast() }
        el.setGlobalPoints(el.points.map { CGPoint(x: el.x + $0.x, y: el.y + $0.y) })
      }
    }
    if let e = document.scene.element(id), let last = e.points.last {
      finishBinding(arrowID: id, point: e.toScene(last))
    }
    pointer.draftID = nil
    liveIDs = []
    document.endInteraction()
    document.select([id])
    if !document.view.toolLocked { document.setTool(.selection) }
  }

  /// Segment whose midpoint handle is under `p`.
  func midpointHandle(of e: Element, at p: CGPoint) -> Int? {
    guard e.points.count >= 2 else { return nil }
    for i in 0..<(e.points.count - 1) {
      let a = e.toScene(e.points[i])
      let b = e.toScene(e.points[i + 1])
      guard a.distance(to: b) > 30 / zoom else { continue }
      let m = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
      if m.distance(to: p) <= 7 / zoom { return i }
    }
    return nil
  }

  func linkBadgeContains(_ e: Element, _ p: CGPoint) -> Bool {
    let size = 14 / zoom
    let b = e.bounds
    return CGRect(x: b.maxX - size / 2, y: b.minY - size, width: size, height: size).insetBy(dx: -3 / zoom, dy: -3 / zoom).contains(p)
  }

  func openLink(_ link: String) {
    var s = link.trimmingCharacters(in: .whitespaces)
    if !s.contains("://") { s = "https://" + s }
    if let url = URL(string: s) { NSWorkspace.shared.open(url) }
  }

  /// Index of the point handle of a selected line under `p`.
  func pointHandle(of e: Element, at p: CGPoint) -> Int? {
    let r = 8 / zoom
    for (i, pt) in e.points.enumerated().reversed() where e.toScene(pt).distance(to: p) <= r { return i }
    return nil
  }

  func dragPoint(_ index: Int, to raw: CGPoint) {
    guard let id = document.singleSelection?.id, let original = pointer.originals[id] else { return }
    let p = snapPoint(raw)
    let isEnd = index == original.points.count - 1
    let isStart = index == 0
    document.updateInteraction { scene in
      var global = original.points.map { original.toScene($0) }
      global[index] = p
      scene.update(id) { el in
        el.setGlobalPoints(global)
      }
      // Dragging a bound end detaches it until it is dropped on a shape.
      if isStart { scene.unbind(arrowID: id, end: .start) }
      if isEnd { scene.unbind(arrowID: id, end: .end) }
      if scene.element(id)?.boundTextID != nil { scene.layoutLabel(of: id) }
    }
    if original.type == .arrow, isStart || isEnd {
      pointer.bindTarget = bindableElement(at: raw, excluding: [id])?.id
    }
    overlayLayer.setNeedsDisplay()
  }

  // MARK: - Freedraw

  func startFreedraw(at p: CGPoint, event: NSEvent) {
    var e = Element.make(.freedraw, x: p.x, y: p.y, style: document.style)
    e.points = [.zero]
    let pressure = event.subtype == .tabletPoint ? Double(event.pressure) : nil
    e.simulatePressure = pressure == nil
    e.pressures = pressure.map { [$0] } ?? []
    pointer.draftID = e.id
    pointer.mode = .drawingFreedraw
    document.beginInteraction()
    document.updateInteraction { $0.elements.append(e) }
    liveIDs = [e.id]
  }

  func updateFreedraw(to p: CGPoint, event: NSEvent) {
    guard let id = pointer.draftID else { return }
    let pressure = event.subtype == .tabletPoint ? Double(event.pressure) : nil
    document.updateInteraction { scene in
      scene.update(id) { el in
        el.points.append(CGPoint(x: p.x - el.x, y: p.y - el.y))
        if !el.simulatePressure { el.pressures.append(pressure ?? 0.5) }
      }
    }
    overlayLayer.setNeedsDisplay()
  }

  func finishFreedraw() {
    guard let id = pointer.draftID else { return }
    pointer.draftID = nil
    liveIDs = []
    // Normalise so the bounding box starts at x/y (Excalidraw keeps points relative).
    document.updateInteraction { scene in
      scene.update(id) { el in
        if el.points.count == 1 { el.points.append(CGPoint(x: 0.0001, y: 0.0001)) }
        let r = CGRect(points: el.points)
        el.width = r.width
        el.height = r.height
      }
      scene.adoptIntoFrames([id])
    }
    document.endInteraction()
  }

  // MARK: - Eraser

  func eraseAlong(from a: CGPoint, to b: CGPoint) {
    let steps = max(1, Int(a.distance(to: b) / (4 / zoom)))
    var changed = false
    for i in 0...steps {
      let t = CGFloat(i) / CGFloat(steps)
      let p = a + (b - a) * t
      if let hit = hitElement(at: p) {
        let unit = document.scene.withLabels(selectionUnit(for: hit))
        if !unit.isSubset(of: erasing) {
          erasing.formUnion(unit)
          changed = true
        }
      }
    }
    if changed { requestRender() }
    pointer.last = b
  }

  // MARK: - Laser pointer

  func addLaserPoint(_ p: CGPoint) {
    laserTrail.append((p, ProcessInfo.processInfo.systemUptime))
    if laserTimer == nil {
      laserTimer = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self] _ in
        MainActor.assumeIsolated {
          guard let self else { return }
          let now = ProcessInfo.processInfo.systemUptime
          self.laserTrail.removeAll { now - $0.time > 0.6 }
          self.overlayLayer.setNeedsDisplay()
          if self.laserTrail.isEmpty {
            self.laserTimer?.invalidate()
            self.laserTimer = nil
          }
        }
      }
    }
    overlayLayer.setNeedsDisplay()
  }
}
