import AppKit
import GrafixCore
import GrafixRender
import UniformTypeIdentifiers

/// Export / import (Excalidraw's "Save to…", "Export image", clipboard copy).
@MainActor
enum ExportActions {
  /// The selection (or whole scene) as a scene of its own, for exporting.
  static func exportScene(_ doc: EditorDocument, selectionOnly: Bool) -> Scene {
    guard selectionOnly, doc.hasSelection else { return doc.scene }
    let ids = doc.scene.withLabels(doc.scene.expandedSelection(doc.selection))
    var s = doc.scene
    s.elements = s.elements.filter { ids.contains($0.id) }
    return s
  }

  static func copyPNG(_ doc: EditorDocument, selectionOnly: Bool) {
    let scene = exportScene(doc, selectionOnly: selectionOnly)
    guard let img = SceneRenderer.image(scene, scale: 2, padding: 10, dark: true), let png = SceneRenderer.pngData(img) else { return }
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setData(png, forType: .png)
  }

  static func exportPNG(_ doc: EditorDocument, selectionOnly: Bool = false, scale: CGFloat = 2, background: Bool = true) {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.png]
    panel.nameFieldStringValue = (doc.sceneID?.split(separator: "/").last.map(String.init) ?? "Drawing") + ".png"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    let scene = exportScene(doc, selectionOnly: selectionOnly)
    guard let img = SceneRenderer.image(scene, scale: scale, padding: 10, dark: true, background: background),
      let data = SceneRenderer.pngData(img)
    else { return }
    try? data.write(to: url)
  }

  static func exportSVG(_ doc: EditorDocument, selectionOnly: Bool = false, background: Bool = true) {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.svg]
    panel.nameFieldStringValue = (doc.sceneID?.split(separator: "/").last.map(String.init) ?? "Drawing") + ".svg"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    let scene = exportScene(doc, selectionOnly: selectionOnly)
    guard let svg = SVGExporter.svg(scene, dark: true, background: background) else { return }
    try? svg.write(to: url, atomically: true, encoding: .utf8)
  }

  static func exportPDF(_ doc: EditorDocument, slides: Bool) {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.pdf]
    panel.nameFieldStringValue = (doc.sceneID?.split(separator: "/").last.map(String.init) ?? "Drawing") + ".pdf"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    let frames = slides ? doc.scene.slideFrames.map(\.id) : nil
    guard let data = SceneRenderer.pdf(doc.scene, frameIDs: frames?.isEmpty == true ? nil : frames, dark: true) else { return }
    try? data.write(to: url)
  }

  /// Saves a copy as a standalone .excalidraw file (opens in excalidraw.com).
  static func exportExcalidraw(_ doc: EditorDocument) {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [UTType(filenameExtension: "excalidraw") ?? .json]
    panel.nameFieldStringValue = (doc.sceneID?.split(separator: "/").last.map(String.init) ?? "Drawing") + ".excalidraw"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    try? doc.scene.encoded().write(to: url)
  }
}
