import AppKit
import GrafixCore
import GrafixRender

/// In-place text editing (Excalidraw's textWysiwyg.tsx): an NSTextView laid
/// exactly over the text element, using the same font, size and alignment.
@MainActor
final class TextEditorOverlay: NSObject, NSTextViewDelegate {
  let elementID: String
  weak var canvas: CanvasView?
  let textView: NSTextView
  private var finished = false

  init(elementID: String, canvas: CanvasView) {
    self.elementID = elementID
    self.canvas = canvas
    textView = EditorTextView(frame: .zero)
    super.init()
    textView.delegate = self
    textView.drawsBackground = false
    textView.isRichText = false
    textView.allowsUndo = true
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.isAutomaticSpellingCorrectionEnabled = false
    textView.isAutomaticTextReplacementEnabled = false
    textView.textContainerInset = .zero
    textView.textContainer?.lineFragmentPadding = 0
    textView.focusRingType = .none
    (textView as? EditorTextView)?.onCommit = { [weak self] in self?.commit() }
    if let e = canvas.document.scene.element(elementID) {
      textView.string = e.originalText
    }
    canvas.addSubview(textView)
    reposition()
    canvas.window?.makeFirstResponder(textView)
    textView.selectAll(nil)
  }

  var element: Element? { canvas?.document.scene.element(elementID) }

  /// Matches the editor to the element's on-screen position and style.
  func reposition() {
    guard let canvas, let e = element else { return }
    let doc = canvas.document
    let z = doc.view.zoom
    let font = Fonts.font(family: e.fontFamily, size: e.fontSize * z) as NSFont
    let para = NSMutableParagraphStyle()
    para.alignment = e.textAlign == .center ? .center : e.textAlign == .right ? .right : .left
    let lineHeight = e.fontSize * e.lineHeight * z
    para.minimumLineHeight = lineHeight
    para.maximumLineHeight = lineHeight
    let baseline = TextLayout.baselineOffset(family: e.fontFamily, size: e.fontSize * z, lineHeightPx: lineHeight)
    let color = NSColor(cgColor: CSSColor.cgColor(e.strokeColor, dark: true)) ?? .labelColor
    textView.typingAttributes = [.font: font, .foregroundColor: color, .paragraphStyle: para]
    _ = baseline
    textView.font = font
    textView.textColor = color
    textView.alignment = para.alignment
    textView.defaultParagraphStyle = para
    if let storage = textView.textStorage {
      storage.setAttributes(textView.typingAttributes, range: NSRange(location: 0, length: storage.length))
    }
    textView.insertionPointColor = color

    var frame: CGRect
    let container = e.containerId.flatMap { doc.scene.element($0) }
    if let container {
      let maxW = container.labelMaxWidth(fontSize: e.fontSize)
      let origin: CGPoint
      if container.type == .arrow {
        let mid = container.pathMidpoint
        origin = CGPoint(x: mid.x - maxW / 2, y: mid.y - e.height / 2)
      } else {
        origin = CGPoint(x: container.labelOrigin.x, y: e.y)
      }
      let screen = doc.screenCoordinates(origin)
      frame = CGRect(x: screen.x, y: screen.y, width: maxW * z, height: max(e.height, e.fontSize * e.lineHeight) * z)
      textView.textContainer?.widthTracksTextView = true
      textView.isHorizontallyResizable = false
    } else {
      let screen = doc.screenCoordinates(CGPoint(x: e.x, y: e.y))
      let w = e.autoResize ? max(e.width, 4) + e.fontSize : e.width
      frame = CGRect(x: screen.x, y: screen.y, width: w * z, height: max(e.height, e.fontSize * e.lineHeight) * z)
      textView.textContainer?.widthTracksTextView = !e.autoResize
      textView.isHorizontallyResizable = e.autoResize
      textView.textContainer?.containerSize = CGSize(width: e.autoResize ? 100_000 : e.width * z, height: 100_000)
    }
    let angle = container?.type == .arrow ? 0 : e.angle
    textView.frameCenterRotation = 0
    textView.frame = frame
    if angle != 0 { textView.frameCenterRotation = -angle * 180 / .pi }
  }

  func textDidChange(_ notification: Notification) {
    guard let canvas else { return }
    let text = textView.string
    let id = elementID
    canvas.document.updateInteraction { scene in
      guard let i = scene.indexOf(id) else { return }
      scene.elements[i].originalText = text
      scene.elements[i].text = text
      if let c = scene.elements[i].containerId {
        scene.elements[i].bump()
        scene.layoutLabel(of: c)
      } else {
        scene.elements[i].fitText()
        scene.elements[i].bump()
      }
    }
    reposition()
  }

  func commit() {
    guard !finished, let canvas else { return }
    finished = true
    let id = elementID
    let text = textView.string
    let doc = canvas.document
    doc.updateInteraction { scene in
      guard let e = scene.element(id) else { return }
      if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        scene.delete([id])
        if let c = e.containerId { scene.updateEach([c]) { $0.boundElements?.removeAll { $0.id == id } } }
      } else if let c = e.containerId {
        scene.layoutLabel(of: c)
      }
    }
    doc.endInteraction()
    textView.removeFromSuperview()
    canvas.textEditor = nil
    canvas.window?.makeFirstResponder(canvas)
    canvas.requestRender()
    if let e = doc.scene.element(id), !e.isDeleted {
      doc.select([e.containerId ?? id])
    }
    if !doc.view.toolLocked, doc.view.tool == .text { doc.setTool(.selection) }
  }
}

/// Escape and Cmd+Enter finish editing, like Excalidraw.
final class EditorTextView: NSTextView {
  var onCommit: (() -> Void)?
  override func keyDown(with event: NSEvent) {
    if event.keyCode == 53 || (event.keyCode == 36 && event.modifierFlags.contains(.command)) {
      onCommit?()
      return
    }
    super.keyDown(with: event)
  }
  override func resignFirstResponder() -> Bool {
    let ok = super.resignFirstResponder()
    if ok { DispatchQueue.main.async { [weak self] in self?.onCommit?() } }
    return ok
  }
}

extension CanvasView {
  func beginTextEditing(_ id: String) {
    textEditor?.commit()
    document.beginInteraction()
    document.selection = []
    textEditor = TextEditorOverlay(elementID: id, canvas: self)
    requestRender()
  }

  /// Edits (creating if needed) the label of a shape or arrow.
  func beginLabelEditing(container id: String, at point: CGPoint? = nil) {
    guard let container = document.scene.element(id), container.canHaveLabel else { return }
    if let label = container.boundTextID, document.scene.element(label)?.isDeleted == false {
      beginTextEditing(label)
      return
    }
    document.beginInteraction()
    var labelID: String?
    let style = document.style
    document.updateInteraction { scene in
      labelID = scene.setLabel("x", on: id, fontSize: style.fontSize, fontFamily: style.fontFamily, strokeColor: container.strokeColor)
      if let l = labelID, let i = scene.indexOf(l) {
        scene.elements[i].text = ""
        scene.elements[i].originalText = ""
      }
    }
    guard let labelID else {
      document.endInteraction(commit: false)
      return
    }
    document.selection = []
    textEditor = TextEditorOverlay(elementID: labelID, canvas: self)
    requestRender()
  }

  /// New free-standing text at `p`; clicking a shape with the text tool edits its label instead.
  func createText(at p: CGPoint) {
    if document.view.tool == .text, let hit = labelContainer(at: p) {
      beginLabelEditing(container: hit.id)
      return
    }
    var e = Element.makeText("", x: p.x, y: p.y, style: document.style)
    e.height = e.fontSize * e.lineHeight
    e.y = p.y - e.height / 2
    document.beginInteraction()
    document.updateInteraction { scene in
      scene.elements.append(e)
      scene.adoptIntoFrames([e.id])
    }
    document.selection = []
    textEditor = TextEditorOverlay(elementID: e.id, canvas: self)
    requestRender()
  }
}
