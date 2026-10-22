import CoreGraphics
import Foundation

/// The style applied to newly drawn elements (Excalidraw's `currentItem*` app state).
public struct ItemStyle: Equatable, Sendable, Codable {
  public var strokeColor = "#1e1e1e"
  public var backgroundColor = "transparent"
  public var fillStyle = "solid"
  public var strokeWidth: Double = 2
  public var strokeStyle = "solid"
  public var roughness: Double = 1
  public var opacity: Double = 100
  /// "round" or "sharp".
  public var roundness = "round"
  /// "round" (curved), "sharp" (straight) or "elbow".
  public var arrowType = "round"
  public var startArrowhead: String? = nil
  public var endArrowhead: String? = "arrow"
  public var fontFamily = 5
  public var fontSize: Double = 20
  public var textAlign = "left"

  public init() {}
}

extension Element {
  /// Default roundness for a type when edges are "round" (getDefaultRoundnessTypeForElement).
  public static func defaultRoundness(for type: ElementType) -> Roundness? {
    switch type {
    case .rectangle, .embeddable, .iframe, .image: .adaptive
    case .line, .arrow, .diamond, .stickynote: .proportional
    default: nil
    }
  }

  /// A new element with Excalidraw's defaults and the given style.
  public static func make(
    _ type: ElementType, x: Double, y: Double, width: Double = 0, height: Double = 0,
    style: ItemStyle = ItemStyle()
  ) -> Element {
    var e = Element(type: type, x: x, y: y, width: width, height: height)
    e.strokeColor = style.strokeColor
    e.backgroundColor = style.backgroundColor
    e.fillStyle = FillStyle(rawValue: style.fillStyle)
    e.strokeWidth = style.strokeWidth
    e.strokeStyle = StrokeStyle(rawValue: style.strokeStyle) ?? .solid
    e.roughness = style.roughness
    e.opacity = style.opacity
    e.roundness = style.roundness == "round" ? defaultRoundness(for: type) : nil
    switch type {
    case .arrow:
      e.startArrowhead = style.startArrowhead.map { Arrowhead(rawValue: $0) }
      e.endArrowhead = style.endArrowhead.map { Arrowhead(rawValue: $0) }
      e.elbowed = style.arrowType == "elbow"
      e.roundness = style.arrowType == "round" ? .proportional : nil
      e.points = [.zero, CGPoint(x: width, y: height)]
    case .line:
      e.points = [.zero, CGPoint(x: width, y: height)]
    case .freedraw:
      e.points = []
      e.roundness = nil
    case .text:
      e.fontFamily = style.fontFamily
      e.fontSize = style.fontSize
      e.textAlign = TextAlign(rawValue: style.textAlign) ?? .left
      e.lineHeight = FontFamily(rawValue: style.fontFamily)?.lineHeight ?? 1.25
      e.backgroundColor = "transparent"
      e.roundness = nil
    case .frame, .magicframe:
      // FRAME_STYLE
      e.strokeColor = "#bbb"
      e.strokeWidth = 2
      e.strokeStyle = .solid
      e.fillStyle = .solid
      e.roughness = 0
      e.roundness = nil
      e.backgroundColor = "transparent"
      e.name = nil
    case .image:
      e.backgroundColor = "transparent"
      e.strokeColor = "transparent"
    default:
      break
    }
    return e
  }

  /// A text element sized to its content.
  public static func makeText(
    _ text: String, x: Double, y: Double, style: ItemStyle = ItemStyle()
  ) -> Element {
    var e = make(.text, x: x, y: y, style: style)
    e.text = text
    e.originalText = text
    e.fitText()
    return e
  }
}

extension Scene {
  /// Adds `label` text inside (or along) `containerID`, replacing any existing label.
  @discardableResult
  public mutating func setLabel(
    _ label: String, on containerID: String, fontSize: Double? = nil, fontFamily: Int? = nil,
    strokeColor: String? = nil, textAlign: TextAlign = .center, verticalAlign: VerticalAlign = .middle
  ) -> String? {
    guard let ci = indexOf(containerID) else { return nil }
    if let existing = elements[ci].boundTextID, let ti = indexOf(existing) {
      elements[ti].originalText = label
      elements[ti].text = label
      if let fontSize { elements[ti].fontSize = fontSize }
      if let fontFamily {
        elements[ti].fontFamily = fontFamily
        elements[ti].lineHeight = FontFamily(rawValue: fontFamily)?.lineHeight ?? 1.25
      }
      if let strokeColor { elements[ti].strokeColor = strokeColor }
      if label.isEmpty {
        // Clearing a label deletes it and unlinks it from the container (Excalidraw does the same).
        elements[ti].isDeleted = true
        elements[ti].bump()
        elements[ci].boundElements?.removeAll { $0.id == existing }
        if elements[ci].boundElements?.isEmpty == true { elements[ci].boundElements = nil }
        elements[ci].bump()
        return nil
      }
      elements[ti].isDeleted = false
      elements[ti].bump()
      layoutLabel(of: containerID)
      return existing
    }
    guard !label.isEmpty else { return nil }
    let container = elements[ci]
    var style = ItemStyle()
    style.fontSize = fontSize ?? 20
    style.fontFamily = fontFamily ?? 5
    style.strokeColor = strokeColor ?? container.strokeColor
    var text = Element.make(.text, x: container.x, y: container.y, style: style)
    text.text = label
    text.originalText = label
    text.textAlign = textAlign
    text.verticalAlign = verticalAlign
    text.containerId = containerID
    text.frameId = container.frameId
    text.groupIds = container.groupIds
    text.opacity = container.opacity
    var bound = container.boundElements ?? []
    bound.append(BoundElement(id: text.id, type: "text"))
    elements[ci].boundElements = bound
    elements[ci].bump()
    elements.insert(text, at: ci + 1)
    layoutLabel(of: containerID)
    return text.id
  }
}
