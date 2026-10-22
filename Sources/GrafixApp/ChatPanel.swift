import Darwin
import Foundation
import SwiftUI

struct ChatPanel: View {
  let sceneJSON: String
  let applyScene: (String) -> Void
  @State private var messages: [String] = []
  @State private var prompt = ""
  @State private var proposal: String?
  @State private var proposalSource: String?
  @State private var operation: ChatOperation?
  @State private var requestID: UUID?
  @State private var error: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Canvas coworker").font(.headline)
      Text(
        "Uses your installed Codex CLI and its signed-in account. Changes are proposed before they reach your canvas."
      )
      .font(.caption).foregroundStyle(.secondary)
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
            Text(message).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
          }
        }
      }
      if operation != nil {
        HStack {
          ProgressView().controlSize(.small)
          Text("Codex is working…").font(.caption)
          Spacer()
          Button("Cancel") { cancel() }
        }
      }
      if let error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
      if let proposal {
        Text(
          "Review the reply before applying. The model is asked to preserve unknown properties, but exact drawing fidelity is not guaranteed."
        )
        .font(.caption).foregroundStyle(.secondary)
        Button("Apply canvas change") {
          guard proposalSource == sceneJSON else {
            error = "The canvas changed since this proposal. Ask again using the current canvas."
            return
          }
          applyScene(proposal)
          self.proposal = nil
          messages.append("Applied the proposed canvas change.")
        }
        .disabled(proposalSource != sceneJSON)
        if proposalSource != sceneJSON {
          Text("Canvas changed. Request a fresh proposal before applying.").font(.caption)
            .foregroundStyle(.orange)
        }
      }
      TextEditor(text: $prompt).font(.body).frame(height: 85)
        .border(.secondary.opacity(0.3)).accessibilityLabel("Message to Codex")
      HStack {
        Button("Send", action: send).disabled(
          prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || operation != nil)
        Spacer()
        Button("Clear chat") {
          messages = []
          proposal = nil
          error = nil
        }
        .disabled(operation != nil)
      }
    }
    .padding().frame(minWidth: 280)
    .onDisappear { cancel() }
  }

  private func cancel() {
    operation?.cancel()
    operation = nil
    requestID = nil
    error = "Request cancelled. Your canvas was not changed."
  }

  private func send() {
    let question = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    let source = sceneJSON
    let history = messages.suffix(12).joined(separator: "\n\n")
    messages.append("You: \(question)")
    prompt = ""
    error = nil
    proposal = nil
    let work = ChatOperation()
    let id = UUID()
    operation = work
    requestID = id
    Task {
      let result = await Task.detached {
        work.run(
          prompt: """
            You are Grafix's drawing coworker. Reply to the user's request about the attached Excalidraw scene.
            Do not run commands, use tools, read other files, or modify files. Use only this supplied scene and conversation.
            Return the schema response: reply is your explanation; sceneJSON is an empty string if no edit is needed,
            otherwise it is the COMPLETE updated Excalidraw JSON document encoded as a string.
            Preserve every unknown document and element property, all existing IDs, files and appState.
            Change only what the user requests. Do not discard unsupported elements.
            Earlier conversation (context only):
            \(history)
            Current scene:
            \(source)
            User request:
            \(question)
            """)
      }.value
      guard requestID == id else { return }
      operation = nil
      requestID = nil
      switch result {
      case .success(let response):
        messages.append("Codex: \(response.reply)")
        if !response.sceneJSON.isEmpty {
          proposal = response.sceneJSON
          proposalSource = source
        }
      case .failure(let failure): error = failure.localizedDescription
      }
    }
  }
}

private struct ChatResponse: Decodable, Sendable {
  let reply: String
  let sceneJSON: String
}

private final class ChatOperation: @unchecked Sendable {
  private let lock = NSLock()
  private var process: Process?
  private var cancelled = false

  func cancel() {
    lock.lock()
    cancelled = true
    let running = process
    lock.unlock()
    if let running, running.isRunning {
      running.terminate()
      DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
        if running.isRunning { kill(running.processIdentifier, SIGKILL) }
      }
    }
  }

  func run(prompt: String) -> Result<ChatResponse, Error> {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "grafix-chat-\(UUID().uuidString)")
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: directory) }
      let schema = directory.appendingPathComponent("response-schema.json")
      let output = directory.appendingPathComponent("response.json")
      let input = directory.appendingPathComponent("prompt.txt")
      let log = directory.appendingPathComponent("codex.log")
      try Data(
        #"{"type":"object","properties":{"reply":{"type":"string"},"sceneJSON":{"type":"string"}},"required":["reply","sceneJSON"],"additionalProperties":false}"#
          .utf8
      ).write(to: schema)
      try Data(prompt.utf8).write(to: input)
      FileManager.default.createFile(atPath: log.path, contents: nil)
      let inputHandle = try FileHandle(forReadingFrom: input)
      let logHandle = try FileHandle(forWritingTo: log)
      defer {
        try? inputHandle.close()
        try? logHandle.close()
      }
      let child = Process()
      child.executableURL = URL(fileURLWithPath: "/usr/bin/env")
      child.arguments = [
        "codex", "exec", "--sandbox", "read-only", "--ephemeral", "--skip-git-repo-check",
        "--color", "never", "--output-schema", schema.path, "--output-last-message", output.path,
        "-",
      ]
      var environment = ProcessInfo.processInfo.environment
      let home = FileManager.default.homeDirectoryForCurrentUser.path
      environment["PATH"] = [
        environment["PATH"] ?? "", "/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin",
        "\(home)/.cargo/bin",
      ].joined(separator: ":")
      child.environment = environment
      child.currentDirectoryURL = directory
      child.standardInput = inputHandle
      child.standardOutput = logHandle
      child.standardError = logHandle
      lock.lock()
      if cancelled {
        lock.unlock()
        throw CocoaError(.userCancelled)
      }
      process = child
      do { try child.run() } catch {
        lock.unlock()
        throw error
      }
      lock.unlock()
      let timeout = DispatchWorkItem { [weak self] in self?.cancel() }
      DispatchQueue.global().asyncAfter(deadline: .now() + 180, execute: timeout)
      child.waitUntilExit()
      timeout.cancel()
      lock.lock()
      process = nil
      let wasCancelled = cancelled
      lock.unlock()
      guard !wasCancelled else {
        throw ChatFailure(
          "Codex stopped or exceeded the 3-minute limit. Your canvas was not changed.")
      }
      guard child.terminationStatus == 0 else {
        let detail = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        throw ChatFailure(
          "Codex failed (\(child.terminationStatus)). Check that `codex login` works in Terminal.\n\(detail.suffix(1800))"
        )
      }
      let response = try JSONDecoder().decode(ChatResponse.self, from: Data(contentsOf: output))
      if !response.sceneJSON.isEmpty {
        guard
          let object = try JSONSerialization.jsonObject(with: Data(response.sceneJSON.utf8))
            as? [String: Any],
          object["type"] as? String == "excalidraw", object["elements"] is [Any]
        else {
          throw ChatFailure("Codex returned an invalid Excalidraw scene. Nothing was applied.")
        }
      }
      return .success(response)
    } catch { return .failure(error) }
  }
}

private struct ChatFailure: LocalizedError {
  let message: String
  init(_ message: String) { self.message = message }
  var errorDescription: String? { message }
}
