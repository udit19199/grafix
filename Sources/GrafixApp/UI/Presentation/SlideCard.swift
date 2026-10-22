import GrafixCore
import GrafixPort
import SwiftUI

/// One entry in the slides panel: number, 16:9 thumbnail, editable title and
/// presenter notes (Excalidraw+ presentation sidebar).
struct SlideCard: View {
  let slide: Slide
  let thumbnail: CGImage?
  let selected: Bool
  let dark: Bool
  let background: Color
  var onSelect: () -> Void
  var onRename: (String) -> Void
  var onNotes: (String) -> Void

  @State private var title = ""
  @State private var notes = ""
  @FocusState private var titleFocus: Bool
  @FocusState private var notesFocus: Bool
  @State private var hover = false

  private var m: PortMetrics { Theme.metrics(dark) }
  private var brand: Color { SlidesStyle.brand(dark) }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .top, spacing: 8) {
        Text("\(slide.number)")
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(selected ? brand : m.keybindingColor)
          .frame(width: 16, alignment: .trailing)
          .padding(.top, 2)
        thumb
      }
      HStack(spacing: 8) {
        Spacer().frame(width: 16)
        TextField("Slide \(slide.number)", text: $title)
          .textFieldStyle(.plain)
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(m.textColor)
          .focused($titleFocus)
          .onSubmit { commitTitle() }
          .onChange(of: titleFocus) { _, f in if !f { commitTitle() } }
      }
      HStack(alignment: .top, spacing: 8) {
        Spacer().frame(width: 16)
        notesEditor
      }
    }
    .padding(8)
    .background(
      RoundedRectangle(cornerRadius: 8).fill(selected ? m.selectedBackground : (hover ? m.hoverBackground : .clear)))
    .contentShape(Rectangle())
    .onHover { hover = $0 }
    .onAppear { title = slide.name; notes = slide.notes ?? "" }
    .onChange(of: slide.name) { _, n in if !titleFocus { title = n } }
    .onChange(of: slide.notes) { _, n in if !notesFocus { notes = n ?? "" } }
    .onDisappear { commitTitle(); commitNotes() }
  }

  private var thumb: some View {
    let aspect = slide.bounds.height > 0 ? slide.bounds.width / slide.bounds.height : 16.0 / 9
    return ZStack {
      Rectangle().fill(background)
      if let thumbnail {
        Image(decorative: thumbnail, scale: 2).resizable().aspectRatio(contentMode: .fit)
      } else {
        ProgressView().controlSize(.small).opacity(0.5)
      }
    }
    .aspectRatio(aspect, contentMode: .fit)
    .clipShape(RoundedRectangle(cornerRadius: 4))
    .overlay(
      RoundedRectangle(cornerRadius: 4)
        .strokeBorder(selected ? brand : m.borderColor, lineWidth: selected ? 2 : 1))
    .onTapGesture(perform: onSelect)
  }

  private var notesEditor: some View {
    ZStack(alignment: .topLeading) {
      TextEditor(text: $notes)
        .font(.system(size: 11))
        .scrollContentBackground(.hidden)
        .foregroundStyle(m.textColor)
        .focused($notesFocus)
        .onChange(of: notesFocus) { _, f in if !f { commitNotes() } }
        .padding(.horizontal, -5)
      if notes.isEmpty {
        Text("Presenter notes")
          .font(.system(size: 11))
          .foregroundStyle(m.keybindingColor)
          .allowsHitTesting(false)
      }
    }
    .frame(minHeight: 36, maxHeight: 72)
    .padding(.horizontal, 6)
    .padding(.vertical, 4)
    .background(
      RoundedRectangle(cornerRadius: 6).fill(m.surfaceLowest)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 6).strokeBorder(notesFocus ? brand : m.borderColor, lineWidth: 1))
  }

  private func commitTitle() { if title != slide.name { onRename(title) } }
  private func commitNotes() { if notes != (slide.notes ?? "") { onNotes(notes) } }
}

enum SlidesStyle {
  static func brand(_ dark: Bool) -> Color {
    PortTheme.color("color-primary", dark: dark) ?? Color(red: 0x69 / 255, green: 0x65 / 255, blue: 0xdb / 255)
  }
}
