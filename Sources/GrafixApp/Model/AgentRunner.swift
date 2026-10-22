import AppKit
import Foundation
import Observation

/// One row in the chat transcript.
struct ChatItem: Identifiable {
  enum Kind {
    case user(String)
    case assistant(String)
    case tool(name: String, toolID: String, status: ToolStatus, image: NSImage?)
    case error(String)
  }
  enum ToolStatus { case running, done, failed }
  let id = UUID()
  var kind: Kind
}

/// A decoded line of `claude --output-format stream-json`. Sendable so it can hop off the reader thread.
enum AgentEvent: Sendable {
  case session(String)
  case text(String)
  case toolUse(id: String, name: String)
  case toolResult(id: String, failed: Bool, image: Data?)
  case result(failed: Bool, message: String?)

  /// Parses one JSON line; returns every event it carries.
  static func parse(line: String) -> [AgentEvent] {
    guard let data = line.data(using: .utf8),
      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let type = obj["type"] as? String
    else { return [] }
    var out: [AgentEvent] = []
    if let sid = obj["session_id"] as? String, type == "system" || type == "result" { out.append(.session(sid)) }
    switch type {
    case "assistant", "user":
      let message = obj["message"] as? [String: Any]
      let blocks = message?["content"] as? [[String: Any]] ?? []
      for block in blocks {
        switch block["type"] as? String {
        case "text":
          if type == "assistant", let t = block["text"] as? String, !t.isEmpty { out.append(.text(t)) }
        case "tool_use":
          out.append(.toolUse(id: block["id"] as? String ?? "", name: block["name"] as? String ?? "tool"))
        case "tool_result":
          var image: Data?
          if let parts = block["content"] as? [[String: Any]] {
            for part in parts where part["type"] as? String == "image" {
              if let src = part["source"] as? [String: Any], let b64 = src["data"] as? String {
                image = Data(base64Encoded: b64)
              }
            }
          }
          out.append(.toolResult(id: block["tool_use_id"] as? String ?? "", failed: block["is_error"] as? Bool ?? false, image: image))
        default: break
        }
      }
    case "result":
      let failed = obj["is_error"] as? Bool ?? false
      out.append(.result(failed: failed, message: obj["result"] as? String))
    default: break
    }
    return out
  }
}

/// Runs an installed agent CLI (Claude Code) with Grafix's MCP server attached, so the
/// agent edits the open scene through MCP tools while the app merges the file changes live.
@MainActor @Observable
final class AgentRunner {
  var items: [ChatItem] = []
  var running = false
  /// Display name of the detected CLI, nil when none is installed.
  var cliName: String?
  private(set) var detected = false

  @ObservationIgnored private var claudePath: String?
  @ObservationIgnored private var sessionID: String?
  @ObservationIgnored private var process: Process?
  @ObservationIgnored private var stopped = false
  @ObservationIgnored private var gotText = false
  /// Index of the assistant text row currently being appended to.
  @ObservationIgnored private var openTextIndex: Int?

  // MARK: - Detection

  /// Finds `claude` through the user's login shell PATH (once). Falls back to common locations.
  func detect() async {
    guard !detected else { return }
    let found = await Task.detached { () -> String? in
      let p = Process()
      p.executableURL = URL(fileURLWithPath: "/bin/zsh")
      p.arguments = ["-lc", "command -v claude"]
      let pipe = Pipe()
      p.standardOutput = pipe
      p.standardError = FileHandle.nullDevice
      do { try p.run() } catch { return nil }
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      p.waitUntilExit()
      let path = String(decoding: data, as: UTF8.self).split(separator: "\n").last.map(String.init)?
        .trimmingCharacters(in: .whitespaces)
      if let path, FileManager.default.isExecutableFile(atPath: path) { return path }
      let home = NSHomeDirectory()
      return ["\(home)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }
    }.value
    claudePath = found
    cliName = found == nil ? nil : "Claude Code"
    detected = true
  }

  // MARK: - Files

  static var supportDir: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Grafix", isDirectory: true)
  }

  /// Path of the grafix-mcp binary: inside the app bundle if present, else next to the executable.
  static func mcpBinary() -> URL {
    let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/grafix-mcp")
    if FileManager.default.isExecutableFile(atPath: bundled.path) { return bundled }
    let exe = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
    return exe.deletingLastPathComponent().appendingPathComponent("grafix-mcp")
  }

  /// Writes ~/Library/Application Support/Grafix/mcp.json and returns its URL.
  static func writeMCPConfig(root: String) throws -> URL {
    try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
    let config: [String: Any] = [
      "mcpServers": [
        "grafix": [
          "command": mcpBinary().path,
          "args": ["--root", root],
          "env": ["GRAFIX_ROOT": root],
        ] as [String: Any]
      ]
    ]
    let url = supportDir.appendingPathComponent("mcp.json")
    try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys]).write(to: url)
    return url
  }

  // MARK: - Prompt

  static func systemPrompt(model: AppModel) -> String {
    let doc = model.document
    let sel = doc.selectedElements.filter { $0.containerId == nil || !doc.selection.contains($0.containerId!) }
    var selection = "nothing selected"
    if !sel.isEmpty {
      let rows = sel.prefix(30).map { e -> String in
        let label = e.text.isEmpty ? (doc.scene.elements.first { $0.containerId == e.id }?.text ?? "") : e.text
        return "- \(e.id) (\(e.type.rawValue)\(label.isEmpty ? "" : ", \"\(label.prefix(40))\""))"
      }
      selection = "\(sel.count) selected element(s):\n" + rows.joined(separator: "\n")
    }
    return """
      You are the AI assistant built into Grafix, a native macOS Excalidraw-style drawing app. The user has a scene open and \
      sees your edits live on their canvas.
      Open scene id: \(doc.sceneID ?? "none"). Workspace collection: \(model.currentCollection).
      Current selection: \(selection).
      Rules: use ONLY the grafix MCP tools to read and change the scene (never touch files directly, never use shell). \
      Call the matching read_*_format guide tool before your first write. Prefer editing the open scene over creating new ones. \
      Keep edits minimal and focused on the request, then verify with take_screenshot and fix problems. \
      Reply briefly in plain Markdown.
      """
  }

  // MARK: - Run

  func send(_ prompt: String, model: AppModel) {
    let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, !running else { return }
    items.append(ChatItem(kind: .user(text)))
    guard let claude = claudePath else {
      items.append(ChatItem(kind: .error("Install Claude Code to use AI chat.")))
      return
    }
    model.document.flushSave()
    let configURL: URL
    do { configURL = try Self.writeMCPConfig(root: model.workspace.root.path) } catch {
      items.append(ChatItem(kind: .error("Could not write MCP config: \(error.localizedDescription)")))
      return
    }
    var args = [
      "-p", text, "--output-format", "stream-json", "--verbose",
      "--mcp-config", configURL.path, "--strict-mcp-config",
      "--allowedTools", "mcp__grafix__*",
      "--disallowedTools", "Bash", "Edit", "Write", "NotebookEdit", "WebFetch", "WebSearch",
      "--permission-mode", "acceptEdits",
      "--append-system-prompt", Self.systemPrompt(model: model),
    ]
    if let sessionID { args += ["--resume", sessionID] }
    start(executable: claude, arguments: args)
  }

  private func start(executable: String, arguments: [String]) {
    running = true
    stopped = false
    gotText = false
    openTextIndex = nil
    let work = Self.supportDir.appendingPathComponent("agent", isDirectory: true)
    try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

    let p = Process()
    p.executableURL = URL(fileURLWithPath: executable)
    p.arguments = arguments
    p.currentDirectoryURL = work
    var env = ProcessInfo.processInfo.environment
    env["PATH"] = (env["PATH"] ?? "/usr/bin:/bin") + ":\(NSHomeDirectory())/.local/bin:/opt/homebrew/bin:/usr/local/bin"
    p.environment = env
    p.standardInput = FileHandle.nullDevice
    let out = Pipe()
    let err = Pipe()
    p.standardOutput = out
    p.standardError = err

    let buffer = LineBuffer()
    let errBuffer = LineBuffer()
    err.fileHandleForReading.readabilityHandler = { h in errBuffer.append(h.availableData) }
    let box = ProcessBox(p)
    out.fileHandleForReading.readabilityHandler = { [weak self] h in
      let data = h.availableData
      if data.isEmpty {
        h.readabilityHandler = nil
        errBuffer.append(Data())
        let tail = errBuffer.all
        box.process.waitUntilExit()
        let code = box.process.terminationStatus
        Task { @MainActor in self?.finish(exitCode: code, stderr: tail) }
        return
      }
      let events = buffer.append(data).flatMap { AgentEvent.parse(line: $0) }
      if !events.isEmpty { Task { @MainActor in for e in events { self?.handle(e) } } }
    }
    do {
      try p.run()
      process = p
    } catch {
      running = false
      items.append(ChatItem(kind: .error("Could not start claude: \(error.localizedDescription)")))
    }
  }

  func stop() {
    stopped = true
    process?.terminate()
  }

  func newConversation() {
    guard !running else { return }
    items = []
    sessionID = nil
  }

  private func finish(exitCode: Int32, stderr: String) {
    running = false
    process = nil
    openTextIndex = nil
    for i in items.indices {
      if case .tool(let n, let id, .running, let img) = items[i].kind { items[i].kind = .tool(name: n, toolID: id, status: .done, image: img) }
    }
    if stopped {
      items.append(ChatItem(kind: .error("Stopped.")))
    } else if exitCode != 0, !items.contains(where: { if case .error = $0.kind { true } else { false } }) {
      let msg = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
      items.append(ChatItem(kind: .error(msg.isEmpty ? "claude exited with code \(exitCode)." : String(msg.suffix(600)))))
    }
  }

  private func handle(_ event: AgentEvent) {
    switch event {
    case .session(let id): sessionID = id
    case .text(let t):
      gotText = true
      if let i = openTextIndex, case .assistant(let old) = items[i].kind {
        items[i].kind = .assistant(old + "\n\n" + t)
      } else {
        items.append(ChatItem(kind: .assistant(t)))
        openTextIndex = items.count - 1
      }
    case .toolUse(let id, let name):
      openTextIndex = nil
      let short = name.replacingOccurrences(of: "mcp__grafix__", with: "")
      items.append(ChatItem(kind: .tool(name: short, toolID: id, status: .running, image: nil)))
    case .toolResult(let id, let failed, let data):
      for i in items.indices {
        if case .tool(let n, let tid, _, _) = items[i].kind, tid == id {
          items[i].kind = .tool(name: n, toolID: tid, status: failed ? .failed : .done, image: data.flatMap { NSImage(data: $0) })
        }
      }
    case .result(let failed, let message):
      if failed {
        items.append(ChatItem(kind: .error(message ?? "The agent reported an error.")))
      } else if let message, !message.isEmpty, !gotText {
        items.append(ChatItem(kind: .assistant(message)))
      }
    }
  }

}

/// Splits a byte stream into complete lines; thread-safe.
final class LineBuffer: @unchecked Sendable {
  private let lock = NSLock()
  private var pending = Data()
  private var collected = Data()

  @discardableResult
  func append(_ data: Data) -> [String] {
    lock.lock()
    defer { lock.unlock() }
    collected.append(data)
    pending.append(data)
    var lines: [String] = []
    while let nl = pending.firstIndex(of: 0x0A) {
      lines.append(String(decoding: pending[pending.startIndex..<nl], as: UTF8.self))
      pending.removeSubrange(pending.startIndex...nl)
    }
    return lines
  }

  var all: String {
    lock.lock()
    defer { lock.unlock() }
    return String(decoding: collected, as: UTF8.self)
  }
}

final class ProcessBox: @unchecked Sendable {
  let process: Process
  init(_ p: Process) { process = p }
}
