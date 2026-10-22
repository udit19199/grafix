import AppKit
import CryptoKit
import Foundation
import GrafixCore
import UniformTypeIdentifiers

/// Editing actions shared by menus, keyboard shortcuts, the context menu and
/// the properties panel. Names follow Excalidraw's actions/ folder.
extension EditorDocument {
  var hasSelection: Bool { !selection.isEmpty }

  func deleteSelected() {
    guard hasSelection else { return }
    let ids = selection
    commit { $0.delete(ids) }
    selection = []
  }

  func duplicateSelected() {
    guard hasSelection else { return }
    let ids = selection
    var created: [String] = []
    commit { created = $0.duplicate(ids, offset: CGPoint(x: 10, y: 10)) }
    select(Set(created))
  }

  func groupSelected() {
    guard selection.count > 1 else { return }
    let ids = selection
    commit { $0.group(ids) }
  }

  func ungroupSelected() {
    let ids = selection
    commit { $0.ungroup(ids) }
  }

  func reorderSelected(_ move: Scene.ZMove) {
    guard hasSelection else { return }
    let ids = selection
    commit { $0.reorder(ids, move) }
  }

  func alignSelected(_ a: Scene.Alignment) {
    let ids = selection
    commit { $0.align(ids, a) }
  }

  func distributeSelected(horizontally: Bool) {
    let ids = selection
    commit { $0.distribute(ids, horizontally: horizontally) }
  }

  func toggleLockSelected() {
    guard hasSelection else { return }
    let ids = selection
    let lock = !selectedElements.allSatisfy(\.locked)
    commit { $0.updateEach(ids, includeLabels: true) { $0.locked = lock } }
    if lock { selection = [] }
  }

  func flipSelected(horizontal: Bool) {
    guard let bounds = scene.bounds(of: selection) else { return }
    let ids = scene.withLabels(selection)
    commit { scene in
      for i in scene.elements.indices where ids.contains(scene.elements[i].id) {
        var e = scene.elements[i]
        if e.isText && e.containerId != nil { continue }
        if e.isLinear || e.type == .freedraw {
          let global = e.points.map { e.toScene($0) }.map { p in
            horizontal ? CGPoint(x: bounds.maxX - (p.x - bounds.minX), y: p.y) : CGPoint(x: p.x, y: bounds.maxY - (p.y - bounds.minY))
          }
          e.setGlobalPoints(global)
        } else {
          if horizontal { e.x = bounds.maxX - (e.x + e.width - bounds.minX) } else { e.y = bounds.maxY - (e.y + e.height - bounds.minY) }
          e.angle = -e.angle
          if e.type == .image {
            if horizontal { e.scale[0] *= -1 } else { e.scale[1] *= -1 }
          }
        }
        e.bump()
        scene.elements[i] = e
      }
      for id in ids where scene.element(id)?.boundTextID != nil { scene.layoutLabel(of: id) }
      scene.updateBoundArrows(of: ids)
    }
  }

  /// Cmd+K: set or clear the hyperlink on the selection.
  func editLinkOfSelection() {
    guard hasSelection else { return }
    let alert = NSAlert()
    alert.messageText = "Link"
    alert.informativeText = "Cmd-click the element to open it."
    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
    field.stringValue = singleSelection?.link ?? ""
    field.placeholderString = "https://"
    alert.accessoryView = field
    alert.addButton(withTitle: "Save")
    alert.addButton(withTitle: "Cancel")
    alert.window.initialFirstResponder = field
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    let value = field.stringValue.trimmingCharacters(in: .whitespaces)
    let ids = selection.filter { scene.element($0)?.containerId == nil }
    commit { $0.updateEach(ids) { $0.link = value.isEmpty ? nil : value } }
  }

  // MARK: - Clipboard (Excalidraw clipboard format)

  static let clipboardType = "excalidraw/clipboard"

  func copySelected() {
    let ids = scene.expandedSelection(selection)
    let elements = scene.elements.filter { ids.contains($0.id) && !$0.isDeleted }
    guard !elements.isEmpty else { return }
    let fileIDs = Set(elements.compactMap(\.fileId))
    let payload: JSONValue = [
      "type": .string(Self.clipboardType),
      "elements": .array(elements.map { .object($0.json) }),
      "files": .object(scene.files.filter { fileIDs.contains($0.key) }),
    ]
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(payload.serialized(), forType: .string)
  }

  func cutSelected() {
    copySelected()
    deleteSelected()
  }

  /// Pastes Excalidraw clipboard JSON, a whole scene, an image, or plain text,
  /// centred at `point` (scene coordinates).
  func paste(at point: CGPoint) {
    let pb = NSPasteboard.general
    if let text = pb.string(forType: .string) {
      if let json = try? JSONValue.parse(text), let o = json.object,
        o["type"]?.string == Self.clipboardType || o["type"]?.string == "excalidraw",
        let raw = o["elements"]?.array
      {
        let elements = raw.compactMap(\.object).map(Element.init(json:)).filter { !$0.isDeleted }
        pasteElements(elements, files: o["files"]?.object ?? [:], at: point)
        return
      }
      if !text.isEmpty {
        let e = Element.makeText(text, x: point.x, y: point.y, style: style)
        var moved = e
        moved.x -= e.width / 2
        moved.y -= e.height / 2
        commit { $0.elements.append(moved) }
        select([moved.id])
        return
      }
    }
    if let data = pb.data(forType: .png) ?? pb.data(forType: .tiff).flatMap({ NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) }) {
      insertImage(data: data, mimeType: "image/png", at: point)
    }
  }

  private func pasteElements(_ elements: [Element], files: [String: JSONValue], at point: CGPoint) {
    guard !elements.isEmpty else { return }
    var temp = Scene(elements: elements)
    let ids = Set(elements.map(\.id))
    guard let bounds = temp.bounds(of: ids) else { return }
    let created = temp.duplicate(ids, offset: CGPoint(x: point.x - bounds.midX, y: point.y - bounds.midY))
    let copies = temp.elements.filter { !ids.contains($0.id) }
    commit { scene in
      scene.elements.append(contentsOf: copies)
      for (k, v) in files where scene.files[k] == nil { scene.files[k] = v }
    }
    select(Set(created))
  }

  // MARK: - Images

  /// Adds an image file to the scene and an image element for it.
  func insertImage(data: Data, mimeType: String, at point: CGPoint) {
    guard let rep = NSBitmapImageRep(data: data) ?? NSImage(data: data).flatMap({ $0.tiffRepresentation }).flatMap(NSBitmapImageRep.init(data:)) else {
      lastError = "That file is not an image Grafix can read."
      return
    }
    let fileID = Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
    var w = Double(rep.pixelsWide)
    var h = Double(rep.pixelsHigh)
    // Excalidraw caps inserted images to a sensible size.
    let maxSide = 600.0
    if max(w, h) > maxSide {
      let k = maxSide / max(w, h)
      w *= k
      h *= k
    }
    var e = Element.make(.image, x: point.x - w / 2, y: point.y - h / 2, width: w, height: h, style: style)
    e.fileId = fileID
    e.roundness = nil
    let file: JSONValue = [
      "mimeType": .string(mimeType), "id": .string(fileID),
      "dataURL": .string("data:\(mimeType);base64,\(data.base64EncodedString())"),
      "created": .number(Element.now()), "lastRetrieved": .number(Element.now()),
    ]
    commit { scene in
      scene.files[fileID] = file
      scene.elements.append(e)
    }
    select([e.id])
  }

  func insertImageFromPanel(at point: CGPoint) {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.png, .jpeg, .gif, .svg, .webP, .heic, .image]
    guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
    let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "image/png"
    if mime == "image/svg+xml" {
      // Rasterize SVG so every renderer can show it.
      if let image = NSImage(data: data), let tiff = image.tiffRepresentation,
        let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
      {
        insertImage(data: png, mimeType: "image/png", at: point)
      }
      return
    }
    insertImage(data: data, mimeType: mime, at: point)
  }

  // MARK: - Canvas

  func clearCanvas() {
    let ids = Set(scene.visibleElements.map(\.id))
    commit { $0.delete(ids) }
    selection = []
  }

  func setBackground(_ color: String) {
    commit { $0.viewBackgroundColor = color }
  }

  func zoomIn() { setZoom(stepped(view.zoom, up: true), viewSize: viewSize) }
  func zoomOut() { setZoom(stepped(view.zoom, up: false), viewSize: viewSize) }
  func resetZoom() { setZoom(1, viewSize: viewSize) }

  func zoomToFitAll() {
    guard let r = scene.bounds(of: Set(scene.visibleElements.map(\.id))) else { return }
    zoom(toFit: r, viewSize: viewSize, maxZoom: 1)
  }

  func zoomToSelection() {
    guard let r = scene.bounds(of: selection) else { return zoomToFitAll() }
    zoom(toFit: r, viewSize: viewSize, maxZoom: 4)
  }

  /// Excalidraw zoom steps by 10% of the current zoom, snapped to 10%.
  private func stepped(_ z: CGFloat, up: Bool) -> CGFloat {
    let next = up ? z + 0.1 : z - 0.1
    return (next * 10).rounded() / 10
  }

  func setTool(_ tool: Tool) {
    view.tool = tool
    if tool != .selection && tool != .lasso { selection = [] }
    onOverlayChange?()
  }
}
