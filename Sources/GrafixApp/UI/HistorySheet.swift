import GrafixCore
import GrafixRender
import SwiftUI

/// Version history (Excalidraw+ "History"): browse snapshots, preview, restore.
struct HistorySheet: View {
  @Bindable var model: AppModel
  @State private var revisions: [Workspace.Revision] = []
  @State private var selected: Workspace.Revision?
  @State private var preview: CGImage?

  var body: some View {
    let doc = model.document
    HStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 0) {
        Text("Version history").font(.system(size: 15, weight: .semibold)).padding(14)
        Divider()
        if revisions.isEmpty {
          Text("No versions yet. Grafix keeps a snapshot every few minutes while you edit.")
            .font(.system(size: 12)).foregroundStyle(.secondary).padding(14)
        }
        List(revisions, selection: Binding(get: { selected?.id }, set: { id in selected = revisions.first { $0.id == id } })) { r in
          VStack(alignment: .leading, spacing: 2) {
            Text(r.date.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 13))
            Text(r.date.formatted(.relative(presentation: .named))).font(.system(size: 11)).foregroundStyle(.secondary)
          }
          .tag(r.id)
        }
        .listStyle(.sidebar)
      }
      .frame(width: 240)
      Divider()
      VStack {
        ZStack {
          Color(nsColor: .textBackgroundColor)
          if let preview {
            Image(decorative: preview, scale: 2).resizable().scaledToFit().padding(20)
          } else {
            Text(selected == nil ? "Select a version" : "Rendering…").foregroundStyle(.secondary)
          }
        }
        HStack {
          Spacer()
          Button("Close") { model.showHistory = false }.keyboardShortcut(.cancelAction)
          Button("Restore this version") {
            if let selected { doc.restore(revision: selected) }
            model.showHistory = false
          }
          .keyboardShortcut(.defaultAction)
          .disabled(selected == nil)
        }
        .padding(12)
      }
    }
    .frame(width: 900, height: 580)
    .task {
      if let id = doc.sceneID {
        doc.flushSave()
        _ = try? model.workspace.saveRevision(doc.scene, of: id)
        revisions = (try? model.workspace.revisions(of: id)) ?? []
        selected = revisions.dropFirst().first ?? revisions.first
      }
    }
    .task(id: selected?.id) {
      preview = nil
      guard let r = selected else { return }
      let ws = model.workspace
      let dark = true
      let image = await Task.detached { () -> CGImage? in
        guard let s = try? ws.loadRevision(r) else { return nil }
        return SceneRenderer.image(s, scale: 2, maxWidth: 1300, maxHeight: 1000, padding: 20, dark: dark)
      }.value
      if selected?.id == r.id { preview = image }
    }
  }
}
