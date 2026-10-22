import AppKit
import GrafixCore

/// Right-click menu (Excalidraw's ContextMenu items).
@MainActor
enum ContextMenuBuilder {
  static func menu(for doc: EditorDocument, at point: CGPoint, canvas: CanvasView) -> NSMenu {
    let menu = NSMenu()
    func item(_ title: String, _ key: String = "", _ mods: NSEvent.ModifierFlags = [.command], enabled: Bool = true, _ action: @escaping () -> Void) {
      let i = ClosureMenuItem(title: title, keyEquivalent: key, action: action)
      i.keyEquivalentModifierMask = mods
      i.isEnabled = enabled
      menu.addItem(i)
    }
    if doc.hasSelection {
      item("Cut", "x") { doc.cutSelected() }
      item("Copy", "c") { doc.copySelected() }
      item("Paste", "v") { doc.paste(at: point) }
      menu.addItem(.separator())
      item("Copy to clipboard as PNG", "c", [.shift, .option]) { ExportActions.copyPNG(doc, selectionOnly: true) }
      menu.addItem(.separator())
      if doc.selection.count > 1 { item("Group selection", "g") { doc.groupSelected() } }
      if doc.selectedElements.contains(where: { !$0.groupIds.isEmpty }) { item("Ungroup selection", "g", [.command, .shift]) { doc.ungroupSelected() } }
      if let e = doc.singleSelection, e.canHaveLabel, e.type != .arrow {
        item("Edit label", "\r", []) { canvas.beginLabelEditing(container: e.id) }
      }
      menu.addItem(.separator())
      item("Send backward", "[") { doc.reorderSelected(.backward) }
      item("Bring forward", "]") { doc.reorderSelected(.forward) }
      item("Send to back", "[", [.command, .option]) { doc.reorderSelected(.back) }
      item("Bring to front", "]", [.command, .option]) { doc.reorderSelected(.front) }
      menu.addItem(.separator())
      item("Flip horizontal", "H", [.shift]) { doc.flipSelected(horizontal: true) }
      item("Flip vertical", "V", [.shift]) { doc.flipSelected(horizontal: false) }
      menu.addItem(.separator())
      item("Add to library", "") { NotificationCenter.default.post(name: .grafixAddToLibrary, object: doc) }
      item("Duplicate", "d") { doc.duplicateSelected() }
      item(doc.selectedElements.allSatisfy(\.locked) ? "Unlock" : "Lock", "l", [.command, .shift]) { doc.toggleLockSelected() }
      menu.addItem(.separator())
      item("Delete", "\u{8}", []) { doc.deleteSelected() }
    } else {
      item("Paste", "v") { doc.paste(at: point) }
      menu.addItem(.separator())
      item("Select all", "a") { doc.selectAll() }
      item(doc.view.grid ? "Hide grid" : "Show grid", "'") {
        doc.view.grid.toggle()
        canvas.viewChanged()
      }
      item(doc.view.zen ? "Exit zen mode" : "Zen mode", "z", [.option]) { doc.view.zen.toggle() }
      item(doc.view.viewMode ? "Exit view mode" : "View mode", "r", [.option]) { doc.view.viewMode.toggle() }
      item("Zoom to fit all elements", "1", [.shift]) { doc.zoomToFitAll() }
      menu.addItem(.separator())
      let locked = doc.scene.visibleElements.filter(\.locked)
      if !locked.isEmpty {
        item("Unlock all", "") {
          let ids = Set(locked.map(\.id))
          doc.commit { $0.updateEach(ids) { $0.locked = false } }
        }
      }
    }
    return menu
  }
}

extension Notification.Name {
  /// Posted with the EditorDocument as object; the library panel adds the selection.
  static let grafixAddToLibrary = Notification.Name("grafix.addToLibrary")
}

/// NSMenuItem that runs a closure.
final class ClosureMenuItem: NSMenuItem {
  private let handler: () -> Void
  init(title: String, keyEquivalent: String, action: @escaping () -> Void) {
    handler = action
    super.init(title: title, action: #selector(run), keyEquivalent: keyEquivalent)
    target = self
  }
  required init(coder: NSCoder) { fatalError() }
  @objc private func run() { handler() }
}
