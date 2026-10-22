import GrafixCore
import SwiftUI

/// Excalidraw's Stats panel (components/Stats): scene counts plus editable
/// position/size/angle of the selection. Toggle with Alt+/.
struct StatsPanel: View {
  let document: EditorDocument

  var body: some View {
    let _ = document.revision
    let doc = document
    let visible = doc.scene.visibleElements
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text("Stats").font(.system(size: 13, weight: .semibold))
        Spacer()
        Button { doc.view.showStats = false } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
      }
      Group {
        row("Scene", "")
        row("Elements", "\(visible.count)")
        if let b = doc.scene.bounds(of: Set(visible.map(\.id))) {
          row("Width", "\(Int(b.width))")
          row("Height", "\(Int(b.height))")
        }
      }
      if let e = doc.singleSelection {
        Divider()
        Text(e.type.rawValue.capitalized).font(.system(size: 12, weight: .semibold))
        field("X", e.x) { v in doc.commit { $0.move([e.id], by: CGPoint(x: v - e.x, y: 0)) } }
        field("Y", e.y) { v in doc.commit { $0.move([e.id], by: CGPoint(x: 0, y: v - e.y)) } }
        if !e.isLinear {
          field("W", e.width) { v in
            doc.commit { scene in
              scene.update(e.id) { $0.width = max(1, v) }
              scene.layoutLabel(of: e.id)
              scene.updateBoundArrows(of: [e.id])
            }
          }
          field("H", e.height) { v in
            doc.commit { scene in
              scene.update(e.id) { $0.height = max(1, v) }
              scene.layoutLabel(of: e.id)
              scene.updateBoundArrows(of: [e.id])
            }
          }
        }
        field("Angle", (e.angle * 180 / .pi).rounded()) { v in
          doc.commit { scene in
            scene.update(e.id) { $0.angle = v * .pi / 180 }
            scene.layoutLabel(of: e.id)
            scene.updateBoundArrows(of: [e.id])
          }
        }
        if e.isText { row("Font size", "\(Int(e.fontSize))") }
      } else if doc.selection.count > 1, let b = doc.scene.bounds(of: doc.selection) {
        Divider()
        row("Selected", "\(doc.selectedElements.count)")
        row("Width", "\(Int(b.width))")
        row("Height", "\(Int(b.height))")
      }
    }
    .font(.system(size: 12))
    .padding(12)
    .frame(width: 200)
    .background(RoundedRectangle(cornerRadius: 8).fill(Color(red: 0.14, green: 0.14, blue: 0.16)))
    .shadow(color: .black.opacity(0.12), radius: 6, y: 1)
  }

  private func row(_ label: String, _ value: String) -> some View {
    HStack {
      Text(label).foregroundStyle(.secondary)
      Spacer()
      Text(value).monospacedDigit()
    }
  }

  private func field(_ label: String, _ value: Double, _ set: @escaping (Double) -> Void) -> some View {
    HStack {
      Text(label).foregroundStyle(.secondary).frame(width: 40, alignment: .leading)
      NumberField(value: value, onCommit: set)
    }
  }
}

/// A text field that commits a number on Enter / focus loss.
private struct NumberField: View {
  let value: Double
  let onCommit: (Double) -> Void
  @State private var text = ""
  @FocusState private var focused: Bool

  var body: some View {
    TextField("", text: $text)
      .textFieldStyle(.roundedBorder)
      .monospacedDigit()
      .focused($focused)
      .onAppear { text = format(value) }
      .onChange(of: value) { _, v in if !focused { text = format(v) } }
      .onSubmit(commit)
      .onChange(of: focused) { _, f in if !f { commit() } }
  }

  private func format(_ v: Double) -> String { String(format: "%.0f", v) }
  private func commit() {
    if let v = Double(text), abs(v - value) > 0.0001 { onCommit(v) } else { text = format(value) }
  }
}
