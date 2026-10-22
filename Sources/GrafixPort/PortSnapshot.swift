import AppKit
import SwiftUI

/// Draws the ported editor chrome to an image.
///
/// The web editor can be screenshotted from a browser and the web editor itself
/// is the reference, so the native chrome has to be comparable to it. This
/// renders the native toolbar and properties panel offscreen: no window, no
/// Screen Recording permission, and the same bytes every run.
///
/// `NSHostingView` and the drawing calls below are main-actor bound, so the
/// snapshot entry points are too; the app calls them from `main()`.
@MainActor
public enum PortSnapshot {
  public static func png(
    chrome: PortEditorChrome,
    style: PortElementStyle,
    size: CGSize = CGSize(width: 1280, height: 720)
  ) -> Data? {
    let view = NSHostingView(
      rootView: PortChromePreview(chrome: chrome, style: style)
        .frame(width: size.width, height: size.height)
    )
    view.frame = CGRect(origin: .zero, size: size)
    // The web editor's light theme is the reference; keep the appearance fixed
    // so the image does not depend on the machine's setting.
    view.appearance = NSAppearance(named: chrome.dark ? .darkAqua : .aqua)
    view.layoutSubtreeIfNeeded()
    guard let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
      return nil
    }
    view.cacheDisplay(in: view.bounds, to: representation)
    return representation.representation(using: .png, properties: [:])
  }

  /// Writes a snapshot to a file and reports the path.
  @discardableResult
  public static func write(
    chrome: PortEditorChrome,
    style: PortElementStyle,
    to path: String,
    size: CGSize = CGSize(width: 1280, height: 720)
  ) -> Bool {
    guard let data = png(chrome: chrome, style: style, size: size) else {
      return false
    }
    return (try? data.write(to: URL(fileURLWithPath: path))) != nil
  }
}

/// The chrome as it appears over an empty canvas: the toolbar at the top, the
/// properties panel on the left, and the canvas filling the rest.
public struct PortChromePreview: View {
  @State private var chrome: PortEditorChrome
  @State private var style: PortElementStyle
  private let liveActions: [String]
  private let liveBindings: [String]

  public init(
    chrome: PortEditorChrome,
    style: PortElementStyle,
    liveActions: [String] = PortHelp.defaultLiveActions,
    liveBindings: [String] = PortHelp.defaultLiveBindings
  ) {
    self._chrome = State(initialValue: chrome)
    self._style = State(initialValue: style)
    self.liveActions = liveActions
    self.liveBindings = liveBindings
  }

  public var body: some View {
    let metrics = PortMetrics.load(dark: chrome.dark)
    ZStack(alignment: .topLeading) {
      (PortTheme.color("default-bg-color", dark: chrome.dark) ?? Color.white)
      VStack(alignment: .leading, spacing: 16) {
        PortToolbar(chrome: $chrome)
        PortPropertiesPanel(style: $style, dark: chrome.dark)
      }
      .padding(16)
      if chrome.showingHelp {
        PortHelpDialog(
          liveActions: liveActions, liveBindings: liveBindings, dark: chrome.dark, dismiss: {})
      }
    }
    .ignoresSafeArea()
    .environment(\.colorScheme, chrome.dark ? .dark : .light)
    .background(metrics.islandColor)
  }
}
