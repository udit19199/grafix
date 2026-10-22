import AppKit
import SwiftUI

/// Invisible view that takes first responder and forwards key presses
/// (SwiftUI's onKeyPress needs focus, which an overlay does not get reliably).
struct PresentationKeys: NSViewRepresentable {
  var onKey: (NSEvent) -> Bool

  func makeNSView(context: Context) -> KeyView {
    let v = KeyView()
    v.onKey = onKey
    return v
  }

  func updateNSView(_ v: KeyView, context: Context) { v.onKey = onKey }

  final class KeyView: NSView {
    var onKey: ((NSEvent) -> Bool)?
    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      DispatchQueue.main.async { [weak self] in self?.window?.makeFirstResponder(self) }
    }
    override func keyDown(with event: NSEvent) {
      if onKey?(event) != true { super.keyDown(with: event) }
    }
    override func resignFirstResponder() -> Bool {
      DispatchQueue.main.async { [weak self] in
        guard let self, let w = window, w.firstResponder !== self, !(w.firstResponder is NSText) else { return }
        w.makeFirstResponder(self)
      }
      return true
    }
  }
}
