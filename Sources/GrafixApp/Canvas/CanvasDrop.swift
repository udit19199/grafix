import AppKit
import GrafixCore
import UniformTypeIdentifiers

/// Drag & drop onto the canvas: images become image elements, .excalidraw
/// files are merged in at the drop point (like Excalidraw's file drop).
extension CanvasView {
  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    let point = document.sceneCoordinates(convert(sender.draggingLocation, from: nil))
    let pb = sender.draggingPasteboard
    // Library sidebar tiles drag a "grafix-library:<itemID>[,<itemID>…]" string.
    if let text = pb.string(forType: .string), text.hasPrefix("grafix-library:") {
      let store = LibraryStore.shared(for: document.workspace)
      let ids = text.dropFirst("grafix-library:".count).split(separator: ",").map(String.init)
      var created: [String] = []
      var offset: CGFloat = 0
      document.commit { scene in
        for id in ids {
          guard let item = store.item(id) else { continue }
          created += scene.insert(item, at: CGPoint(x: point.x + offset, y: point.y + offset))
          offset += 30
        }
      }
      if !created.isEmpty { document.select(Set(created)) }
      return !created.isEmpty
    }
    if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
      var offset: CGFloat = 0
      for url in urls {
        let at = CGPoint(x: point.x + offset, y: point.y + offset)
        offset += 30
        guard let data = try? Data(contentsOf: url) else { continue }
        if url.pathExtension == "excalidraw" || url.pathExtension == "json", let scene = try? Scene(data: data) {
          insertScene(scene, at: at)
        } else if let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image) {
          if type == .svg, let image = NSImage(data: data), let tiff = image.tiffRepresentation,
            let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
          {
            document.insertImage(data: png, mimeType: "image/png", at: at)
          } else {
            document.insertImage(data: data, mimeType: type.preferredMIMEType ?? "image/png", at: at)
          }
        }
      }
      return true
    }
    if let data = pb.data(forType: .png) {
      document.insertImage(data: data, mimeType: "image/png", at: point)
      return true
    }
    if let tiff = pb.data(forType: .tiff), let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
      document.insertImage(data: png, mimeType: "image/png", at: point)
      return true
    }
    return false
  }

  /// Adds another scene's elements centred at `point`.
  func insertScene(_ other: Scene, at point: CGPoint) {
    let visible = other.visibleElements
    guard !visible.isEmpty else { return }
    var temp = Scene(elements: visible, files: other.files)
    let ids = Set(visible.map(\.id))
    guard let b = temp.bounds(of: ids) else { return }
    let created = temp.duplicate(ids, offset: CGPoint(x: point.x - b.midX, y: point.y - b.midY))
    let copies = temp.elements.filter { !ids.contains($0.id) }
    document.commit { scene in
      scene.elements.append(contentsOf: copies)
      for (k, v) in other.files where scene.files[k] == nil { scene.files[k] = v }
    }
    document.select(Set(created))
  }
}

/// Copy / paste styles (Excalidraw: Cmd+Option+C / Cmd+Option+V).
extension EditorDocument {
  private static var copiedStyle: Element?

  func copyStyles() {
    Self.copiedStyle = singleSelection ?? selectedElements.first
  }

  func pasteStyles() {
    guard let s = Self.copiedStyle, hasSelection else { return }
    let ids = selection
    commit { scene in
      scene.updateEach(ids) { e in
        e.strokeColor = s.strokeColor
        if !e.isText { e.backgroundColor = s.backgroundColor }
        e.fillStyle = s.fillStyle
        e.strokeWidth = s.strokeWidth
        e.strokeStyle = s.strokeStyle
        e.roughness = s.roughness
        e.opacity = s.opacity
        if e.isText && s.isText {
          e.fontFamily = s.fontFamily
          e.fontSize = s.fontSize
          e.textAlign = s.textAlign
          e.lineHeight = s.lineHeight
        }
        if e.type == .arrow && s.type == .arrow {
          e.startArrowhead = s.startArrowhead
          e.endArrowhead = s.endArrowhead
        }
      }
      for id in ids where scene.element(id)?.boundTextID != nil { scene.layoutLabel(of: id) }
      for id in ids { if let c = scene.element(id)?.containerId { scene.layoutLabel(of: c) } }
    }
  }
}
