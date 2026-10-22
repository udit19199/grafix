import GrafixPort
import SwiftUI

/// Right-side AI chat: runs an installed agent CLI with Grafix's MCP server attached.
/// Styled after Excalidraw's Sidebar (components/Sidebar/Sidebar.scss) and TTDDialog chat.
struct ChatPanel: View {
  @Bindable var model: AppModel
  @State private var runner = AgentRunner()
  @State private var draft = ""
  @FocusState private var inputFocused: Bool

  var body: some View {
    let palette = ChatPalette(dark: true)
    VStack(spacing: 0) {
      header(palette)
      Divider().overlay(palette.border)
      transcript(palette)
      inputArea(palette)
      Text("Edits arrive live. Cmd+Z undoes an agent edit.")
        .font(.system(size: 10.5)).foregroundStyle(palette.muted)
        .padding(.bottom, 8)
    }
    .frame(maxHeight: .infinity)
    .background(palette.panel)
    .overlay(alignment: .leading) { Rectangle().fill(palette.border).frame(width: 1) }
    .task {
      await runner.detect()
      if let test = ProcessInfo.processInfo.environment["GRAFIX_CHAT_TEST"], !test.isEmpty, runner.items.isEmpty {
        runner.send(test, model: model)
      }
    }
  }

  private func header(_ p: ChatPalette) -> some View {
    HStack(spacing: 8) {
      Text("AI").font(.system(size: 14, weight: .semibold)).foregroundStyle(p.text)
      if let name = runner.cliName {
        Text(name).font(.system(size: 11)).foregroundStyle(p.muted)
          .padding(.horizontal, 6).padding(.vertical, 2).background(p.hover, in: Capsule())
      }
      Spacer()
      if !runner.items.isEmpty && !runner.running {
        Button("New") { runner.newConversation() }.buttonStyle(.plain)
          .font(.system(size: 12)).foregroundStyle(p.brand)
      }
      Button { model.showChat = false } label: {
        PortIconView(name: "cross", size: 16, color: p.text).frame(width: 28, height: 28).contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help("Close")
    }
    .padding(.leading, 14).padding(.trailing, 8).frame(height: 44)
  }

  private func transcript(_ p: ChatPalette) -> some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 10) {
          if runner.detected && runner.cliName == nil {
            Text("Install Claude Code to use AI chat.").font(.system(size: 13)).foregroundStyle(p.muted)
          } else if runner.items.isEmpty {
            SuggestedPrompts(palette: p) { draft = $0; inputFocused = true }
          }
          ForEach(runner.items) { ChatRow(item: $0, palette: p) }
          if runner.running {
            ProgressView().controlSize(.small).scaleEffect(0.8).id("tail")
          }
          Color.clear.frame(height: 1).id("end")
        }
        .padding(14)
      }
      .onChange(of: runner.items.count) { _, _ in proxy.scrollTo("end") }
      .onChange(of: runner.running) { _, _ in proxy.scrollTo("end") }
    }
  }

  private func inputArea(_ p: ChatPalette) -> some View {
    HStack(alignment: .bottom, spacing: 8) {
      TextField("Message AI…", text: $draft, axis: .vertical)
        .textFieldStyle(.plain)
        .font(.system(size: 13))
        .foregroundStyle(p.text)
        .lineLimit(1...6)
        .focused($inputFocused)
        .onKeyPress(.return, phases: .down) { press in
          if press.modifiers.contains(.shift) { draft += "\n"; return .handled }
          submit()
          return .handled
        }
        .disabled(runner.detected && runner.cliName == nil)
      if runner.running {
        Button { runner.stop() } label: {
          Image(systemName: "stop.fill").font(.system(size: 11)).foregroundStyle(.white)
            .frame(width: 26, height: 26).background(p.danger, in: Circle())
        }
        .buttonStyle(.plain).help("Stop")
      } else {
        Button { submit() } label: {
          Image(systemName: "arrow.up").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? p.muted.opacity(0.5) : p.brand, in: Circle())
        }
        .buttonStyle(.plain).help("Send")
      }
    }
    .padding(.horizontal, 10).padding(.vertical, 8)
    .background(p.inputBG, in: RoundedRectangle(cornerRadius: 10))
    .overlay(RoundedRectangle(cornerRadius: 10).stroke(inputFocused ? p.brand : p.inputBorder, lineWidth: inputFocused ? 2 : 1))
    .padding(12)
  }

  private func submit() {
    let text = draft
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !runner.running else { return }
    draft = ""
    runner.send(text, model: model)
  }
}
