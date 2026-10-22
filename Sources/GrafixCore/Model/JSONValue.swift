import Foundation

/// Any JSON value. Used to preserve properties Grafix does not model, so a
/// scene written by Excalidraw round-trips without losing data.
public enum JSONValue: Codable, Equatable, Hashable, Sendable {
  case object([String: JSONValue])
  case array([JSONValue])
  case string(String)
  case number(Double)
  case bool(Bool)
  case null

  public init(from decoder: Decoder) throws {
    let value = try decoder.singleValueContainer()
    if value.decodeNil() {
      self = .null
    } else if let bool = try? value.decode(Bool.self) {
      self = .bool(bool)
    } else if let number = try? value.decode(Double.self) {
      self = .number(number)
    } else if let string = try? value.decode(String.self) {
      self = .string(string)
    } else if let array = try? value.decode([JSONValue].self) {
      self = .array(array)
    } else {
      self = .object(try value.decode([String: JSONValue].self))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var value = encoder.singleValueContainer()
    switch self {
    case .object(let object): try value.encode(object)
    case .array(let array): try value.encode(array)
    case .string(let string): try value.encode(string)
    case .number(let number):
      // JSON has no NaN/Infinity; write 0 like Excalidraw's restore would.
      guard number.isFinite else {
        try value.encode(0)
        return
      }
      // Whole numbers are written without ".0" so files stay Excalidraw-identical.
      if number == number.rounded(), abs(number) < 9e15 {
        try value.encode(Int64(number))
      } else {
        try value.encode(number)
      }
    case .bool(let bool): try value.encode(bool)
    case .null: try value.encodeNil()
    }
  }

  public var object: [String: JSONValue]? { if case .object(let v) = self { v } else { nil } }
  public var array: [JSONValue]? { if case .array(let v) = self { v } else { nil } }
  public var string: String? { if case .string(let v) = self { v } else { nil } }
  public var number: Double? { if case .number(let v) = self { v } else { nil } }
  public var bool: Bool? { if case .bool(let v) = self { v } else { nil } }
  public var isNull: Bool { self == .null }

  public subscript(key: String) -> JSONValue? { object?[key] }

  /// Parses JSON text. Throws on invalid input.
  public static func parse(_ text: String) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
  }

  public static func parse(_ data: Data) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: data)
  }

  /// Compact or pretty JSON text.
  public func serialized(pretty: Bool = false) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting =
      pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.sortedKeys, .withoutEscapingSlashes]
    return (try? String(decoding: encoder.encode(self), as: UTF8.self)) ?? "null"
  }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByFloatLiteral, ExpressibleByIntegerLiteral,
  ExpressibleByBooleanLiteral, ExpressibleByNilLiteral, ExpressibleByArrayLiteral,
  ExpressibleByDictionaryLiteral
{
  public init(stringLiteral value: String) { self = .string(value) }
  public init(floatLiteral value: Double) { self = .number(value) }
  public init(integerLiteral value: Int) { self = .number(Double(value)) }
  public init(booleanLiteral value: Bool) { self = .bool(value) }
  public init(nilLiteral: ()) { self = .null }
  public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
  public init(dictionaryLiteral elements: (String, JSONValue)...) {
    self = .object(Dictionary(elements, uniquingKeysWith: { _, b in b }))
  }
}
