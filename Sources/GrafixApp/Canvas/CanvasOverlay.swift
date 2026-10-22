import AppKit
import GrafixCore
import GrafixRender

/// Interactive layer drawing (port of renderer/interactiveScene.ts essentials).
extension CanvasView {
  var selectionColor: CGColor {
    CGColor(srgbRed: 0.706, green: 0.690, blue: 1, alpha: 1)  // #b4b0ff
  }

  func drawOverlay(in ctx: CGContext) {
    if !overlayLayer.contentsAreFlipped() {
      ctx.translateBy(x: 0, y: bounds.height)
      ctx.scaleBy(x: 1, y: -1)
    }
    let z = zoom
    ctx.saveGState()
    ctx.scaleBy(x: z, y: z)
    ctx.translateBy(x: document.view.scrollX, y: document.view.scrollY)

    drawLiveElements(ctx)
    if let target = pointer.bindTarget, let e = document.scene.element(target) { drawBindingHighlight(e, ctx) }
    if cropState != nil {
      drawCrop(ctx)
    } else if !document.view.viewMode && textEditor == nil {
      drawSelection(ctx)
    }
    if let box = pointer.box { drawBox(box, ctx) }
    if !snapLines.isEmpty { drawSnapLines(ctx) }
    if pointer.lassoPoints.count > 1 { drawLasso(ctx) }
    if !laserTrail.isEmpty { drawLaser(ctx) }
    ctx.restoreGState()
  }

  /// Elements being dragged/drawn, rendered every frame from the overlay cache.
  func drawLiveElements(_ ctx: CGContext) {
    guard !liveIDs.isEmpty else { return }
    let scene = document.scene
    var sub = Scene(elements: [], appState: scene.appState, files: scene.files)
    var hidden = Set<String>()
    let positions = scene.positions()
    var include = Set<String>()
    for id in liveIDs {
      include.insert(id)
      if let e = positions[id].map({ scene.elements[$0] }), let f = e.frameId, !liveIDs.contains(f) {
        include.insert(f)
        hidden.insert(f)
      }
      if let e = positions[id].map({ scene.elements[$0] }), let c = e.containerId, !liveIDs.contains(c) {
        include.insert(c)
        hidden.insert(c)
      }
    }
    sub.elements = scene.elements.filter { include.contains($0.id) }
    var options = SceneRenderer.Options()
    options.dark = true
    options.zoom = zoom
    options.hiddenIDs = hidden
    SceneRenderer.draw(sub, in: ctx, cache: overlayCache, options: options)
  }

  func drawSelection(_ ctx: CGContext) {
    let doc = document
    let selected = doc.selectedElements.filter { $0.containerId == nil || !doc.selection.contains($0.containerId!) }
    guard !selected.isEmpty, pointer.mode != .drawingShape, pointer.mode != .drawingFreedraw else { return }
    let lineWidth = 1 / zoom
    let pad = 4 / zoom
    ctx.setStrokeColor(selectionColor)
    ctx.setLineWidth(lineWidth)
    let multi = selected.count > 1
    for e in selected {
      if e.isLinear && e.points.count <= 2 && !multi { continue }
      let r = e.absoluteCoords.insetBy(dx: -pad, dy: -pad)
      strokeRotated(r, angle: e.angle, center: e.rotationCenter, ctx: ctx, dashed: e.locked)
    }
    if let single = doc.singleSelection, single.isLinear, !single.locked {
      drawPointHandles(single, ctx)
    }
    guard let frame = selectionFrame() else { return }
    if multi {
      ctx.saveGState()
      ctx.setLineDash(phase: 0, lengths: [8 / zoom, 4 / zoom])
      strokeRotated(frame.rect.insetBy(dx: -pad, dy: -pad), angle: 0, center: frame.center, ctx: ctx, dashed: false)
      ctx.restoreGState()
    }
    // Transform handles.
    let handles = handleRects(for: frame)
    ctx.saveGState()
    ctx.translateBy(x: frame.center.x, y: frame.center.y)
    ctx.rotate(by: frame.angle)
    ctx.translateBy(x: -frame.center.x, y: -frame.center.y)
    ctx.setFillColor(CGColor(srgbRed: 0.07, green: 0.07, blue: 0.07, alpha: 1))
    for (h, r) in handles {
      if h == .rotation {
        ctx.addEllipse(in: r)
      } else {
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: 2 / zoom, cornerHeight: 2 / zoom, transform: nil))
      }
      ctx.drawPath(using: .fillStroke)
    }
    ctx.restoreGState()
  }

  func strokeRotated(_ r: CGRect, angle: CGFloat, center: CGPoint, ctx: CGContext, dashed: Bool) {
    ctx.saveGState()
    if dashed { ctx.setLineDash(phase: 0, lengths: [4 / zoom, 4 / zoom]) }
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: angle)
    ctx.translateBy(x: -center.x, y: -center.y)
    ctx.stroke(r)
    ctx.restoreGState()
  }

  func drawPointHandles(_ e: Element, _ ctx: CGContext) {
    let radius = 5 / zoom
    ctx.saveGState()
    ctx.setLineWidth(1 / zoom)
    ctx.setStrokeColor(selectionColor)
    for (i, pt) in e.points.enumerated() {
      let p = e.toScene(pt)
      let bound = (i == 0 && e.startBinding != nil) || (i == e.points.count - 1 && e.endBinding != nil)
      ctx.setFillColor(bound ? selectionColor : CGColor(gray: 0.1, alpha: 1))
      ctx.addEllipse(in: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2))
      ctx.drawPath(using: .fillStroke)
    }
    // Midpoint handles (faint) for adding points.
    if !e.elbowed, e.points.count >= 2 {
      ctx.setFillColor(selectionColor.copy(alpha: 0.35) ?? selectionColor)
      let r = 3.5 / zoom
      for i in 0..<(e.points.count - 1) {
        let a = e.toScene(e.points[i])
        let b = e.toScene(e.points[i + 1])
        guard a.distance(to: b) > 30 / zoom else { continue }
        let m = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        ctx.fillEllipse(in: CGRect(x: m.x - r, y: m.y - r, width: r * 2, height: r * 2))
      }
    }
    ctx.restoreGState()
  }

  /// Excalidraw draws snap guides in a red-pink (#ff6b6b) with small crosses.
  func drawSnapLines(_ ctx: CGContext) {
    ctx.saveGState()
    ctx.setStrokeColor(CGColor(srgbRed: 1, green: 0.42, blue: 0.42, alpha: 1))
    ctx.setLineWidth(1 / zoom)
    for (a, b) in snapLines {
      ctx.move(to: a)
      ctx.addLine(to: b)
      for p in [a, b] {
        let s = 3 / zoom
        ctx.move(to: CGPoint(x: p.x - s, y: p.y - s))
        ctx.addLine(to: CGPoint(x: p.x + s, y: p.y + s))
        ctx.move(to: CGPoint(x: p.x - s, y: p.y + s))
        ctx.addLine(to: CGPoint(x: p.x + s, y: p.y - s))
      }
    }
    ctx.strokePath()
    ctx.restoreGState()
  }

  func drawBox(_ r: CGRect, _ ctx: CGContext) {
    ctx.saveGState()
    ctx.setFillColor(selectionColor.copy(alpha: 0.08) ?? selectionColor)
    ctx.fill(r)
    ctx.setStrokeColor(selectionColor)
    ctx.setLineWidth(1 / zoom)
    ctx.stroke(r)
    ctx.restoreGState()
  }

  func drawLasso(_ ctx: CGContext) {
    ctx.saveGState()
    ctx.setStrokeColor(selectionColor)
    ctx.setLineWidth(1 / zoom)
    ctx.setLineDash(phase: 0, lengths: [4 / zoom, 4 / zoom])
    ctx.addLines(between: pointer.lassoPoints)
    ctx.strokePath()
    ctx.setFillColor(selectionColor.copy(alpha: 0.06) ?? selectionColor)
    ctx.addLines(between: pointer.lassoPoints)
    ctx.closePath()
    ctx.fillPath()
    ctx.restoreGState()
  }

  /// Excalidraw highlights the shape an arrow end would bind to.
  func drawBindingHighlight(_ e: Element, _ ctx: CGContext) {
    ctx.saveGState()
    let c = e.rotationCenter
    ctx.translateBy(x: c.x, y: c.y)
    ctx.rotate(by: e.angle)
    ctx.translateBy(x: -c.x, y: -c.y)
    ctx.translateBy(x: e.x, y: e.y)
    ctx.setStrokeColor(selectionColor.copy(alpha: 0.35) ?? selectionColor)
    ctx.setLineWidth(8 / zoom)
    ctx.setLineJoin(.round)
    ctx.addPath(e.localOutline)
    ctx.strokePath()
    ctx.restoreGState()
  }

  func drawLaser(_ ctx: CGContext) {
    let now = ProcessInfo.processInfo.systemUptime
    ctx.saveGState()
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    for i in 1..<laserTrail.count {
      let a = laserTrail[i - 1]
      let b = laserTrail[i]
      let age = now - b.time
      let alpha = max(0, 1 - age / 0.6)
      ctx.setStrokeColor(CGColor(srgbRed: 1, green: 0.2, blue: 0.2, alpha: alpha))
      ctx.setLineWidth((2 + 3 * alpha) / zoom)
      ctx.move(to: a.point)
      ctx.addLine(to: b.point)
      ctx.strokePath()
    }
    ctx.restoreGState()
  }
}
