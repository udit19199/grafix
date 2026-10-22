import AppKit
import GrafixCore
import SwiftUI

/// Menu bar. Command-key shortcuts follow Excalidraw's (actions/*.tsx keyTest
/// and HelpDialog). Plain-key shortcuts live in CanvasView.handleKey.
struct AppCommands: Commands {
  let model: AppModel?

  var body: some Commands {
    CommandGroup(replacing: .newItem) {
      Button("New Scene") { model?.newScene() }.keyboardShortcut("n")
      Button("New Window") { NSApp.sendAction(#selector(NSResponder.newWindowForTab(_:)), to: nil, from: nil) }
        .keyboardShortcut("n", modifiers: [.command, .shift])
      Divider()
      Button("Import .excalidraw…") { model?.importFile() }.keyboardShortcut("o")
      Button("Save") { model?.document.flushSave() }.keyboardShortcut("s")
      Button("Version History…") { model?.showHistory = true }.keyboardShortcut("h", modifiers: [.command, .option])
      Button("Export as .excalidraw…") { if let d = model?.document { ExportActions.exportExcalidraw(d) } }
        .keyboardShortcut("s", modifiers: [.command, .shift])
      Button("Export Image…") { if let d = model?.document { ExportActions.exportPNG(d) } }
        .keyboardShortcut("e", modifiers: [.command, .shift])
      Button("Export SVG…") { if let d = model?.document { ExportActions.exportSVG(d, selectionOnly: d.hasSelection) } }
      Button("Export Slides as PDF…") { if let d = model?.document { ExportActions.exportPDF(d, slides: true) } }
    }
    CommandGroup(replacing: .undoRedo) {
      Button("Undo") { model?.document.undo() }.keyboardShortcut("z").disabled(!(model?.document.canUndo ?? false))
      Button("Redo") { model?.document.redo() }.keyboardShortcut("z", modifiers: [.command, .shift])
        .disabled(!(model?.document.canRedo ?? false))
    }
    CommandGroup(replacing: .pasteboard) {
      Button("Cut") { if !forwardToText(#selector(NSText.cut(_:))) { model?.document.cutSelected() } }.keyboardShortcut("x")
      Button("Copy") { if !forwardToText(#selector(NSText.copy(_:))) { model?.document.copySelected() } }.keyboardShortcut("c")
      Button("Paste") {
        if !forwardToText(#selector(NSText.paste(_:))), let d = model?.document {
          d.paste(at: d.sceneCoordinates(CGPoint(x: d.viewSize.width / 2, y: d.viewSize.height / 2)))
        }
      }.keyboardShortcut("v")
      Button("Copy Styles") { model?.document.copyStyles() }.keyboardShortcut("c", modifiers: [.command, .option])
      Button("Paste Styles") { model?.document.pasteStyles() }.keyboardShortcut("v", modifiers: [.command, .option])
      Button("Copy as PNG") { if let d = model?.document { ExportActions.copyPNG(d, selectionOnly: d.hasSelection) } }
        .keyboardShortcut("c", modifiers: [.shift, .option])
      Divider()
      Button("Select All") { if !forwardToText(#selector(NSText.selectAll(_:))) { model?.document.selectAll() } }.keyboardShortcut("a")
      Button("Duplicate") { model?.document.duplicateSelected() }.keyboardShortcut("d")
      Button("Delete") { model?.document.deleteSelected() }.keyboardShortcut(.delete, modifiers: [])
        .disabled(true)  // handled by the canvas so text fields keep Delete
    }
    CommandMenu("Arrange") {
      Button("Group") { model?.document.groupSelected() }.keyboardShortcut("g")
      Button("Ungroup") { model?.document.ungroupSelected() }.keyboardShortcut("g", modifiers: [.command, .shift])
      Divider()
      Button("Bring Forward") { model?.document.reorderSelected(.forward) }.keyboardShortcut("]")
      Button("Send Backward") { model?.document.reorderSelected(.backward) }.keyboardShortcut("[")
      Button("Bring to Front") { model?.document.reorderSelected(.front) }.keyboardShortcut("]", modifiers: [.command, .option])
      Button("Send to Back") { model?.document.reorderSelected(.back) }.keyboardShortcut("[", modifiers: [.command, .option])
      Divider()
      Menu("Align") {
        Button("Left") { model?.document.alignSelected(.left) }.keyboardShortcut(.leftArrow, modifiers: [.command, .shift])
        Button("Center Horizontally") { model?.document.alignSelected(.centerX) }
        Button("Right") { model?.document.alignSelected(.right) }.keyboardShortcut(.rightArrow, modifiers: [.command, .shift])
        Button("Top") { model?.document.alignSelected(.top) }.keyboardShortcut(.upArrow, modifiers: [.command, .shift])
        Button("Center Vertically") { model?.document.alignSelected(.centerY) }
        Button("Bottom") { model?.document.alignSelected(.bottom) }.keyboardShortcut(.downArrow, modifiers: [.command, .shift])
      }
      Menu("Distribute") {
        Button("Horizontally") { model?.document.distributeSelected(horizontally: true) }.keyboardShortcut("h", modifiers: [.option])
        Button("Vertically") { model?.document.distributeSelected(horizontally: false) }.keyboardShortcut("v", modifiers: [.option])
      }
      Divider()
      Button("Link…") { model?.document.editLinkOfSelection() }.keyboardShortcut("k")
      Button("Lock / Unlock") { model?.document.toggleLockSelected() }.keyboardShortcut("l", modifiers: [.command, .shift])
    }
    CommandGroup(after: .toolbar) {
      Button("Zoom In") { model?.document.zoomIn() }.keyboardShortcut("=")
      Button("Zoom Out") { model?.document.zoomOut() }.keyboardShortcut("-")
      Button("Reset Zoom") { model?.document.resetZoom() }.keyboardShortcut("0")
      Button("Zoom to Fit") { model?.document.zoomToFitAll() }
      Divider()
      Button("Toggle Grid") { model?.document.view.grid.toggle(); model?.document.onOverlayChange?() }.keyboardShortcut("'")
      Button("Zen Mode") { model?.document.view.zen.toggle() }.keyboardShortcut("z", modifiers: [.option])
      Button("View Mode") { model?.document.view.viewMode.toggle() }.keyboardShortcut("r", modifiers: [.option])
      Divider()
      Button("Workspace Sidebar") { model?.showWorkspace.toggle() }.keyboardShortcut("b")
      Button("Slides") { model?.rightPanel = model?.rightPanel == "slides" ? nil : "slides" }.keyboardShortcut("k", modifiers: [.command, .shift])
      Button("Present") { model?.presentingSlide = 0; model?.presenting = true }.keyboardShortcut(.return, modifiers: [.command, .shift])
      Button("AI Chat") { model?.showChat.toggle() }.keyboardShortcut("j")
      Button("Command Palette") { model?.showCommandPalette.toggle() }.keyboardShortcut("p", modifiers: [.command, .shift])
      Button("Find on Canvas") { model?.showFind = true }.keyboardShortcut("f")
      Button("Library") { model?.rightPanel = model?.rightPanel == "library" ? nil : "library" }
    }
    CommandGroup(replacing: .help) {
      Button("Keyboard Shortcuts") { model?.showHelp = true }.keyboardShortcut("/", modifiers: [.command])
    }
  }

  /// Text fields keep their own clipboard behaviour.
  private func forwardToText(_ selector: Selector) -> Bool {
    if NSApp.keyWindow?.firstResponder is NSText {
      return NSApp.sendAction(selector, to: nil, from: nil)
    }
    return false
  }
}
