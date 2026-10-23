import Foundation
import GrafixCore

/// An error whose message is shown to the agent as the tool result (isError = true).
struct ToolError: Error, LocalizedError {
  let message: String
  init(_ message: String) { self.message = message }
  var errorDescription: String? { message }
}

/// What a tool returns: MCP content blocks.
struct ToolResult {
  var content: [JSONValue]
  var isError = false

  static func text(_ text: String) -> ToolResult {
    ToolResult(content: [.object(["type": "text", "text": .string(text)])])
  }

  /// Pretty JSON as a text block.
  static func json(_ value: JSONValue) -> ToolResult { .text(value.serialized(pretty: true)) }

  static func image(png: Data) -> ToolResult {
    ToolResult(content: [
      .object(["type": "image", "data": .string(png.base64EncodedString()), "mimeType": "image/png"])
    ])
  }

  static func error(_ message: String) -> ToolResult {
    var r = ToolResult.text(message)
    r.isError = true
    return r
  }
}

/// Typed access to a tool call's arguments with agent-friendly errors.
struct Args {
  let values: [String: JSONValue]

  func string(_ key: String) throws -> String? {
    guard let v = values[key], !v.isNull else { return nil }
    guard let s = v.string else { throw ToolError("'\(key)' must be a string.") }
    return s
  }

  func require(_ key: String) throws -> String {
    guard let s = try string(key), !s.isEmpty else { throw ToolError("Missing required argument '\(key)'.") }
    return s
  }

  func number(_ key: String) throws -> Double? {
    guard let v = values[key], !v.isNull else { return nil }
    if let n = v.number { return n }
    if let s = v.string, let n = Double(s) { return n }
    throw ToolError("'\(key)' must be a number.")
  }

  func bool(_ key: String) -> Bool? { values[key]?.bool }

  func stringList(_ key: String) throws -> [String]? {
    guard let v = values[key], !v.isNull else { return nil }
    let list = try Args.decodeList(v, key: key)
    return try list.map {
      guard let s = $0.string else { throw ToolError("'\(key)' must be an array of strings.") }
      return s
    }
  }

  /// Array of JSON objects given either as a real array or as a JSON string.
  func objectList(_ key: String) throws -> [[String: JSONValue]]? {
    guard let v = values[key], !v.isNull else { return nil }
    let list = try Args.decodeList(v, key: key)
    return try list.enumerated().map { i, item in
      guard let o = item.object else { throw ToolError("'\(key)[\(i)]' must be a JSON object.") }
      return o
    }
  }

  /// Accepts an array, a single object (wrapped), or a string containing JSON of either.
  static func decodeList(_ v: JSONValue, key: String) throws -> [JSONValue] {
    var value = v
    if let s = v.string {
      let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.isEmpty { return [] }
      do { value = try JSONValue.parse(trimmed) } catch {
        throw ToolError("'\(key)' is not valid JSON (\(error.localizedDescription)). Pass a JSON array, e.g. [{\"type\":\"rectangle\",\"x\":0,\"y\":0,\"width\":160,\"height\":85}].")
      }
    }
    if let a = value.array { return a }
    if value.object != nil { return [value] }
    throw ToolError("'\(key)' must be a JSON array.")
  }
}

// MARK: - Schema builders

/// A JSON Schema property.
func prop(_ type: String, _ description: String, extra: [String: JSONValue] = [:]) -> JSONValue {
  var o: [String: JSONValue] = ["type": .string(type), "description": .string(description)]
  for (k, v) in extra { o[k] = v }
  return .object(o)
}

/// Property accepting a JSON array given as an array or as a JSON string (Excalidraw+ style).
func jsonArrayProp(_ description: String) -> JSONValue {
  .object([
    "type": .array(["array", "string"]),
    "description": .string(description + " Either a JSON array or a string containing a JSON array."),
    "items": .object([:]),
  ])
}

func schema(_ properties: [String: JSONValue] = [:], required: [String] = []) -> JSONValue {
  .object([
    "type": "object", "properties": .object(properties),
    "required": .array(required.map(JSONValue.string)), "additionalProperties": false,
  ])
}

// MARK: - Tool definition

struct Tool {
  let name: String
  let description: String
  let inputSchema: JSONValue
  let run: (Args, Workspace) throws -> ToolResult

  var listing: JSONValue {
    .object(["name": .string(name), "description": .string(description), "inputSchema": inputSchema])
  }
}

// MARK: - Shared helpers

extension JSONValue {
  static func num(_ d: Double) -> JSONValue { .number((d * 100).rounded() / 100) }
  static func rect(_ r: CGRect) -> JSONValue {
    .object(["x": .num(r.minX), "y": .num(r.minY), "width": .num(r.width), "height": .num(r.height)])
  }
}

func iso(_ date: Date?) -> JSONValue { date.map { .string($0.formatted(.iso8601)) } ?? .null }

extension Workspace {
  /// Throws an actionable error when the scene does not exist.
  func requireScene(_ id: String) throws -> SceneInfo {
    do { return try info(id) } catch {
      if error is WorkspaceError, (error as? WorkspaceError).map({ if case .invalidID = $0 { return true } else { return false } }) == true {
        throw ToolError("Invalid sceneId '\(id)'. Scene ids look like 'Personal/My scene'. Call list_scenes to see ids.")
      }
      throw ToolError("No scene '\(id)'. Call list_scenes to see ids.")
    }
  }

  /// Loads a scene with an actionable error.
  func loadScene(_ id: String) throws -> Scene {
    _ = try requireScene(id)
    do { return try load(id) } catch { throw ToolError("Could not read scene '\(id)': \(error.localizedDescription)") }
  }

  /// Load-change-save under the workspace flock, with a friendly not-found error.
  func edit<T>(_ id: String, _ change: (inout Scene) throws -> T) throws -> (Scene, T) {
    _ = try requireScene(id)
    return try modify(id, change)
  }
}
