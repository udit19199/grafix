import AppKit
import GrafixCore
import GrafixPort
import GrafixRender
import SwiftUI

/// Right sidebar listing the scene's slides; ports the Excalidraw+ "Presentation"
/// sidebar. One frame = one slide, ordered by frame customData.slidesOrder.
struct SlidesPanel: View {
  @Bindable var model: AppModel
  @State private var thumbs = SlideThumbnails()
  @State private var pendingDelete: String?
  @State private var dropTarget: String?

  var body: some View {
    let doc = model.document
    let dark = true
    let m = Theme.metrics(dark)
    let _ = doc.revision
    let slides = doc.scene.slides
    let bg = Color(cgColor: CSSColor.cgColor(doc.scene.viewBackgroundColor, dark: dark))
    VStack(spacing: 0) {
      header(slides.count, doc: doc, m: m)
      Rectangle().fill(m.borderColor).frame(height: 1)
      if slides.isEmpty {
        emptyState(doc: doc, m: m)
      } else {
        ScrollView {
          LazyVStack(spacing: 4) {
            ForEach(slides, id: \.frameID) { slide in
              card(slide, doc: doc, dark: dark, bg: bg, order: slides.map(\.frameID))
            }
          }
          .padding(8)
        }
      }
    }
    .background(m.islandColor)
    .overlay(alignment: .leading) { Rectangle().fill(m.borderColor).frame(width: 1) }
    .onAppear { thumbs.refresh(doc, delay: .milliseconds(10)) }
    .onChange(of: doc.revision) { thumbs.refresh(doc) }
    .onChange(of: doc.sceneID) { thumbs.refresh(doc, delay: .milliseconds(10)) }
    .confirmationDialog(
      "Delete this slide and everything on it?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
      titleVisibility: .visible
    ) {
      Button("Delete slide", role: .destructive) {
        if let id = pendingDelete { doc.deleteSlide(id) }
        pendingDelete = nil
      }
    }
  }

  // MARK: Header

  private func header(_ count: Int, doc: EditorDocument, m: PortMetrics) -> some View {
    let brand = SlidesStyle.brand(true)
    return VStack(spacing: 10) {
      HStack(spacing: 8) {
        Text("Slides").font(.system(size: 14, weight: .semibold)).foregroundStyle(m.textColor)
        Text("\(count)")
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(m.keybindingColor)
          .padding(.horizontal, 6).padding(.vertical, 1)
          .background(Capsule().fill(m.hoverBackground))
        Spacer()
        Menu {
          Button("Export PDF…") { ExportActions.exportPDF(doc, slides: true) }.disabled(count == 0)
          Button("Add slide") { doc.addSlide() }
        } label: {
          PortIconView(name: "dots", size: 16, color: m.iconColor)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 28, height: 28)
        Button { model.rightPanel = nil } label: {
          PortIconView(name: "cross", size: 16, color: m.iconColor).frame(width: 28, height: 28)
        }.buttonStyle(.plain)
      }
      HStack(spacing: 8) {
        Button { present(from: doc) } label: {
          HStack(spacing: 6) {
            PortIconView(name: "playerplay", size: 14, color: .white)
            Text("Present").font(.system(size: 13, weight: .semibold))
          }
          .foregroundStyle(.white)
          .frame(maxWidth: .infinity, minHeight: 32)
          .background(RoundedRectangle(cornerRadius: 8).fill(brand.opacity(count == 0 ? 0.4 : 1)))
        }
        .buttonStyle(.plain).disabled(count == 0)
        Button { doc.addSlide() } label: {
          HStack(spacing: 4) {
            PortIconView(name: "plus", size: 14, color: m.textColor)
            Text("Add slide").font(.system(size: 13, weight: .medium))
          }
          .foregroundStyle(m.textColor)
          .frame(maxWidth: .infinity, minHeight: 32)
          .background(RoundedRectangle(cornerRadius: 8).fill(m.hoverBackground))
        }
        .buttonStyle(.plain)
      }
    }
    .padding(12)
  }

  private func emptyState(doc: EditorDocument, m: PortMetrics) -> some View {
    VStack(spacing: 10) {
      Spacer()
      PortIconView(name: "present", size: 36, color: m.keybindingColor)
      Text("No slides yet").font(.system(size: 14, weight: .semibold)).foregroundStyle(m.textColor)
      Text("Each frame on the canvas is a slide. Add a slide, draw inside it, then present.")
        .font(.system(size: 12)).foregroundStyle(m.keybindingColor)
        .multilineTextAlignment(.center).padding(.horizontal, 24)
      Button { doc.addSlide() } label: {
        Text("Add first slide").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
          .padding(.horizontal, 16).frame(height: 32)
          .background(RoundedRectangle(cornerRadius: 8).fill(SlidesStyle.brand(true)))
      }.buttonStyle(.plain)
      Spacer()
    }
    .frame(maxWidth: .infinity)
  }

  // MARK: Cards

  private func card(_ slide: Slide, doc: EditorDocument, dark: Bool, bg: Color, order: [String]) -> some View {
    let id = slide.frameID
    return SlideCard(
      slide: slide, thumbnail: thumbs.image(id), selected: doc.selection.contains(id), dark: dark, background: bg,
      onSelect: { doc.focusSlide(id) },
      onRename: { doc.renameSlide(id, to: $0) },
      onNotes: { doc.setSlideNotes(id, $0) }
    )
    .overlay(alignment: .top) {
      if dropTarget == id { Rectangle().fill(SlidesStyle.brand(dark)).frame(height: 2).offset(y: -3) }
    }
    .draggable(id) { Text(slide.name.isEmpty ? "Slide \(slide.number)" : slide.name).padding(6) }
    .dropDestination(for: String.self) { items, _ in
      guard let moved = items.first, moved != id else { return false }
      var next = order.filter { $0 != moved }
      next.insert(moved, at: next.firstIndex(of: id) ?? next.count)
      doc.reorderSlides(next)
      return true
    } isTargeted: { dropTarget = $0 ? id : (dropTarget == id ? nil : dropTarget) }
    .contextMenu {
      Button("Present from here") { model.presentingSlide = slide.number - 1; model.presenting = true }
      Button("Duplicate slide") { doc.duplicateSlide(id) }
      Divider()
      Button("Move up") { doc.moveSlide(id, by: -1) }.disabled(slide.number == 1)
      Button("Move down") { doc.moveSlide(id, by: 1) }.disabled(slide.number == order.count)
      Divider()
      Button("Delete slide…", role: .destructive) { pendingDelete = id }
    }
  }

  private func present(from doc: EditorDocument) {
    let order = doc.scene.slideFrames.map(\.id)
    let start = order.firstIndex { doc.selection.contains($0) } ?? 0
    model.presentingSlide = start
    model.presenting = true
  }
}
