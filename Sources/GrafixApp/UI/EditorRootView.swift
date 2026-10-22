import GrafixCore
import GrafixPort
import SwiftUI

/// Window layout, mirroring Excalidraw's LayerUI: canvas full-bleed, floating
/// islands on top. Each panel lives in its own file under UI/.
struct EditorRootView: View {
  @Bindable var model: AppModel
  /// Window width, to tuck the sidebar away when the canvas would get cramped.
  @State private var windowWidth: CGFloat = 1440

  /// Side panels only show when the canvas keeps at least this much room.
  private static let minCanvasWidth: CGFloat = 820

  private var sidePanelsWidth: CGFloat {
    (model.rightPanel != nil ? 300 : 0) + (model.showChat ? 340 : 0)
  }

  private var showSidebar: Bool {
    model.showWorkspace && !model.document.view.zen && !model.presenting
      && windowWidth - sidePanelsWidth - 260 >= Self.minCanvasWidth
  }

  var body: some View {
    let doc = model.document
    let dark = true
    HStack(spacing: 0) {
      if showSidebar {
        WorkspaceSidebar(model: model)
          .frame(width: 260)
          .transition(.move(edge: .leading))
      }
      ZStack {
        CanvasRepresentable(document: doc)
          .ignoresSafeArea()
        if !model.presenting {
          // Leading alignment: if the window is too narrow, overflow goes off the
          // right edge instead of hiding the menu and properties panel.
          CanvasChrome(model: model)
            .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
      }
      // The canvas column absorbs all leftover width, so side panels never clip.
      .frame(minWidth: 0, maxWidth: .infinity)
      .clipped()
      .layoutPriority(-1)
      if let panel = model.rightPanel, !doc.view.zen, !model.presenting {
        Group {
          if panel == "slides" { SlidesPanel(model: model) }
          if panel == "library" { LibraryPanel(model: model) }
        }
        .frame(width: 300)
        .transition(.move(edge: .trailing))
      }
      if model.showChat && !model.presenting {
        ChatPanel(model: model).frame(width: 340)
      }
    }
    .background(Theme.canvasBackground(dark))
    .background(GeometryReader { g in Color.clear.onAppear { windowWidth = g.size.width }.onChange(of: g.size.width) { _, w in windowWidth = w } })
    .preferredColorScheme(.dark)
    .overlay(alignment: .top) {
      if model.showCommandPalette && !model.presenting {
        ZStack(alignment: .top) {
          Color.black.opacity(0.15).ignoresSafeArea().onTapGesture { model.showCommandPalette = false }
          CommandPalette(model: model).padding(.top, 90)
        }
      } else if model.showFind && !model.presenting {
        HStack { Spacer(); FindBar(model: model).padding(.top, 70).padding(.trailing, 16) }
      }
    }
    .overlay {
      if model.presenting { PresentationView(model: model) }
    }
    .sheet(isPresented: $model.showHelp) { HelpSheet(model: model) }
    .sheet(isPresented: $model.showHistory) { HistorySheet(model: model) }
    .alert(
      "Grafix", isPresented: Binding(get: { model.error != nil || doc.lastError != nil }, set: { if !$0 { model.error = nil; doc.lastError = nil } })
    ) {
      Button("OK") {
        model.error = nil
        doc.lastError = nil
      }
    } message: {
      Text(model.error ?? doc.lastError ?? "")
    }
    .onReceive(NotificationCenter.default.publisher(for: .grafixShowHelp)) { _ in model.showHelp = true }
    .animation(.easeOut(duration: 0.15), value: model.showWorkspace)
    .animation(.easeOut(duration: 0.15), value: model.rightPanel)
  }
}

/// The floating UI over the canvas (top toolbar, left properties, footer).
struct CanvasChrome: View {
  @Bindable var model: AppModel

  var body: some View {
    let doc = model.document
    VStack(spacing: 0) {
      HStack(alignment: .top, spacing: 8) {
        if !doc.view.zen { MainMenuButton(model: model) }
        Spacer(minLength: 0)
        if !doc.view.viewMode { ToolbarIsland(document: doc) }
        Spacer(minLength: 0)
        if !doc.view.zen { TopRightIsland(model: model) }
      }
      .padding(.horizontal, 16)
      .padding(.top, 16)
      HStack(alignment: .top) {
        if !doc.view.zen && !doc.view.viewMode && PropertiesPanel.isVisible(doc) {
          PropertiesPanel(document: doc)
            .padding(.leading, 16)
            .padding(.top, 12)
        }
        Spacer()
      }
      Spacer(minLength: 0)
      if doc.view.showStats {
        HStack { Spacer(); StatsPanel(document: doc) }.padding(.trailing, 16)
      }
      FooterBar(model: model)
        .padding(16)
    }
  }
}
