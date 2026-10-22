import Foundation
import GrafixCore

// stdout is reserved for newline-delimited MCP JSON-RPC messages.
struct RPCFailure: Error {
  let code: Int
  let message: String
}

func object(_ value: JSONValue?) -> [String: JSONValue] { value?.objectValue ?? [:] }
func string(_ value: JSONValue?) -> String? {
  guard case .string(let value) = value else { return nil }
  return value
}
func required(_ arguments: [String: JSONValue], _ key: String) throws -> String {
  guard let value = string(arguments[key]), !value.isEmpty else {
    throw RPCFailure(code: -32602, message: "Missing or invalid \(key)")
  }
  return value
}
func revision(_ scene: SceneDocument) throws -> String {
  scene.revision
}
func snapshot(_ scene: SceneDocument) throws -> JSONValue {
  .object(["revision": .string(try revision(scene)), "scene": .object(scene.root)])
}
func schema(_ properties: [String: JSONValue], required: [String]) -> JSONValue {
  .object([
    "type": .string("object"), "properties": .object(properties),
    "required": .array(required.map(JSONValue.string)), "additionalProperties": .bool(false),
  ])
}
let nameProperty: JSONValue = .object([
  "type": .string("string"),
  "description": .string("Drawing filename in the Grafix library, ending in .excalidraw"),
])
let tools: JSONValue = .array([
  .object([
    "name": .string("list_drawings"),
    "description": .string("List local drawings in the Grafix library."),
    "inputSchema": schema([:], required: []),
  ]),
  .object([
    "name": .string("read_scene"),
    "description": .string(
      "Read the full lossless scene and its revision. Read before editing; unknown properties are preserved."
    ), "inputSchema": schema(["name": nameProperty], required: ["name"]),
  ]),
  .object([
    "name": .string("create_scene"),
    "description": .string("Create a new drawing. Refuses to replace an existing drawing."),
    "inputSchema": schema(
      [
        "name": nameProperty,
        "scene": .object([
          "type": .string("object"),
          "description": .string("Optional Excalidraw scene; omit for a blank drawing"),
        ]),
      ], required: ["name"]),
  ]),
  .object([
    "name": .string("patch_elements"),
    "description": .string(
      "Atomically merge properties into elements by ID, append new elements, or mark elements deleted. Requires the latest read_scene revision. File edits reload in the app but do not share its undo history yet."
    ),
    "inputSchema": schema(
      [
        "name": nameProperty,
        "expectedRevision": .object(["type": .string("string")]),
        "patches": .object([
          "type": .string("array"),
          "items": .object([
            "type": .string("object"), "required": .array([.string("id")]),
            "properties": .object(["id": .object(["type": .string("string")])]),
            "additionalProperties": .bool(true),
          ]),
          "description": .string(
            "Each object needs a nonempty id. Existing properties are merged; new IDs require type, x, y, width, height. To delete, set isDeleted=true."
          ),
        ]),
      ], required: ["name", "expectedRevision", "patches"]),
  ]),
])

func callTool(_ name: String, arguments: [String: JSONValue], store: SceneStore) throws -> JSONValue
{
  switch name {
  case "list_drawings":
    return .array(try store.list().map { .string($0.lastPathComponent) })
  case "read_scene": return try snapshot(store.load(name: required(arguments, "name")))
  case "create_scene":
    let name = try required(arguments, "name")
    let existing = try store.list()
    guard
      !existing.contains(where: {
        $0.standardizedFileURL == storeDirectory.appendingPathComponent(name).standardizedFileURL
      })
    else {
      throw RPCFailure(code: -32602, message: "Drawing already exists; read and patch it instead")
    }
    var scene = SceneDocument()
    if let supplied = arguments["scene"] {
      guard supplied.objectValue != nil else {
        throw RPCFailure(code: -32602, message: "scene must be an object")
      }
      scene = try SceneDocument(data: JSONEncoder().encode(supplied)).copyForNewFile()
    }
    return try snapshot(store.save(scene, name: name))
  case "patch_elements":
    let name = try required(arguments, "name")
    var scene = try store.load(name: name)
    guard try revision(scene) == required(arguments, "expectedRevision") else {
      throw RPCFailure(
        code: -32602, message: "Drawing changed. Read it again before applying patches.")
    }
    guard case .array(let patches) = arguments["patches"] else {
      throw RPCFailure(code: -32602, message: "patches must be an array")
    }
    var elements = scene.elements
    for patch in patches {
      guard let properties = patch.objectValue else {
        throw RPCFailure(code: -32602, message: "Every patch must be an object")
      }
      let id = try required(properties, "id")
      if let index = elements.firstIndex(where: { string($0["id"]) == id }) {
        elements[index].merge(properties) { _, new in new }
      } else {
        guard string(properties["type"]) != nil,
          ["x", "y", "width", "height"].allSatisfy({
            if case .number = properties[$0] { return true }
            return false
          })
        else {
          throw RPCFailure(
            code: -32602, message: "New elements require type and numeric x, y, width, height")
        }
        elements.append(properties)
      }
    }
    scene.elements = elements
    return try snapshot(store.save(scene, name: name))
  default: throw RPCFailure(code: -32602, message: "Unknown tool: \(name)")
  }
}

var arguments = Array(CommandLine.arguments.dropFirst())
let storeDirectory: URL
if arguments.isEmpty {
  storeDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("Grafix/Personal", isDirectory: true)
} else if arguments.count == 2, arguments[0] == "--directory" {
  storeDirectory = URL(
    fileURLWithPath: NSString(string: arguments[1]).expandingTildeInPath, isDirectory: true)
} else {
  FileHandle.standardError.write(Data("Usage: grafix-mcp [--directory PATH]\n".utf8))
  exit(2)
}
let store = SceneStore(directory: storeDirectory)
let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
while let line = readLine() {
  var id: JSONValue = .null
  var hasID = true
  var response: JSONValue
  do {
    guard let data = line.data(using: .utf8),
      let request = try JSONDecoder().decode(JSONValue.self, from: data).objectValue
    else {
      throw RPCFailure(code: -32700, message: "Invalid JSON object")
    }
    hasID = request["id"] != nil
    id = request["id"] ?? .null
    guard string(request["jsonrpc"]) == "2.0", let method = string(request["method"]) else {
      throw RPCFailure(code: -32600, message: "Invalid JSON-RPC request")
    }
    if !hasID { continue }
    switch id {
    case .string, .number: break
    default:
      id = .null
      throw RPCFailure(code: -32600, message: "Request id must be a string or number")
    }
    if let supplied = request["params"], supplied.objectValue == nil {
      throw RPCFailure(code: -32602, message: "params must be an object")
    }
    let params = object(request["params"])
    let result: JSONValue
    switch method {
    case "initialize":
      let supported = ["2024-11-05", "2025-03-26", "2025-06-18"]
      let requested = string(params["protocolVersion"]) ?? ""
      result = .object([
        "protocolVersion": .string(supported.contains(requested) ? requested : "2025-06-18"),
        "capabilities": .object(["tools": .object([:])]),
        "serverInfo": .object(["name": .string("grafix"), "version": .string("0.1.0")]),
        "instructions": .string(
          "Local file-based drawing tools. Read before patching. Native app undo is not shared with file edits."
        ),
      ])
    case "ping": result = .object([:])
    case "tools/list": result = .object(["tools": tools])
    case "tools/call":
      do {
        if let supplied = params["arguments"], supplied.objectValue == nil {
          throw RPCFailure(code: -32602, message: "Tool arguments must be an object")
        }
        let value = try callTool(
          required(params, "name"), arguments: object(params["arguments"]), store: store)
        let text = String(decoding: try encoder.encode(value), as: UTF8.self)
        result = .object([
          "content": .array([.object(["type": .string("text"), "text": .string(text)])]),
          "isError": .bool(false),
        ])
      } catch {
        result = .object([
          "content": .array([
            .object([
              "type": .string("text"),
              "text": .string((error as? RPCFailure)?.message ?? error.localizedDescription),
            ])
          ]), "isError": .bool(true),
        ])
      }
    default: throw RPCFailure(code: -32601, message: "Method not found: \(method)")
    }
    response = .object(["jsonrpc": .string("2.0"), "id": id, "result": result])
  } catch {
    let failure = error as? RPCFailure ?? RPCFailure(code: -32700, message: "Invalid JSON")
    response = .object([
      "jsonrpc": .string("2.0"), "id": id,
      "error": .object(["code": .number(Double(failure.code)), "message": .string(failure.message)]
      ),
    ])
  }
  if hasID, let data = try? encoder.encode(response) {
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([10]))
  }
}
