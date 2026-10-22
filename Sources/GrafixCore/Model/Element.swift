import CoreGraphics
import Foundation

/// One Excalidraw element, typed.
///
/// Field names and meanings match Excalidraw's `ExcalidrawElement`
/// (excalidraw/packages/element/src/types.ts) so `.excalidraw` files round-trip.
/// Properties Grafix does not model are kept in `extra` and written back untouched.
///
/// Coordinates: `x`/`y` is the top-left of the unrotated bounding box in scene
/// space. `angle` is radians, clockwise, around the box centre. For linear
/// elements (`line`, `arrow`, `freedraw`) `points` are relative to `x`/`y`.
public struct Element: Identifiable, Equatable, Sendable {
  public var id: String
  public var type: ElementType
  public var x: Double
  public var y: Double
  public var width: Double
  public var height: Double
  public var angle: Double = 0
  public var strokeColor: String = "#1e1e1e"
  public var backgroundColor: String = "transparent"
  public var fillStyle: FillStyle = .solid
  public var strokeWidth: Double = 2
  public var strokeStyle: StrokeStyle = .solid
  public var roughness: Double = 1
  public var opacity: Double = 100
  public var roundness: Roundness? = nil
  public var seed: Int = Element.randomSeed()
  /// Incremented on every change. Used for caches and for merging external edits.
  public var version: Int = 1
  public var versionNonce: Int = Element.randomSeed()
  /// Fractional index giving z-order. Kept in sync with array order on save.
  public var index: String? = nil
  public var isDeleted: Bool = false
  /// Groups this element belongs to, deepest first.
  public var groupIds: [String] = []
  public var frameId: String? = nil
  public var boundElements: [BoundElement]? = nil
  /// Last update, epoch milliseconds.
  public var updated: Double = Element.now()
  public var created: Double? = Element.now()
  public var link: String? = nil
  public var locked: Bool = false
  public var customData: [String: JSONValue]? = nil

  // MARK: text
  public var text: String = ""
  public var originalText: String = ""
  public var fontSize: Double = 20
  public var fontFamily: Int = FontFamily.excalifont.rawValue
  public var textAlign: TextAlign = .left
  public var verticalAlign: VerticalAlign = .top
  /// Shape or arrow this text is the label of.
  public var containerId: String? = nil
  public var autoResize: Bool = true
  /// Unitless; multiply by `fontSize` for pixels.
  public var lineHeight: Double = 1.25

  // MARK: linear (line, arrow) and freedraw
  public var points: [CGPoint] = []
  public var startBinding: PointBinding? = nil
  public var endBinding: PointBinding? = nil
  public var startArrowhead: Arrowhead? = nil
  public var endArrowhead: Arrowhead? = nil
  /// Elbow (orthogonal) arrow.
  public var elbowed: Bool = false
  /// A closed line that can be filled.
  public var polygon: Bool = false
  public var pressures: [Double] = []
  public var simulatePressure: Bool = true

  // MARK: image
  public var fileId: String? = nil
  public var imageStatus: String = "saved"
  public var scale: [Double] = [1, 1]
  public var crop: JSONValue? = nil

  // MARK: frame
  public var name: String? = nil

  /// Unmodelled keys, written back as-is.
  public var extra: [String: JSONValue] = [:]

  public init(
    id: String = Element.newID(), type: ElementType, x: Double, y: Double, width: Double,
    height: Double
  ) {
    self.id = id
    self.type = type
    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }

  // MARK: helpers

  public static func newID() -> String {
    // Excalidraw uses 21-char nanoid-like ids; any unique string works.
    let alphabet = Array("useandom-26T198340PX75pxJACKVERYMINDBUSHWOLF_GQZbfghjklqvwyzrict")
    var rng = SystemRandomNumberGenerator()
    return String((0..<21).map { _ in alphabet[Int(rng.next() % UInt64(alphabet.count))] })
  }

  public static func randomSeed() -> Int { Int.random(in: 1..<(1 << 31)) }
  public static func now() -> Double { (Date().timeIntervalSince1970 * 1000).rounded() }

  /// Call after any change so caches and merges see it.
  public mutating func bump() {
    version += 1
    versionNonce = Element.randomSeed()
    updated = Element.now()
  }

  public var isLinear: Bool { type == .line || type == .arrow }
  public var isText: Bool { type == .text }
  public var isFrame: Bool { type == .frame || type == .magicframe }
  /// Shapes that can hold a text label and be arrow targets.
  public var canHaveLabel: Bool {
    [.rectangle, .ellipse, .diamond, .arrow, .stickynote].contains(type)
  }
  public var isBindable: Bool {
    [.rectangle, .ellipse, .diamond, .text, .image, .frame, .magicframe, .embeddable, .iframe,
     .stickynote].contains(type)
  }
  /// The element's id plus any bound text and arrows, in `boundElements`.
  public var boundTextID: String? { boundElements?.first(where: { $0.type == "text" })?.id }

  public var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
  public var center: CGPoint { CGPoint(x: x + width / 2, y: y + height / 2) }

  public var presenterNotes: String? {
    get { customData?["presenterNotes"]?.string }
    set {
      var data = customData ?? [:]
      data["presenterNotes"] = newValue.map(JSONValue.string)
      customData = data
    }
  }
  /// Excalidraw+ slide order (0-based) stored on frames.
  public var slidesOrder: Double? {
    get { customData?["slidesOrder"]?.number }
    set {
      var data = customData ?? [:]
      data["slidesOrder"] = newValue.map(JSONValue.number)
      customData = data
    }
  }
}

// MARK: - Enumerations (string-backed so unknown values survive)

public struct ElementType: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
  public var rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }
  public init(stringLiteral value: String) { rawValue = value }
  public static let selection: ElementType = "selection"
  public static let rectangle: ElementType = "rectangle"
  public static let diamond: ElementType = "diamond"
  public static let ellipse: ElementType = "ellipse"
  public static let arrow: ElementType = "arrow"
  public static let line: ElementType = "line"
  public static let freedraw: ElementType = "freedraw"
  public static let text: ElementType = "text"
  public static let image: ElementType = "image"
  public static let frame: ElementType = "frame"
  public static let magicframe: ElementType = "magicframe"
  public static let embeddable: ElementType = "embeddable"
  public static let iframe: ElementType = "iframe"
  public static let stickynote: ElementType = "stickynote"
}

public struct FillStyle: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
  public var rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }
  public init(stringLiteral value: String) { rawValue = value }
  public static let hachure: FillStyle = "hachure"
  public static let crossHatch: FillStyle = "cross-hatch"
  public static let solid: FillStyle = "solid"
  public static let zigzag: FillStyle = "zigzag"
}

public enum StrokeStyle: String, Sendable, CaseIterable {
  case solid, dashed, dotted
}

public enum TextAlign: String, Sendable, CaseIterable {
  case left, center, right
}

public enum VerticalAlign: String, Sendable, CaseIterable {
  case top, middle, bottom
}

public struct Arrowhead: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
  public var rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }
  public init(stringLiteral value: String) { rawValue = value }
  public static let arrow: Arrowhead = "arrow"
  public static let bar: Arrowhead = "bar"
  public static let circle: Arrowhead = "circle"
  public static let circleOutline: Arrowhead = "circle_outline"
  public static let triangle: Arrowhead = "triangle"
  public static let triangleOutline: Arrowhead = "triangle_outline"
  public static let diamond: Arrowhead = "diamond"
  public static let diamondOutline: Arrowhead = "diamond_outline"
  public static let cardinalityOne: Arrowhead = "cardinality_one"
  public static let cardinalityMany: Arrowhead = "cardinality_many"
  public static let cardinalityOneOrMany: Arrowhead = "cardinality_one_or_many"
  public static let cardinalityExactlyOne: Arrowhead = "cardinality_exactly_one"
  public static let cardinalityZeroOrOne: Arrowhead = "cardinality_zero_or_one"
  public static let cardinalityZeroOrMany: Arrowhead = "cardinality_zero_or_many"

  /// Legacy names are mapped the way Excalidraw's restore.ts maps them.
  public var normalized: Arrowhead {
    switch rawValue {
    case "dot": .circle
    case "crowfoot_one": .cardinalityOne
    case "crowfoot_many": .cardinalityMany
    case "crowfoot_one_or_many": .cardinalityOneOrMany
    default: self
    }
  }
}

/// Excalidraw font family ids (common/src/constants.ts FONT_FAMILY).
public enum FontFamily: Int, Sendable, CaseIterable {
  case virgil = 1, helvetica = 2, cascadia = 3, excalifont = 5, nunito = 6, lilitaOne = 7,
    comicShanns = 8, liberationSans = 9, assistant = 10

  /// Line height Excalidraw uses for new text in this family (font-metadata.ts).
  public var lineHeight: Double {
    switch self {
    case .lilitaOne, .helvetica, .liberationSans: 1.15
    case .cascadia: 1.2
    default: 1.25
    }
  }

  /// Ascender/descender in em units, from Excalidraw's FONT_METADATA.
  public var metrics: (unitsPerEm: Double, ascender: Double, descender: Double) {
    switch self {
    case .excalifont, .virgil: (1000, 886, -374)
    case .nunito: (1000, 1011, -353)
    case .lilitaOne: (1000, 923, -220)
    case .comicShanns: (1000, 750, -250)
    case .helvetica: (2048, 1577, -471)
    case .cascadia: (2048, 1900, -480)
    case .liberationSans: (2048, 1854, -434)
    case .assistant: (2048, 1021, -287)
    }
  }
}

public struct Roundness: Equatable, Sendable {
  /// 1 legacy, 2 proportional, 3 adaptive (Excalidraw ROUNDNESS).
  public var type: Int
  public var value: Double?
  public init(type: Int, value: Double? = nil) {
    self.type = type
    self.value = value
  }
  public static let proportional = Roundness(type: 2)
  public static let adaptive = Roundness(type: 3)
}

public struct BoundElement: Equatable, Sendable {
  public var id: String
  /// "arrow" or "text".
  public var type: String
  public init(id: String, type: String) {
    self.id = id
    self.type = type
  }
}

/// Where an arrow end attaches to a shape.
public struct PointBinding: Equatable, Sendable {
  public var elementId: String
  /// Ratio inside the bound element's box, [0..1, 0..1]. [0.5, 0.5] is the centre.
  public var fixedPoint: CGPoint?
  /// "inside", "orbit" or "skip".
  public var mode: String?
  /// Legacy fields from older files; preserved.
  public var focus: Double?
  public var gap: Double?
  public init(
    elementId: String, fixedPoint: CGPoint? = nil, mode: String? = "orbit", focus: Double? = nil,
    gap: Double? = nil
  ) {
    self.elementId = elementId
    self.fixedPoint = fixedPoint
    self.mode = mode
    self.focus = focus
    self.gap = gap
  }
}
