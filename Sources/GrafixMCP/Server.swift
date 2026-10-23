import Foundation
import GrafixCore

/// Newline-delimited JSON-RPC 2.0 over stdio implementing the MCP subset Grafix needs.
/// stdout carries ONLY protocol messages; diagnostics go to stderr.
struct Server {
  static let supportedVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]

  let workspace: Workspace
  let tools: [Tool]

  init(workspace: Workspace) {
    self.workspace = workspace
    self.tools = allTools()
  }

  /// Reads requests until stdin closes.
  func serve() {
    while let line = readLine(strippingNewline: true) {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.isEmpty { continue }
      if let response = handle(line: trimmed) { write(response) }
    }
  }

  func handle(line: String) -> JSONValue? {
    guard let message = try? JSONValue.parse(line) else {
      return errorResponse(id: .null, code: -32700, message: "Parse error")
    }
    if let batch = message.array {
      let responses = batch.compactMap { handle(message: $0) }
      return responses.isEmpty ? nil : .array(responses)
    }
    return handle(message: message)
  }

  func handle(message: JSONValue) -> JSONValue? {
    guard let object = message.object, let method = object["method"]?.string else {
      return errorResponse(id: message["id"] ?? .null, code: -32600, message: "Invalid request")
    }
    // Notifications carry no id and never get a response.
    guard let id = object["id"] else { return nil }
    let params = object["params"]?.object ?? [:]
    switch method {
    case "initialize": return result(id, initialize(params))
    case "ping": return result(id, .object([:]))
    case "tools/list": return result(id, .object(["tools": .array(tools.map(\.listing))]))
    case "tools/call": return result(id, callTool(params))
    default: return errorResponse(id: id, code: -32601, message: "Method not found: \(method)")
    }
  }

  func initialize(_ params: [String: JSONValue]) -> JSONValue {
    let requested = params["protocolVersion"]?.string ?? ""
    let version = Server.supportedVersions.contains(requested) ? requested : Server.supportedVersions[0]
    return .object([
      "protocolVersion": .string(version),
      "capabilities": .object(["tools": .object(["listChanged": false])]),
      "serverInfo": .object(["name": "grafix-mcp", "version": "0.2.0"]),
      "instructions": .string(Guides.serverInstructions),
    ])
  }

  func callTool(_ params: [String: JSONValue]) -> JSONValue {
    guard let name = params["name"]?.string, let tool = tools.first(where: { $0.name == name }) else {
      let known = tools.map(\.name).joined(separator: ", ")
      return resultJSON(.error("Unknown tool '\(params["name"]?.string ?? "")'. Available tools: \(known)."))
    }
    let args = Args(values: params["arguments"]?.object ?? [:])
    do {
      return resultJSON(try tool.run(args, workspace))
    } catch let error as ToolError {
      return resultJSON(.error(error.message))
    } catch {
      return resultJSON(.error(error.localizedDescription))
    }
  }

  // MARK: - Wire format

  func resultJSON(_ r: ToolResult) -> JSONValue {
    var o: [String: JSONValue] = ["content": .array(r.content)]
    if r.isError { o["isError"] = true }
    return .object(o)
  }

  func result(_ id: JSONValue, _ value: JSONValue) -> JSONValue {
    .object(["jsonrpc": "2.0", "id": id, "result": value])
  }

  func errorResponse(id: JSONValue, code: Int, message: String) -> JSONValue {
    .object(["jsonrpc": "2.0", "id": id, "error": .object(["code": .number(Double(code)), "message": .string(message)])])
  }

  func write(_ value: JSONValue) {
    var data = Data(value.serialized().utf8)
    data.append(0x0A)
    FileHandle.standardOutput.write(data)
  }
}

func log(_ text: String) {
  FileHandle.standardError.write(Data((text + "\n").utf8))
}
