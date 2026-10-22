import CoreGraphics
import Foundation

/// Scene edits shared by the app (keyboard, menus, panels) and agents (MCP).
/// Each takes element ids and keeps bindings, labels and groups consistent.
extension Scene {
  // MARK: - Selection helpers

  /// Expands ids with whole groups (outermost group) and bound labels, like
  /// clicking a grouped element in Excalidraw.
  public func expandedSelection(_ ids: Set<String>) -> Set<String> {
    var result = ids
    let groups = Set(ids.compactMap { element($0)?.groupIds.last })
    if !groups.isEmpty {
      for e in elements where !e.isDeleted {
        if let g = e.groupIds.last, groups.contains(g) { result.insert(e.id) }
      }
    }
    return withLabels(result)
  }

  /// Adds the bound text of every container in `ids`.
  public func withLabels(_ ids: Set<String>) -> Set<String> {
    var result = ids
    if ids.count > 8 {
      for e in elements where ids.contains(e.id) { if let t = e.boundTextID { result.insert(t) } }
    } else {
      for id in ids { if let t = element(id)?.boundTextID { result.insert(t) } }
    }
    return result
  }

  /// Elements whose frameId is one of the given frames.
  public func frameChildren(_ frameIDs: Set<String>) -> Set<String> {
    Set(elements.filter { !$0.isDeleted && $0.frameId.map(frameIDs.contains) == true }.map(\.id))
  }

  /// Union of element bounds (rotation included).
  public func bounds(of ids: Set<String>) -> CGRect? {
    let rects = elements.filter { ids.contains($0.id) && !$0.isDeleted }.map(\.bounds)
    guard let first = rects.first else { return nil }
    return rects.dropFirst().reduce(first) { $0.union($1) }
  }

  // MARK: - Move / delete / duplicate

  /// Moves elements (and their labels and frame children), then re-attaches arrows.
  public mutating func move(_ ids: Set<String>, by delta: CGPoint) {
    guard delta != .zero else { return }
    var moving = withLabels(ids)
    let frames = Set(elements.lazy.filter { $0.isFrame && moving.contains($0.id) }.map(\.id))
    if !frames.isEmpty { moving.formUnion(withLabels(frameChildren(frames))) }
    for i in elements.indices where moving.contains(elements[i].id) {
      elements[i].x += delta.x
      elements[i].y += delta.y
      elements[i].bump()
    }
    // Arrows moved on their own lose bindings to shapes that stayed put.
    for i in elements.indices where moving.contains(elements[i].id) && elements[i].type == .arrow {
      let id = elements[i].id
      if let b = elements[i].startBinding, !moving.contains(b.elementId) { unbind(arrowID: id, end: .start) }
      if let b = elements[i].endBinding, !moving.contains(b.elementId) { unbind(arrowID: id, end: .end) }
    }
    updateBoundArrows(of: Set(elements.lazy.filter { moving.contains($0.id) && $0.type != .arrow }.map(\.id)))
  }

  /// Soft-deletes elements with their labels and (for frames) children; cleans bindings.
  public mutating func delete(_ ids: Set<String>) {
    var doomed = withLabels(ids)
    let frames = Set(doomed.filter { element($0)?.isFrame == true })
    doomed.formUnion(withLabels(frameChildren(frames)))
    // Deleting a label clears its container's reference.
    for i in elements.indices where doomed.contains(elements[i].id) {
      elements[i].isDeleted = true
      elements[i].bump()
    }
    for i in elements.indices where !elements[i].isDeleted {
      var e = elements[i]
      var changed = false
      if let b = e.boundElements, b.contains(where: { doomed.contains($0.id) }) {
        e.boundElements = b.filter { !doomed.contains($0.id) }
        changed = true
      }
      if let s = e.startBinding, doomed.contains(s.elementId) { e.startBinding = nil; changed = true }
      if let s = e.endBinding, doomed.contains(s.elementId) { e.endBinding = nil; changed = true }
      if let c = e.containerId, doomed.contains(c) { e.isDeleted = true; changed = true }
      if changed {
        e.bump()
        elements[i] = e
      }
    }
  }

  /// Duplicates elements (with labels), offset by `offset`. New copies keep
  /// internal bindings/groups but get fresh ids. Returns the new ids
  /// (containers only, not their labels).
  @discardableResult
  public mutating func duplicate(_ ids: Set<String>, offset: CGPoint = CGPoint(x: 10, y: 10)) -> [String] {
    let source = withLabels(ids)
    var idMap: [String: String] = [:]
    for id in source { idMap[id] = Element.newID() }
    var groupMap: [String: String] = [:]
    var copies: [Element] = []
    for e in elements where source.contains(e.id) && !e.isDeleted {
      var c = e
      c.id = idMap[e.id]!
      c.x += offset.x
      c.y += offset.y
      c.seed = Element.randomSeed()
      c.version = 1
      c.versionNonce = Element.randomSeed()
      c.created = Element.now()
      c.updated = Element.now()
      c.index = nil
      c.groupIds = e.groupIds.map { g in
        if let m = groupMap[g] { return m }
        let n = Element.newID()
        groupMap[g] = n
        return n
      }
      c.containerId = e.containerId.flatMap { idMap[$0] }
      c.boundElements = e.boundElements?.compactMap { b in idMap[b.id].map { BoundElement(id: $0, type: b.type) } }
      if c.boundElements?.isEmpty == true { c.boundElements = nil }
      if var s = c.startBinding { if let m = idMap[s.elementId] { s.elementId = m; c.startBinding = s } else { c.startBinding = nil } }
      if var s = c.endBinding { if let m = idMap[s.elementId] { s.elementId = m; c.endBinding = s } else { c.endBinding = nil } }
      if let f = c.frameId, let m = idMap[f] { c.frameId = m }
      copies.append(c)
    }
    elements.append(contentsOf: copies)
    return copies.filter { $0.containerId == nil }.map(\.id)
  }

  // MARK: - Style

  /// Applies `change` to each element (and bound labels when `includeLabels`).
  public mutating func updateEach(_ ids: Set<String>, includeLabels: Bool = false, _ change: (inout Element) -> Void) {
    let targets = includeLabels ? withLabels(ids) : ids
    for i in elements.indices where targets.contains(elements[i].id) {
      change(&elements[i])
      elements[i].bump()
    }
  }

  // MARK: - Groups

  @discardableResult
  public mutating func group(_ ids: Set<String>) -> String? {
    let targets = withLabels(ids)
    guard targets.count > 1 else { return nil }
    let groupID = Element.newID()
    for i in elements.indices where targets.contains(elements[i].id) {
      elements[i].groupIds.append(groupID)
      elements[i].bump()
    }
    // Excalidraw also moves grouped elements next to each other in z-order.
    let topIndex = elements.lastIndex { targets.contains($0.id) } ?? 0
    let grouped = elements.filter { targets.contains($0.id) }
    var rest = elements.filter { !targets.contains($0.id) }
    let insertAt = rest.firstIndex { e in (elements.firstIndex { $0.id == e.id } ?? 0) > topIndex } ?? rest.count
    rest.insert(contentsOf: grouped, at: insertAt)
    elements = rest
    return groupID
  }

  /// Removes the outermost group of each selected element.
  public mutating func ungroup(_ ids: Set<String>) {
    let groups = Set(ids.compactMap { element($0)?.groupIds.last })
    for i in elements.indices {
      if let g = elements[i].groupIds.last, groups.contains(g) {
        elements[i].groupIds.removeLast()
        elements[i].bump()
      }
    }
  }

  // MARK: - Z-order

  public enum ZMove: String, Sendable { case front, back, forward, backward }

  /// Reorders elements (labels travel with their containers).
  public mutating func reorder(_ ids: Set<String>, _ move: ZMove) {
    let targets = withLabels(ids)
    guard !targets.isEmpty else { return }
    let moving = elements.filter { targets.contains($0.id) }
    var rest = elements.filter { !targets.contains($0.id) }
    switch move {
    case .front:
      rest.append(contentsOf: moving)
    case .back:
      rest.insert(contentsOf: moving, at: 0)
    case .forward, .backward:
      // Find the neighbour (visible, non-target) just above/below the block.
      let firstPos = elements.firstIndex { targets.contains($0.id) }!
      let lastPos = elements.lastIndex { targets.contains($0.id) }!
      if move == .forward {
        guard let neighbour = elements[(lastPos + 1)...].first(where: { !$0.isDeleted && !targets.contains($0.id) && $0.containerId == nil }),
          let at = rest.firstIndex(where: { $0.id == neighbour.id })
        else { return }
        let after = rest[(at + 1)...].firstIndex { $0.containerId != neighbour.id } ?? rest.count
        rest.insert(contentsOf: moving, at: after)
      } else {
        guard let neighbour = elements[..<firstPos].last(where: { !$0.isDeleted && !targets.contains($0.id) && $0.containerId == nil }),
          let at = rest.firstIndex(where: { $0.id == neighbour.id })
        else { return }
        rest.insert(contentsOf: moving, at: at)
      }
    }
    elements = rest
    for i in elements.indices where targets.contains(elements[i].id) {
      elements[i].index = nil  // re-synced on save
      elements[i].bump()
    }
    FractionalIndex.sync(&elements)
  }

  /// Moves one element directly above or below another (MCP zOrder "above"/"below").
  public mutating func place(_ id: String, relativeTo otherID: String, above: Bool) {
    let moving = withLabels([id])
    guard element(otherID) != nil else { return }
    let block = elements.filter { moving.contains($0.id) }
    var rest = elements.filter { !moving.contains($0.id) }
    guard var at = rest.firstIndex(where: { $0.id == otherID }) else { return }
    if above {
      at += 1
      if let label = element(otherID)?.boundTextID, let li = rest.firstIndex(where: { $0.id == label }), li >= at {
        at = li + 1
      }
    }
    rest.insert(contentsOf: block, at: at)
    elements = rest
    for i in elements.indices where moving.contains(elements[i].id) { elements[i].index = nil }
    FractionalIndex.sync(&elements)
  }

  // MARK: - Align / distribute

  public enum Alignment: String, Sendable, CaseIterable {
    case left, centerX, right, top, centerY, bottom
  }

  /// Aligns selection units (groups move together) to the selection bounds.
  public mutating func align(_ ids: Set<String>, _ alignment: Alignment) {
    let units = selectionUnits(ids)
    guard units.count > 1, let all = bounds(of: Set(units.flatMap { $0 })) else { return }
    for unit in units {
      guard let b = bounds(of: unit) else { continue }
      let dx: CGFloat
      let dy: CGFloat
      switch alignment {
      case .left: (dx, dy) = (all.minX - b.minX, 0)
      case .right: (dx, dy) = (all.maxX - b.maxX, 0)
      case .centerX: (dx, dy) = (all.midX - b.midX, 0)
      case .top: (dx, dy) = (0, all.minY - b.minY)
      case .bottom: (dx, dy) = (0, all.maxY - b.maxY)
      case .centerY: (dx, dy) = (0, all.midY - b.midY)
      }
      move(unit, by: CGPoint(x: dx, y: dy))
    }
  }

  /// Distributes units with equal gaps (Excalidraw distributeElements).
  public mutating func distribute(_ ids: Set<String>, horizontally: Bool) {
    let units = selectionUnits(ids).compactMap { u in bounds(of: u).map { (u, $0) } }
    guard units.count > 2 else { return }
    let sorted = units.sorted { horizontally ? $0.1.midX < $1.1.midX : $0.1.midY < $1.1.midY }
    let total = sorted.reduce(0) { $0 + (horizontally ? $1.1.width : $1.1.height) }
    let span =
      horizontally
      ? sorted.map(\.1.maxX).max()! - sorted.map(\.1.minX).min()!
      : sorted.map(\.1.maxY).max()! - sorted.map(\.1.minY).min()!
    let gap = (span - total) / CGFloat(sorted.count - 1)
    var cursor = horizontally ? sorted[0].1.minX : sorted[0].1.minY
    for (unit, b) in sorted {
      let delta = cursor - (horizontally ? b.minX : b.minY)
      move(unit, by: horizontally ? CGPoint(x: delta, y: 0) : CGPoint(x: 0, y: delta))
      cursor += (horizontally ? b.width : b.height) + gap
    }
  }

  /// Splits a selection into units: one per outermost group, else one per element.
  public func selectionUnits(_ ids: Set<String>) -> [Set<String>] {
    var byGroup: [String: Set<String>] = [:]
    var singles: [Set<String>] = []
    for e in elements where ids.contains(e.id) && !e.isDeleted && e.containerId == nil {
      if let g = e.groupIds.last { byGroup[g, default: []].insert(e.id) } else { singles.append([e.id]) }
    }
    return Array(byGroup.values) + singles
  }

  // MARK: - Frames

  /// Assigns elements fully inside `frameID` to it (Excalidraw adds elements to
  /// a frame when they are drawn or dropped inside it).
  public mutating func adoptIntoFrames(_ ids: Set<String>) {
    let frames = elements.filter { $0.isFrame && !$0.isDeleted }
    for i in elements.indices where ids.contains(elements[i].id) && !elements[i].isFrame && elements[i].containerId == nil {
      let b = elements[i].bounds
      let target = frames.last { $0.rect.contains(b) }?.id
      if elements[i].frameId != target {
        elements[i].frameId = target
        elements[i].bump()
        if let t = elements[i].boundTextID, let ti = indexOf(t) {
          elements[ti].frameId = target
          elements[ti].bump()
        }
      }
    }
  }
}
