import AppKit
import GrafixPort
import SwiftUI

/// One transcript row: user bubble, assistant Markdown, tool chip or error.
struct ChatRow: View {
  let item: ChatItem
  let palette: ChatPalette

  var body: some View {
    switch item.kind {
    case .user(let text):
      HStack {
        Spacer(minLength: 36)
        Text(text)
          .font(.system(size: 13))
          .foregroundStyle(palette.onBrandTint)
          .textSelection(.enabled)
          .padding(.horizontal, 10).padding(.vertical, 7)
          .background(palette.brandTint, in: RoundedRectangle(cornerRadius: 10))
      }
    case .assistant(let text):
      MarkdownText(text: text).foregroundStyle(palette.text)
        .frame(maxWidth: .infinity, alignment: .leading)
    case .tool(let name, _, let status, let image):
      VStack(alignment: .leading, spacing: 4) {
        ToolChip(name: name, status: status, palette: palette)
        if let image {
          Image(nsImage: image).resizable().scaledToFit()
            .frame(maxWidth: 240, maxHeight: 160)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(palette.border))
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    case .error(let text):
      Text(text).font(.system(size: 12)).foregroundStyle(palette.danger)
        .textSelection(.enabled)
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
  }
}

/// Compact "edit_scene_content ✓" pill.
struct ToolChip: View {
  let name: String
  let status: ChatItem.ToolStatus
  let palette: ChatPalette

  var body: some View {
    HStack(spacing: 5) {
      Text(name).font(.system(size: 11, design: .monospaced))
      switch status {
      case .running: ProgressView().controlSize(.mini).scaleEffect(0.7).frame(width: 10, height: 10)
      case .done: Text("✓").font(.system(size: 11, weight: .bold)).foregroundStyle(palette.success)
      case .failed: Text("✗").font(.system(size: 11, weight: .bold)).foregroundStyle(palette.danger)
      }
    }
    .foregroundStyle(palette.muted)
    .padding(.horizontal, 8).padding(.vertical, 3)
    .background(palette.hover, in: Capsule())
  }
}

/// Block-aware Markdown: paragraphs and list items rendered with AttributedString(markdown:).
struct MarkdownText: View {
  let text: String

  var body: some View {
    let blocks = text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    VStack(alignment: .leading, spacing: 4) {
      ForEach(Array(blocks.enumerated()), id: \.offset) { _, line in
        Text(Self.attributed(line)).font(.system(size: 13)).textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  static func attributed(_ line: String) -> AttributedString {
    var l = line
    var prefix = ""
    let trimmed = l.drop(while: { $0 == " " })
    if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") { prefix = "•  "; l = String(trimmed.dropFirst(2)) }
    else if trimmed.hasPrefix("#") { l = "**" + trimmed.drop(while: { $0 == "#" || $0 == " " }) + "**" }
    let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    let parsed = (try? AttributedString(markdown: l, options: opts)) ?? AttributedString(l)
    return AttributedString(prefix) + parsed
  }
}

/// Empty-state prompt suggestions.
struct SuggestedPrompts: View {
  let palette: ChatPalette
  let pick: (String) -> Void
  private let prompts = [
    "Make a flowchart of ", "Turn this into 5 slides", "Tidy up the selected shapes", "Explain this diagram",
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Ask AI to draw or edit this scene").font(.system(size: 12)).foregroundStyle(palette.muted)
      ForEach(prompts, id: \.self) { p in
        Button { pick(p) } label: {
          Text(p).font(.system(size: 13)).foregroundStyle(palette.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).stroke(palette.border))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
    }
  }
}
