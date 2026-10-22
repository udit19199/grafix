import AppKit
import GrafixCore

/// Resize and rotate (simplified from Excalidraw's resizeElements.ts).
extension CanvasView {
  /// The box handles are drawn around: one rotated element, or the
  /// axis-aligned bounds of a multi-selection.
  struct SelectionFrame {
    var rect: CGRect  // unrotated, scene coords
    var angle: CGFloat
    var single: Element?
    var center: CGPoint { CGPoint(x: rect.midX, y: rect.midY) }
  }

  func selectionFrame() -> SelectionFrame? {
    let doc = document
    guard !doc.selection.isEmpty else { return nil }
    if let e = doc.singleSelection {
      if e.locked { return nil }
      // 2-point lines and arrows are edited by their points, not a box.
      if e.isLinear && e.points.count <= 2 { return nil }
      return SelectionFrame(rect: e.absoluteCoords, angle: e.angle, single: e)
    }
    let ids = doc.selection.filter { doc.scene.element($0)?.containerId == nil }
    guard let b = doc.scene.bounds(of: ids) else { return nil }
    if doc.selectedElements.contains(where: \.locked) { return nil }
    return SelectionFrame(rect: b, angle: 0, single: nil)
  }

  /// Handle rectangles in scene coords (getTransformHandlesFromCoords), unrotated.
  func handleRects(for frame: SelectionFrame) -> [Handle: CGRect] {
    let size = 8 / zoom
    let margin = 4 / zoom
    let spacing: CGFloat = 2
    let centering = (8 - spacing * 2) / (2 * zoom)
    let r = frame.rect
    var handles: [Handle: CGRect] = [
      .nw: CGRect(x: r.minX - margin - size + centering, y: r.minY - margin - size + centering, width: size, height: size),
      .ne: CGRect(x: r.maxX + margin - centering, y: r.minY - margin - size + centering, width: size, height: size),
      .sw: CGRect(x: r.minX - margin - size + centering, y: r.maxY + margin - centering, width: size, height: size),
      .se: CGRect(x: r.maxX + margin - centering, y: r.maxY + margin - centering, width: size, height: size),
      .rotation: CGRect(x: r.midX - size / 2, y: r.minY - margin - size + centering - 16 / zoom, width: size, height: size),
    ]
    let isText = frame.single?.isText == true
    let isFrame = frame.single?.isFrame == true
    if frame.single != nil, r.width > 5 * 8 / zoom {
      handles[.n] = CGRect(x: r.midX - size / 2, y: r.minY - margin - size + centering, width: size, height: size)
      handles[.s] = CGRect(x: r.midX - size / 2, y: r.maxY + margin - centering, width: size, height: size)
    }
    if frame.single != nil, r.height > 5 * 8 / zoom {
      handles[.w] = CGRect(x: r.minX - margin - size + centering, y: r.midY - size / 2, width: size, height: size)
      handles[.e] = CGRect(x: r.maxX + margin - centering, y: r.midY - size / 2, width: size, height: size)
    }
    if isText {
      // Text: corners scale the font, sides change the wrap width.
      handles[.n] = nil
      handles[.s] = nil
    }
    if isFrame { handles[.rotation] = nil }
    return handles
  }

  /// Handle under a screen point.
  func handle(at screen: CGPoint) -> Handle? {
    guard document.view.tool == .selection, let frame = selectionFrame() else { return nil }
    let p = document.sceneCoordinates(screen).rotated(around: frame.center, by: -frame.angle)
    let slop = 4 / zoom
    for (h, r) in handleRects(for: frame) where r.insetBy(dx: -slop, dy: -slop).contains(p) { return h }
    return nil
  }

  func cursor(for h: Handle) -> NSCursor {
    switch h {
    case .rotation: return .pointingHand
    case .n, .s: return .resizeUpDown
    case .e, .w: return .resizeLeftRight
    default: return .crosshair
    }
  }

  func beginTransform(_ h: Handle, at p: CGPoint) {
    guard let frame = selectionFrame() else { return }
    document.beginInteraction()
    let ids = document.scene.withLabels(document.selection)
    pointer.originals = Dictionary(uniqueKeysWithValues: document.scene.elements.filter { ids.contains($0.id) }.map { ($0.id, $0) })
    pointer.startBounds = frame.rect
    pointer.startAngle = frame.angle
    pointer.mode = h == .rotation ? .rotating : .resizing(h)
    liveIDs = liveSet(for: Set(pointer.originals.keys))
  }

  // MARK: - Resize

  func resize(_ h: Handle, to raw: CGPoint) {
    let p = snapPoint(raw)
    if let single = pointer.originals.values.first(where: { $0.containerId == nil }), pointer.originals.filter({ $0.value.containerId == nil }).count == 1 {
      resizeSingle(single, h, to: p)
    } else {
      resizeMultiple(h, to: p)
    }
    overlayLayer.setNeedsDisplay()
  }

  func resizeSingle(_ e0: Element, _ h: Handle, to p: CGPoint) {
    let box0 = e0.absoluteCoords
    let center0 = box0.center
    // Pointer in the element's unrotated frame.
    let q = p.rotated(around: center0, by: -e0.angle)
    var x1 = box0.minX
    var y1 = box0.minY
    var x2 = box0.maxX
    var y2 = box0.maxY
    switch h {
    case .nw: x1 = q.x; y1 = q.y
    case .n: y1 = q.y
    case .ne: x2 = q.x; y1 = q.y
    case .e: x2 = q.x
    case .se: x2 = q.x; y2 = q.y
    case .s: y2 = q.y
    case .sw: x1 = q.x; y2 = q.y
    case .w: x1 = q.x
    case .rotation: return
    }
    let keepAspect = (pointer.shift != (e0.type == .image)) || (e0.isText && [.nw, .ne, .se, .sw].contains(h))
    if keepAspect, box0.width > 0, box0.height > 0 {
      let ratio = box0.width / box0.height
      var w = x2 - x1
      var hgt = y2 - y1
      if [.n, .s].contains(h) {
        w = abs(hgt) * ratio * (w < 0 ? -1 : 1)
        let cx = box0.midX
        x1 = cx - w / 2
        x2 = cx + w / 2
      } else if [.e, .w].contains(h) {
        hgt = abs(w) / ratio * (hgt < 0 ? -1 : 1)
        let cy = box0.midY
        y1 = cy - hgt / 2
        y2 = cy + hgt / 2
      } else {
        let scale = max(abs(w) / box0.width, abs(hgt) / box0.height)
        let nw = box0.width * scale * (w < 0 ? -1 : 1)
        let nh = box0.height * scale * (hgt < 0 ? -1 : 1)
        switch h {
        case .nw: x1 = x2 - nw; y1 = y2 - nh
        case .ne: x2 = x1 + nw; y1 = y2 - nh
        case .sw: x1 = x2 - nw; y2 = y1 + nh
        default: x2 = x1 + nw; y2 = y1 + nh
        }
      }
    }
    if pointer.alt {
      // Resize from the centre: mirror the moved edges.
      let dx1 = x1 - box0.minX, dx2 = x2 - box0.maxX, dy1 = y1 - box0.minY, dy2 = y2 - box0.maxY
      x1 = box0.minX + dx1 - dx2
      x2 = box0.maxX + dx2 - dx1
      y1 = box0.minY + dy1 - dy2
      y2 = box0.maxY + dy2 - dy1
    }
    let flippedX = x2 < x1
    let flippedY = y2 < y1
    var newBox = CGRect(x: min(x1, x2), y: min(y1, y2), width: abs(x2 - x1), height: abs(y2 - y1))
    let minSize: CGFloat = e0.isLinear || e0.type == .freedraw ? 0 : 1
    newBox.size.width = max(newBox.width, minSize)
    newBox.size.height = max(newBox.height, minSize)
    // Keep the anchor fixed under rotation: compute where the new centre lands.
    let localCenter = newBox.center
    let newCenter = localCenter.rotated(around: center0, by: e0.angle)
    let shift = CGPoint(x: newCenter.x - localCenter.x, y: newCenter.y - localCenter.y)
    let finalBox = newBox.offsetBy(dx: shift.x, dy: shift.y)
    let id = e0.id
    let originals = pointer.originals
    document.updateInteraction { scene in
      guard let i = scene.indexOf(id) else { return }
      var e = e0
      apply(box: finalBox, from: box0, to: &e, flipX: flippedX, flipY: flippedY, handle: h)
      e.version = scene.elements[i].version
      e.bump()
      scene.elements[i] = e
      if e.boundTextID != nil {
        if let t = e.boundTextID, let o = originals[t], let ti = scene.indexOf(t) { scene.elements[ti] = o }
        scene.layoutLabel(of: id)
      }
      scene.updateBoundArrows(of: [id])
    }
  }

  /// Fits an element into `box` (scene coords of its unrotated bounding box).
  func apply(box: CGRect, from old: CGRect, to e: inout Element, flipX: Bool, flipY: Bool, handle: Handle?) {
    let sx = old.width > 0 ? box.width / old.width : 1
    let sy = old.height > 0 ? box.height / old.height : 1
    if e.isLinear || e.type == .freedraw {
      // Scale points about the old box, mirroring when flipped.
      let mapped = e.points.map { pt -> CGPoint in
        let gx = e.x + pt.x
        let gy = e.y + pt.y
        var nx = (gx - old.minX) * sx
        var ny = (gy - old.minY) * sy
        if flipX { nx = box.width - nx }
        if flipY { ny = box.height - ny }
        return CGPoint(x: box.minX + nx, y: box.minY + ny)
      }
      let angle = e.angle
      e.setGlobalPoints(mapped)
      e.angle = angle
      return
    }
    if e.isText {
      if let handle, [.e, .w].contains(handle) {
        e.autoResize = false
        e.width = max(box.width, e.fontSize)
        e.x = box.minX
        e.text = TextLayout.wrap(e.originalText, family: e.fontFamily, size: e.fontSize, maxWidth: e.width)
        e.height = TextLayout.measure(e.text, family: e.fontFamily, size: e.fontSize, lineHeight: e.lineHeight).height
        e.y = box.minY
        return
      }
      let k = old.height > 0 ? box.height / old.height : 1
      e.fontSize = max(1, e.fontSize * k)
      e.x = box.minX
      e.y = box.minY
      e.width = box.width
      e.height = box.height
      if !e.autoResize {
        e.text = TextLayout.wrap(e.originalText, family: e.fontFamily, size: e.fontSize, maxWidth: e.width)
      }
      return
    }
    e.x = box.minX
    e.y = box.minY
    e.width = box.width
    e.height = box.height
    if e.type == .image {
      if flipX { e.scale[0] *= -1 }
      if flipY { e.scale[1] *= -1 }
    }
  }

  func resizeMultiple(_ h: Handle, to p: CGPoint) {
    let b = pointer.startBounds
    guard b.width > 0, b.height > 0 else { return }
    // Anchor = opposite corner; always proportional (like Excalidraw).
    let anchor: CGPoint
    switch h {
    case .nw: anchor = CGPoint(x: b.maxX, y: b.maxY)
    case .ne: anchor = CGPoint(x: b.minX, y: b.maxY)
    case .sw: anchor = CGPoint(x: b.maxX, y: b.minY)
    default: anchor = CGPoint(x: b.minX, y: b.minY)
    }
    let corner: CGPoint
    switch h {
    case .nw: corner = CGPoint(x: b.minX, y: b.minY)
    case .ne: corner = CGPoint(x: b.maxX, y: b.minY)
    case .sw: corner = CGPoint(x: b.minX, y: b.maxY)
    default: corner = CGPoint(x: b.maxX, y: b.maxY)
    }
    let kx = (p.x - anchor.x) / (corner.x - anchor.x)
    let ky = (p.y - anchor.y) / (corner.y - anchor.y)
    let k = max(0.05, max(kx, ky))
    let originals = pointer.originals
    document.updateInteraction { scene in
      for (id, o) in originals where o.containerId == nil || originals[o.containerId!] == nil {
        guard let i = scene.indexOf(id) else { continue }
        var e = o
        let old = o.absoluteCoords
        let box = CGRect(
          x: anchor.x + (old.minX - anchor.x) * k, y: anchor.y + (old.minY - anchor.y) * k,
          width: old.width * k, height: old.height * k)
        if e.isText {
          e.fontSize = max(1, o.fontSize * k)
          e.x = box.minX
          e.y = box.minY
          e.width = box.width
          e.height = box.height
        } else {
          apply(box: box, from: old, to: &e, flipX: false, flipY: false, handle: nil)
        }
        if o.boundTextID != nil, !e.isText {
          // Scale label font with the container.
          if let t = o.boundTextID, let to = originals[t], let ti = scene.indexOf(t) {
            var label = to
            label.fontSize = max(1, to.fontSize * k)
            label.bump()
            scene.elements[ti] = label
          }
        }
        e.version = scene.elements[i].version
        e.bump()
        scene.elements[i] = e
      }
      for id in originals.keys where scene.element(id)?.boundTextID != nil { scene.layoutLabel(of: id) }
      scene.updateBoundArrows(of: Set(originals.keys))
    }
  }

  // MARK: - Rotate

  func rotate(to p: CGPoint) {
    let c = pointer.startBounds.center
    var angle = atan2(p.y - c.y, p.x - c.x) + .pi / 2
    if pointer.shift {
      angle = (angle / (.pi / 12)).rounded() * (.pi / 12)
    }
    let originals = pointer.originals
    let delta = angle - pointer.startAngle
    let single = originals.values.filter { $0.containerId == nil }.count == 1
    document.updateInteraction { scene in
      for (id, o) in originals {
        guard let i = scene.indexOf(id) else { continue }
        var e = o
        if o.isText, let cid = o.containerId, originals[cid] != nil { continue }
        if single {
          e.angle = normalize(angle)
        } else {
          let oc = o.rotationCenter
          let nc = oc.rotated(around: c, by: delta - (originals.isEmpty ? 0 : 0))
          e.x += nc.x - oc.x
          e.y += nc.y - oc.y
          e.angle = normalize(o.angle + delta)
        }
        e.version = scene.elements[i].version
        e.bump()
        scene.elements[i] = e
      }
      for id in originals.keys where scene.element(id)?.boundTextID != nil { scene.layoutLabel(of: id) }
      scene.updateBoundArrows(of: Set(originals.keys))
    }
    overlayLayer.setNeedsDisplay()
  }

  func normalize(_ a: CGFloat) -> CGFloat {
    var v = a.truncatingRemainder(dividingBy: 2 * .pi)
    if v < 0 { v += 2 * .pi }
    return v
  }
}
