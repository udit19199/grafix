import GrafixCore
import SwiftUI

/// Which element/tool types each property applies to
/// (packages/element/src/comparisons.ts).
extension ElementType {
  var hasBackground: Bool { [.rectangle, .stickynote, .iframe, .embeddable, .ellipse, .diamond, .line, .freedraw].contains(self) }
  var hasFillStyle: Bool { hasBackground && self != .stickynote }
  var hasStrokeColor: Bool {
    [.rectangle, .stickynote, .ellipse, .diamond, .freedraw, .arrow, .line, .text, .embeddable].contains(self)
  }
  var hasStrokeWidth: Bool { [.rectangle, .iframe, .embeddable, .ellipse, .diamond, .freedraw, .arrow, .line].contains(self) }
  var hasStrokeStyle: Bool { [.rectangle, .iframe, .embeddable, .ellipse, .diamond, .arrow, .line].contains(self) }
  var hasRoughness: Bool { hasStrokeStyle || self == .stickynote }
  var canChangeRoundness: Bool { [.rectangle, .iframe, .embeddable, .line, .diamond, .stickynote, .image].contains(self) }
}

/// Excalidraw's `getShapeActionPredicates` + `getFormValue` for the properties
/// panel: which sections to show for the active tool and selection, and the
/// current value of each property (nil when the selection disagrees).
@MainActor
struct PanelTarget {
  let tool: Tool
  let elements: [Element]
  let style: ItemStyle
  let selectionRoots: Int

  init(_ doc: EditorDocument) {
    tool = doc.view.tool
    elements = doc.selectedElements
    style = doc.style
    selectionRoots = doc.selectedElements.filter { $0.containerId == nil || !doc.selection.contains($0.containerId!) }.count
  }

  var hasSelection: Bool { !elements.isEmpty }
  private var toolType: ElementType? { tool.elementType }

  /// `forToolOrSelection`: applies to the active tool or to any selected element.
  private func either(_ p: (ElementType) -> Bool) -> Bool {
    (toolType.map(p) ?? false) || elements.contains { p($0.type) }
  }

  var strokeColor: Bool {
    let common = Set(elements.map(\.type.rawValue))
    let single = common.count == 1 ? common.first : nil
    let toolOK = (toolType?.hasStrokeColor ?? false) && single != "image" && single != "frame" && single != "magicframe"
    return toolOK || elements.contains { $0.type.hasStrokeColor }
  }
  var backgroundColor: Bool { (toolType?.hasBackground ?? false) || elements.contains { $0.type.hasBackground } }
  var fill: Bool {
    ((toolType?.hasFillStyle ?? false) && !Self.transparent(style.backgroundColor))
      || elements.contains { $0.type.hasFillStyle && !Self.transparent($0.backgroundColor) }
  }
  var strokeWidth: Bool { either(\.hasStrokeWidth) }
  var strokeStyle: Bool { either(\.hasStrokeStyle) }
  var sloppiness: Bool { either(\.hasRoughness) }
  var roundness: Bool { either(\.canChangeRoundness) }
  var arrowType: Bool { either { $0 == .arrow } }
  var arrowheads: Bool { either { $0 == .arrow } }
  var text: Bool { tool == .text || elements.contains(where: \.isText) }
  var textAlign: Bool { tool == .text || elements.contains(where: \.isText) }
  var verticalAlign: Bool { elements.contains { $0.isText && $0.containerId != nil } }
  var layers: Bool {
    (tool != .freedraw && !elements.contains { $0.type == .freedraw }) || elements.contains { $0.type == .freedraw }
  }
  var align: Bool { selectionRoots > 1 && !(elements.count == 2 && selectionRoots == 1) }
  var distribute: Bool { elements.count > 2 }
  var extraActions: Bool { hasSelection }
  var link: Bool { selectionRoots == 1 }

  static func transparent(_ c: String) -> Bool { c == "transparent" || c.isEmpty }

  /// Common value across the matching elements, the style default when none match,
  /// or nil when they disagree ("mixed").
  func value<T: Equatable>(_ applies: (Element) -> Bool, _ read: (Element) -> T, default def: T) -> T? {
    let matching = elements.filter(applies)
    guard let first = matching.first else { return def }
    let v = read(first)
    return matching.allSatisfy { read($0) == v } ? v : nil
  }

  var strokeColorValue: String? { value({ $0.type.hasStrokeColor }, { $0.strokeColor }, default: style.strokeColor) }
  var backgroundValue: String? { value({ $0.type.hasBackground }, { $0.backgroundColor }, default: style.backgroundColor) }
  var fillValue: String? { value({ $0.type.hasFillStyle }, { $0.fillStyle.rawValue }, default: style.fillStyle) }
  var widthValue: Double? { value({ $0.type.hasStrokeWidth }, { $0.strokeWidth }, default: style.strokeWidth) }
  var strokeStyleValue: String? { value({ $0.type.hasStrokeStyle }, { $0.strokeStyle.rawValue }, default: style.strokeStyle) }
  var roughnessValue: Double? { value({ $0.type.hasRoughness }, { $0.roughness }, default: style.roughness) }
  var roundnessValue: String? {
    value({ $0.type.canChangeRoundness }, { $0.roundness != nil ? "round" : "sharp" }, default: style.roundness)
  }
  var arrowTypeValue: String? {
    value({ $0.type == .arrow }, { $0.elbowed ? "elbow" : ($0.roundness != nil ? "round" : "sharp") }, default: style.arrowType)
  }
  var startArrowheadValue: String?? {
    let v = value({ $0.type == .arrow }, { $0.startArrowhead?.normalized.rawValue ?? "" }, default: style.startArrowhead ?? "")
    return v.map { $0.isEmpty ? nil : $0 }
  }
  var endArrowheadValue: String?? {
    let v = value({ $0.type == .arrow }, { $0.endArrowhead?.normalized.rawValue ?? "" }, default: style.endArrowhead ?? "")
    return v.map { $0.isEmpty ? nil : $0 }
  }
  var fontFamilyValue: Int? { value({ $0.isText }, { $0.fontFamily }, default: style.fontFamily) }
  var fontSizeValue: Double? { value({ $0.isText }, { $0.fontSize }, default: style.fontSize) }
  var textAlignValue: String? { value({ $0.isText }, { $0.textAlign.rawValue }, default: style.textAlign) }
  var verticalAlignValue: String? {
    value({ $0.isText && $0.containerId != nil }, { $0.verticalAlign.rawValue }, default: "middle")
  }
  var opacityValue: Double? { value({ _ in true }, { $0.opacity }, default: style.opacity) }
}

/// Writes for each property, matching the per-action `perform` in
/// actions/actionProperties.tsx. Everything goes through `EditorDocument.setStyle`
/// so it is one undo step and updates the style for new elements.
@MainActor
struct PanelWriter {
  let doc: EditorDocument

  func strokeColor(_ c: String) {
    doc.setStyle({ $0.strokeColor = c }, element: { if $0.type.hasStrokeColor { $0.strokeColor = c } }, labels: true)
  }
  func background(_ c: String) {
    doc.setStyle({ $0.backgroundColor = c }, element: { if $0.type.hasBackground { $0.backgroundColor = c } })
  }
  func fill(_ f: String) {
    doc.setStyle({ $0.fillStyle = f }, element: { if $0.type.hasFillStyle { $0.fillStyle = FillStyle(rawValue: f) } })
  }
  func strokeWidth(_ w: Double) {
    doc.setStyle({ $0.strokeWidth = w }, element: { if $0.type.hasStrokeWidth { $0.strokeWidth = w } })
  }
  func strokeStyle(_ s: String) {
    doc.setStyle({ $0.strokeStyle = s }, element: { if $0.type.hasStrokeStyle, let v = StrokeStyle(rawValue: s) { $0.strokeStyle = v } })
  }
  func roughness(_ r: Double) {
    doc.setStyle({ $0.roughness = r }, element: { if $0.type.hasRoughness { $0.roughness = r } })
  }
  func roundness(_ r: String) {
    doc.setStyle(
      { $0.roundness = r },
      element: {
        if $0.type.canChangeRoundness { $0.roundness = r == "round" ? Element.defaultRoundness(for: $0.type) : nil }
      })
  }
  func arrowType(_ t: String) {
    doc.setStyle(
      { $0.arrowType = t },
      element: { e in
        guard e.type == .arrow else { return }
        e.roundness = t == "round" ? .proportional : nil
        if t == "elbow", !e.points.isEmpty, let first = e.points.first, let last = e.points.last {
          let s = e.toScene(first), g = e.toScene(last)
          e.angle = 0
          e.elbowed = true
          e.setGlobalPoints(GrafixCore.Scene.elbowRoute([s, g]))
        } else {
          e.elbowed = false
        }
      })
  }
  func arrowhead(start: Bool, _ value: String?) {
    doc.setStyle(
      { if start { $0.startArrowhead = value } else { $0.endArrowhead = value } },
      element: { if $0.type == .arrow { if start { $0.startArrowhead = value.map(Arrowhead.init(rawValue:)) } else { $0.endArrowhead = value.map(Arrowhead.init(rawValue:)) } } })
  }
  func fontFamily(_ id: Int) {
    doc.setStyle(
      { $0.fontFamily = id },
      element: {
        guard $0.isText else { return }
        $0.fontFamily = id
        $0.lineHeight = FontFamily(rawValue: id)?.lineHeight ?? 1.25
        if $0.containerId == nil { $0.fitText() }
      }, labels: true)
  }
  func fontSize(_ s: Double) {
    doc.setStyle(
      { $0.fontSize = s },
      element: {
        guard $0.isText else { return }
        $0.fontSize = s
        if $0.containerId == nil { $0.fitText() }
      }, labels: true)
  }
  func textAlign(_ a: String) {
    doc.setStyle(
      { $0.textAlign = a },
      element: {
        guard $0.isText, let v = TextAlign(rawValue: a) else { return }
        $0.textAlign = v
      }, labels: true)
  }
  func verticalAlign(_ a: String) {
    doc.setStyle(
      { _ in },
      element: {
        guard $0.isText, $0.containerId != nil, let v = VerticalAlign(rawValue: a) else { return }
        $0.verticalAlign = v
      }, labels: true)
  }
  func opacity(_ o: Double) {
    doc.setStyle({ $0.opacity = o }, element: { $0.opacity = o }, labels: true, coalesce: "opacity")
  }
  func link(_ url: String?) {
    guard doc.hasSelection else { return }
    let ids = doc.selection
    let single = doc.singleSelection?.id
    doc.commit { scene in
      scene.updateEach(ids.filter { $0 == single }) { $0.link = (url?.isEmpty ?? true) ? nil : url }
    }
  }
}
