import AppKit
import GrafixCore
import SwiftUI

@main
struct GrafixApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
  @FocusedValue(\.appModel) private var focusedModel

  var body: some SwiftUI.Scene {
    WindowGroup {
      WindowRoot()
        .frame(minWidth: 1000, minHeight: 640)
    }
    .defaultSize(width: 1440, height: 900)
    .windowStyle(.hiddenTitleBar)
    .commands { AppCommands(model: focusedModel) }
  }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    Fonts.register()
    NSWindow.allowsAutomaticWindowTabbing = true
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
  }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

/// One window: owns its AppModel (open scene, panels).
struct WindowRoot: View {
  @State private var model = AppModel()
  var body: some View {
    EditorRootView(model: model)
      .focusedSceneValue(\.appModel, model)
      .onAppear { DebugSnapshot.scheduleIfRequested(model: model) }
  }
}

struct AppModelKey: FocusedValueKey { typealias Value = AppModel }
extension FocusedValues {
  var appModel: AppModel? {
    get { self[AppModelKey.self] }
    set { self[AppModelKey.self] = newValue }
  }
}
