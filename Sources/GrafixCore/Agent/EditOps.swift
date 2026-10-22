import CoreGraphics
import Foundation

/// The edit API used by agents (MCP `edit_scene_content`) and by the in-app chat.
/// It mirrors the Excalidraw+ MCP contract so models that know it work here:
///
/// - `delete`: element ids (soft delete; labels, bindings cleaned up).
/// - `update`: patches `{id, ...fields}`; `label: {text, fontSize?, ...}` edits the shape's label.
/// - `add`: element skeletons without `id`. Required: `type, x, y` (+ `width, height`
///   except for text). Optional `tempId` lets other skeletons in the same call
///   reference it in `frameId`, `containerId`, `startBinding.elementId`,
///   `endBinding.elementId`, `groupIds`. `label: {text, ...}` adds bound text.
///   Arrows may omit geometry when both bindings are given.
/// - `zOrder`: moves `{id, at: front|back}` or `{id, above: id}` / `{id, below: id}`.
///
/// Operations apply in order delete -> update -> add -> zOrder.
public struct EditRequest: Sendable {
  public var delete: [String] = []
  public var update: [[String: JSONValue]] = []
  public var add: [[String: JSONValue]] = []
  public var zOrder: [[String: JSONValue]] = []
  public init(
    delete: [String] = [], update: [[String: JSONValue]] = [], add: [[String: JSONValue]] = [],
    zOrder: [[String: JSONValue]] = []
  ) {
    self.delete = delete
    self.update = update
    self.add = add
    self.zOrder = zOrder
  }
}

public struct EditResult: Sendable {
  /// tempId (or "#<index>" when no tempId was given) -> created element id.
  public var created: [String: String] = [:]
  public var createdIDs: [String] = []
  public var updatedIDs: [String] = []
  public var deletedIDs: [String] = []
  public var warnings: [String] = []

  public var json: JSONValue {
    .object([
      "created": .object(created.mapValues(JSONValue.string)),
      "createdIds": .array(createdIDs.map(JSONValue.string)),
      "updatedIds": .array(updatedIDs.map(JSONValue.string)),
      "deletedIds": .array(deletedIDs.map(JSONValue.string)),
      "warnings": .array(warnings.map(JSONValue.string)),
    ])
  }
}

public struct EditError: Error, LocalizedError {
  public var message: String
  public init(_ message: String) { self.message = message }
  public var errorDescription: String? { message }
}

extension Scene {
  /// Applies an agent edit. Throws only for malformed input; per-item problems
  /// that can be skipped are returned as warnings.
  @discardableResult
  public mutating func apply(_ request: EditRequest) throws -> EditResult {
    var result = EditResult()
    let positions = positions()

    // 1. delete
    let toDelete = Set(request.delete.filter { positions[$0] != nil })
    for id in request.delete where positions[id] == nil { result.warnings.append("delete: no element \(id)") }
    if !toDelete.isEmpty {
      delete(toDelete)
      result.deletedIDs = Array(toDelete)
    }

    // 2. update
    for patch in request.update {
      guard let id = patch["id"]?.string else { throw EditError("update: every patch needs an id") }
      guard let i = indexOf(id), !elements[i].isDeleted else {
        result.warnings.append("update: no element \(id)")
        continue
      }
      applyPatch(patch, at: i, tempIDs: [:], result: &result)
      result.updatedIDs.append(id)
    }

    // 3. add
    var tempIDs: [String: String] = [:]
    // Assign ids first so skeletons can reference each other in any order.
    var newIDs: [String] = []
    for (n, skeleton) in request.add.enumerated() {
      if skeleton["id"] != nil { throw EditError("add[\(n)]: do not include id; use tempId") }
      let id = Element.newID()
      newIDs.append(id)
      let key = skeleton["tempId"]?.string ?? "#\(n)"
      if tempIDs[key] != nil { throw EditError("add: tempId \(key) is used twice") }
      tempIDs[key] = id
    }
    let resolve: (String) -> String = { tempIDs[$0] ?? $0 }
    var pendingBindings: [(arrow: String, end: ArrowEnd, binding: [String: JSONValue])] = []
    var pendingLabels: [(id: String, label: [String: JSONValue])] = []
    for (n, skeleton) in request.add.enumerated() {
      guard let typeName = skeleton["type"]?.string else { throw EditError("add[\(n)]: missing type") }
      var element = try makeElement(from: skeleton, type: ElementType(rawValue: typeName), id: newIDs[n], resolve: resolve, index: n)
      if let b = skeleton["startBinding"]?.object { pendingBindings.append((element.id, .start, b)) }
      if let b = skeleton["endBinding"]?.object { pendingBindings.append((element.id, .end, b)) }
      element.startBinding = nil
      element.endBinding = nil
      if element.type == .frame || element.type == .magicframe {
        elements.insert(element, at: 0)  // frames stay below their children
      } else {
        elements.append(element)
      }
      if let label = skeleton["label"] {
        guard let o = label.object else { throw EditError("add[\(n)]: label must be an object like {\"text\": \"...\"}") }
        pendingLabels.append((element.id, o))
      }
      result.createdIDs.append(element.id)
      result.created[skeleton["tempId"]?.string ?? "#\(n)"] = element.id
    }
    // Geometry-less arrows: place between their targets before binding.
    for (arrowID, _, _) in pendingBindings {
      placeArrowIfNeeded(arrowID, bindings: pendingBindings.filter { $0.arrow == arrowID }, resolve: resolve)
    }
    for (arrowID, end, b) in pendingBindings {
      bindFromJSON(arrowID: arrowID, end: end, b, resolve: resolve, result: &result)
    }
    for (id, label) in pendingLabels { applyLabel(label, to: id) }
    let touched = Set(result.createdIDs + result.updatedIDs)
    for id in Set(pendingBindings.map(\.arrow)) { refreshArrow(id) }
    updateBoundArrows(of: touched)

    // 4. zOrder
    for move in request.zOrder {
      guard let rawID = move["id"]?.string else { throw EditError("zOrder: each move needs id") }
      let id = resolve(rawID)
      guard element(id) != nil else {
        result.warnings.append("zOrder: no element \(rawID)")
        continue
      }
      if let at = move["at"]?.string {
        reorder([id], at == "back" ? .back : .front)
      } else if let other = move["above"]?.string {
        place(id, relativeTo: resolve(other), above: true)
      } else if let other = move["below"]?.string {
        place(id, relativeTo: resolve(other), above: false)
      } else {
        result.warnings.append("zOrder: move for \(rawID) needs at, above or below")
      }
    }
    FractionalIndex.sync(&elements)
    return result
  }

  // MARK: - add helpers

  static let skeletonOnlyKeys: Set<String> = ["tempId", "label", "id", "index"]

  mutating func makeElement(
    from skeleton: [String: JSONValue], type: ElementType, id: String, resolve: (String) -> String, index n: Int
  ) throws -> Element {
    let hasGeometry = skeleton["x"]?.number != nil && skeleton["y"]?.number != nil
    let isArrowWithBindings = (type == .arrow || type == .line) && skeleton["startBinding"] != nil && skeleton["endBinding"] != nil
    if !hasGeometry && !isArrowWithBindings {
      throw EditError("add[\(n)]: \(type.rawValue) needs numeric x and y")
    }
    var base = Element.make(
      type, x: skeleton["x"]?.number ?? 0, y: skeleton["y"]?.number ?? 0,
      width: skeleton["width"]?.number ?? 0, height: skeleton["height"]?.number ?? 0)
    base.id = id
    // Agent-created shapes default to round edges + solid fill, like Excalidraw+'s MCP.
    var json = base.json
    for (k, v) in skeleton where !Scene.skeletonOnlyKeys.contains(k) { json[k] = v }
    json["id"] = .string(id)
    if let f = json["frameId"]?.string { json["frameId"] = .string(resolve(f)) }
    if let c = json["containerId"]?.string { json["containerId"] = .string(resolve(c)) }
    if let groups = json["groupIds"]?.array {
      json["groupIds"] = .array(groups.compactMap(\.string).map { .string(resolve($0)) })
    }
    var e = Element(json: json)
    e.version = 1
    e.isDeleted = false
    if e.type == .text {
      if skeleton["originalText"] == nil { e.originalText = e.text }
      if skeleton["lineHeight"] == nil { e.lineHeight = FontFamily(rawValue: e.fontFamily)?.lineHeight ?? 1.25 }
      if skeleton["width"] == nil || skeleton["height"] == nil || skeleton["autoResize"] == nil {
        let keepWidth = skeleton["width"]?.number
        e.autoResize = keepWidth == nil
        if let keepWidth { e.width = keepWidth }
        e.fitText()
      }
    }
    if (e.isLinear || e.type == .freedraw), skeleton["points"] == nil {
      e.points = [.zero, CGPoint(x: e.width, y: e.height)]
    }
    if e.isLinear, let first = e.points.first, first != .zero {
      // Normalise so points[0] == (0,0).
      e.setGlobalPoints(e.points.map { CGPoint(x: e.x + $0.x, y: e.y + $0.y) })
    }
    if e.isLinear, skeleton["width"] == nil || skeleton["height"] == nil {
      let r = CGRect(points: e.points)
      e.width = r.width
      e.height = r.height
    }
    if let c = e.containerId, let ci = indexOf(c) {
      var bound = elements[ci].boundElements ?? []
      bound.append(BoundElement(id: e.id, type: "text"))
      elements[ci].boundElements = bound
    }
    return e
  }

  mutating func placeArrowIfNeeded(
    _ arrowID: String, bindings: [(arrow: String, end: ArrowEnd, binding: [String: JSONValue])],
    resolve: (String) -> String
  ) {
    guard let ai = indexOf(arrowID), elements[ai].width == 0, elements[ai].height == 0,
      elements[ai].x == 0, elements[ai].y == 0
    else { return }
    func center(_ end: ArrowEnd) -> CGPoint? {
      guard let b = bindings.first(where: { $0.end == end })?.binding, let id = b["elementId"]?.string,
        let t = element(resolve(id))
      else { return nil }
      return t.center
    }
    guard let a = center(.start), let b = center(.end) else { return }
    elements[ai].setGlobalPoints(elements[ai].elbowed ? Scene.elbowRoute([a, b]) : [a, b])
  }

  mutating func bindFromJSON(
    arrowID: String, end: ArrowEnd, _ b: [String: JSONValue], resolve: (String) -> String, result: inout EditResult
  ) {
    guard let raw = b["elementId"]?.string else {
      result.warnings.append("binding on \(arrowID) has no elementId")
      return
    }
    let targetID = resolve(raw)
    guard let target = element(targetID), let arrow = element(arrowID) else {
      result.warnings.append("binding target \(raw) not found")
      return
    }
    let mode = b["mode"]?.string ?? "orbit"
    let point: CGPoint
    if let f = b["fixedPoint"]?.array, f.count == 2, let fx = f[0].number, let fy = f[1].number {
      point = CGPoint(x: target.x + target.width * fx, y: target.y + target.height * fy)
        .rotated(around: target.center, by: target.angle)
    } else if mode == "inside" {
      // Aim at the side of the target facing the other end of the arrow.
      let other = end == .start ? arrow.toScene(arrow.points.last ?? .zero) : arrow.toScene(arrow.points.first ?? .zero)
      point = Scene.sideMidpoint(of: target, facing: other)
    } else {
      point = target.center
    }
    bind(arrowID: arrowID, end: end, to: targetID, at: point, mode: mode)
  }

  /// Midpoint of the target's side that faces `p` (used for unspecified "inside" bindings).
  static func sideMidpoint(of t: Element, facing p: CGPoint) -> CGPoint {
    let c = t.center
    let dx = (p.x - c.x) / max(t.width, 1)
    let dy = (p.y - c.y) / max(t.height, 1)
    if abs(dx) > abs(dy) {
      return CGPoint(x: dx > 0 ? t.x + t.width : t.x, y: c.y)
    }
    return CGPoint(x: c.x, y: dy > 0 ? t.y + t.height : t.y)
  }

  mutating func applyLabel(_ label: [String: JSONValue], to id: String) {
    let text = label["text"]?.string ?? ""
    let align = label["textAlign"]?.string.flatMap(TextAlign.init(rawValue:)) ?? .center
    let valign = label["verticalAlign"]?.string.flatMap(VerticalAlign.init(rawValue:)) ?? .middle
    setLabel(
      text, on: id, fontSize: label["fontSize"]?.number, fontFamily: label["fontFamily"]?.number.map { Int($0) },
      strokeColor: label["strokeColor"]?.string, textAlign: align, verticalAlign: valign)
  }

  // MARK: - update helpers

  mutating func applyPatch(_ patch: [String: JSONValue], at i: Int, tempIDs: [String: String], result: inout EditResult) {
    let id = elements[i].id
    var json = elements[i].json
    for (k, v) in patch where !["id", "label", "startBinding", "endBinding", "index", "type"].contains(k) {
      if k == "customData", let new = v.object, let old = json["customData"]?.object {
        // Merge so slide order and notes are not wiped by partial patches.
        json[k] = .object(old.merging(new) { _, b in b })
      } else {
        json[k] = v
      }
    }
    var e = Element(json: json)
    if e.type == .text, patch["text"] != nil {
      if patch["originalText"] == nil { e.originalText = e.text }
      if e.containerId == nil { e.fitText() }
    }
    e.bump()
    elements[i] = e
    for end in [("startBinding", ArrowEnd.start), ("endBinding", ArrowEnd.end)] {
      guard let v = patch[end.0] else { continue }
      if v.isNull {
        unbind(arrowID: id, end: end.1)
      } else if let o = v.object {
        bindFromJSON(arrowID: id, end: end.1, o, resolve: { tempIDs[$0] ?? $0 }, result: &result)
      }
    }
    if let label = patch["label"] {
      if let o = label.object { applyLabel(o, to: id) } else { result.warnings.append("update \(id): label must be an object") }
    }
    if let c = elements[indexOf(id)!].containerId { layoutLabel(of: c) }
    if elements[indexOf(id)!].boundTextID != nil { layoutLabel(of: id) }
    updateBoundArrows(of: [id])
  }
}

// MARK: - Read helpers for agents

extension Scene {
  /// Compact description of an element for agents (no noise fields).
  public func summary(of e: Element) -> [String: JSONValue] {
    var o: [String: JSONValue] = [
      "id": .string(e.id), "type": .string(e.type.rawValue),
      "x": .number(e.x.rounded2), "y": .number(e.y.rounded2),
      "width": .number(e.width.rounded2), "height": .number(e.height.rounded2),
    ]
    if e.angle != 0 { o["angle"] = .number(e.angle) }
    if e.strokeColor != "#1e1e1e" { o["strokeColor"] = .string(e.strokeColor) }
    if e.backgroundColor != "transparent" { o["backgroundColor"] = .string(e.backgroundColor) }
    if e.type == .text {
      o["text"] = .string(e.originalText)
      o["fontSize"] = .number(e.fontSize)
      o["fontFamily"] = .number(Double(e.fontFamily))
      if let c = e.containerId { o["containerId"] = .string(c) }
    }
    if let t = e.boundTextID, let label = element(t) { o["label"] = .string(label.originalText) }
    if let f = e.frameId { o["frameId"] = .string(f) }
    if !e.groupIds.isEmpty { o["groupIds"] = .array(e.groupIds.map(JSONValue.string)) }
    if let n = e.name { o["name"] = .string(n) }
    if e.isLinear {
      if let s = e.startBinding { o["startBinding"] = .string(s.elementId) }
      if let s = e.endBinding { o["endBinding"] = .string(s.elementId) }
    }
    if e.locked { o["locked"] = .bool(true) }
    if let link = e.link { o["link"] = .string(link) }
    return o
  }

  /// Visible elements matching a text query and/or types, for search tools.
  public func search(query: String?, types: Set<String>? = nil, frameID: String? = nil, limit: Int = 25) -> [Element] {
    let q = query?.lowercased().filter { !" -_".contains($0) }
    var out: [Element] = []
    for e in visibleElements where e.containerId == nil {
      if let types, !types.contains(e.type.rawValue) { continue }
      if let frameID, e.frameId != frameID, e.id != frameID { continue }
      if let q, !q.isEmpty {
        var haystack = e.type == .text ? e.originalText : ""
        if let t = e.boundTextID, let label = element(t) { haystack += " " + label.originalText }
        if let n = e.name { haystack += " " + n }
        if !haystack.lowercased().filter({ !" -_".contains($0) }).contains(q) { continue }
      }
      out.append(e)
      if out.count >= limit { break }
    }
    return out
  }
}

extension Double {
  /// Rounded to 2 decimals, for compact agent output.
  public var rounded2: Double { (self * 100).rounded() / 100 }
}
