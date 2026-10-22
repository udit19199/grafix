import GrafixPort
import SwiftUI

/// Keyboard shortcuts dialog: Excalidraw's `HelpDialog`, drawn by
/// `GrafixPort.PortHelpDialog`, dismissed with Escape or its close button.
struct HelpSheet: View {
  @Bindable var model: AppModel

  /// Shortcut actions the editor answers (matches AppCommands and CanvasView).
  private static let liveActions = [
    "loadScene", "saveScene", "saveFileToDisk", "zenMode", "viewMode", "gridMode", "zoomIn", "zoomOut", "resetZoom",
    "zoomToFit", "zoomToFitSelection", "toggleShortcuts", "deleteSelectedElements", "duplicateSelection", "selectAll", "cut", "copy",
    "paste", "copyStyles", "pasteStyles", "copyAsPng", "group", "ungroup", "sendBackward", "bringForward", "sendToBack",
    "bringToFront", "flipHorizontal", "flipVertical", "hyperlink", "toggleElementLock", "imageExport", "searchMenu", "commandPalette",
    "toolLock", "clearCanvas",
  ]

  var body: some View {
    PortHelpDialog(
      liveActions: Self.liveActions, liveBindings: ["Cmd+Z", "Cmd+Shift+Z"], dark: true,
      dismiss: { model.showHelp = false }
    )
    .frame(minWidth: 1040, minHeight: 720)
    .background(Theme.palette(true).island)
    .onExitCommand { model.showHelp = false }
  }
}
