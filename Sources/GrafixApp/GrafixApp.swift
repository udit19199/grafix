import AppKit
import GrafixCore
import GrafixPort
import SwiftUI
import UniformTypeIdentifiers

/// The app's entry point. A snapshot request renders the ported chrome and
/// exits, so the UI can be checked without a window or Screen Recording access.
@main
enum GrafixMain {
  static func main() {
    if let request = SnapshotRequest(arguments: CommandLine.arguments) {
      let written = MainActor.assumeIsolated {
        PortSnapshot.write(
          chrome: request.chrome, style: request.style, to: request.path, size: request.size)
      }
      if !written {
        FileHandle.standardError.write(
          Data("port snapshot: could not write \(request.path)\n".utf8))
      }
      exit(written ? 0 : 1)
    }
    GrafixApp.main()
  }
}

/// Parses the command line for a port snapshot request.
struct SnapshotRequest {
  var path: String
  var chrome: PortEditorChrome
  var style: PortElementStyle
  var size: CGSize

  init?(arguments: [String]) {
    guard let flag = arguments.firstIndex(of: "--port-snapshot"),
      arguments.index(after: flag) < arguments.endIndex
    else {
      return nil
    }
    path = arguments[arguments.index(after: flag)]
    var chrome = PortEditorChrome()
    var style = PortElementStyle()
    var size = CGSize(width: 1280, height: 720)
    var index = 0
    while index < arguments.count {
      let argument = arguments[index]
      let next = index + 1 < arguments.count ? arguments[index + 1] : nil
      switch argument {
      case "--dark": chrome.dark = true
      case "--tool": if let next { chrome.activeTool = next }
      case "--selection-tool": if let next { chrome.preferredSelectionTool = next }
      case "--locked": chrome.toolLocked = true
      case "--pen-mode": chrome.penMode = true
      case "--zen": chrome.zenMode = true
      case "--extra-tools": chrome.extraToolsOpen = true
      case "--help-dialog": chrome.showingHelp = true
      case "--stroke": if let next { style.strokeColor = next }
      case "--background": if let next { style.backgroundColor = next }
      case "--stroke-width": if let next, let value = Double(next) { style.strokeWidth = value }
      case "--roughness": if let next, let value = Double(next) { style.roughness = value }
      case "--opacity": if let next, let value = Double(next) { style.opacity = value }
      case "--width": if let next, let value = Double(next) { size.width = value }
      case "--height": if let next, let value = Double(next) { size.height = value }
      default: break
      }
      index += 1
    }
    self.chrome = chrome
    self.style = style
    self.size = size
  }
}

struct GrafixApp: App {
  @StateObject private var model = EditorModel()
  var body: some Scene {
    WindowGroup {
      EditorView(model: model).frame(minWidth: 1000, minHeight: 680)
    }.commands {
      CommandGroup(replacing: .newItem) {
        Button("New Drawing") { model.newDrawing() }.keyboardShortcut("n")
        ForEach(PortedCommand.inMenu(.file)) { command in
          Button(command.title) { command.run(model) }.repoShortcut(command.menuKey)
        }
        // Exporting a .excalidraw file is Grafix's own action, so it keeps an
        // app-chosen key rather than one from the repo's table.
        Button("Export Excalidraw…") { model.export() }.keyboardShortcut(
          "s", modifiers: [.command, .shift])
      }
      CommandGroup(replacing: .undoRedo) {
        Button("Undo") { model.undo() }.keyboardShortcut("z").disabled(model.history.isEmpty)
        Button("Redo") { model.redo() }.keyboardShortcut("z", modifiers: [.command, .shift])
          .disabled(model.future.isEmpty)
      }
      // Tool shortcuts come from the repo's own tool table, so the native app
      // answers the same keys the web editor does.
      CommandMenu("Tools") {
        ForEach(PortTools.all, id: \.id) { tool in
          Button(tool.label) { model.chrome.activeTool = tool.id }
            .keyboardShortcut(tool.keyboardShortcut)
            .disabled(model.chrome.activeTool == tool.id)
        }
      }
      CommandMenu("View") {
        ForEach(PortedCommand.inMenu(.view)) { command in
          Button(command.title) { command.run(model) }.repoShortcut(command.menuKey)
        }
      }
      CommandGroup(replacing: .help) {
        ForEach(PortedCommand.inMenu(.help)) { command in
          Button(command.title) { command.run(model) }.repoShortcut(command.menuKey)
        }
      }
    }
  }
}

/// A menu command whose key comes from the repo's shortcut table.
///
/// One list drives both the menus and the dimming in the shortcuts dialog, so an
/// action is live in both places at once. The switch statements are exhaustive,
/// which is what keeps the two in step.
enum PortedCommand: String, CaseIterable, Identifiable {
  case loadScene
  case saveScene
  case toggleTheme
  case zenMode
  case zoomIn
  case zoomOut
  case resetZoom
  case toggleShortcuts

  var id: String { rawValue }

  /// The repo action whose key the menu item should use, or nil when the key
  /// belongs to the canvas instead of a menu. "?" is a plain character: as a
  /// menu key equivalent it would be taken away from every text field, so the
  /// canvas listens for it, exactly as the web editor does.
  var menuKey: String? {
    self == .toggleShortcuts ? nil : rawValue
  }

  /// Where the command appears in the menu bar.
  enum Menu {
    case file
    case view
    case help
  }

  var menu: Menu {
    switch self {
    case .loadScene, .saveScene: .file
    case .toggleTheme, .zenMode, .zoomIn, .zoomOut, .resetZoom: .view
    case .toggleShortcuts: .help
    }
  }

  static func inMenu(_ menu: Menu) -> [PortedCommand] {
    allCases.filter { $0.menu == menu }
  }

  var title: String {
    switch self {
    case .loadScene: "Open Excalidraw…"
    case .saveScene: "Save"
    case .toggleTheme: "Dark mode"
    case .zenMode: "Zen mode"
    case .zoomIn: "Zoom in"
    case .zoomOut: "Zoom out"
    case .resetZoom: "Reset zoom"
    case .toggleShortcuts: PortStrings.text(PortHelp.shortcutsKey)
    }
  }

  @MainActor func run(_ model: EditorModel) {
    switch self {
    case .loadScene: model.open()
    case .saveScene: model.save()
    case .toggleTheme: model.chrome.dark.toggle()
    case .zenMode: model.chrome.zenMode.toggle()
    case .zoomIn: model.zoom = min(5, model.zoom * 1.2)
    case .zoomOut: model.zoom = max(0.15, model.zoom / 1.2)
    case .resetZoom: model.zoom = 1
    case .toggleShortcuts: model.showingHelp = true
    }
  }

  /// The actions the menus answer, plus the ones the canvas itself answers,
  /// for the shortcuts dialog to mark as live.
  static var liveActions: [String] { allCases.map(\.rawValue) + canvasActions }

  /// Shortcuts no menu carries because the canvas handles the key directly:
  /// the canvas removes the selected element when Delete is pressed.
  static let canvasActions = ["deleteSelectedElements"]

  /// Menu commands whose keys are the app's own rather than the repo's, because
  /// the web editor reaches them through the browser's menus. Undo and redo are
  /// in the shortcut table's dialog but not in its action map.
  static let appBindings = ["Cmd+Z", "Cmd+Shift+Z"]
}

extension PortTool {
  /// The key that activates this tool as a menu shortcut, using the repo's own
  /// letter or number.
  var keyboardShortcut: KeyboardShortcut {
    if let numericKey, let character = numericKey.first {
      return KeyboardShortcut(KeyEquivalent(character))
    }
    let letter = letters.first?.first ?? "?"
    return KeyboardShortcut(
      KeyEquivalent(letter), modifiers: shiftRequired ? [.shift] : [])
  }
}

@MainActor final class EditorModel: ObservableObject {
  @Published var scene = SceneDocument()
  @Published var files: [URL] = []
  @Published var current: URL?
  @Published var collection = "Personal"
  /// Tool, lock, and theme state, shared with the ported toolbar.
  @Published var chrome = PortEditorChrome()
  /// The tool the canvas draws with, as a plain name for the AppKit view.
  var tool: String { chrome.activeTool }
  @Published var error: String?
  @Published var history: [SceneDocument] = []
  @Published var selected: String?
  @Published var showingChat = false
  /// Whether the shortcuts dialog is open.
  @Published var showingHelp = false
  @Published var future: [SceneDocument] = []
  @Published var zoom: CGFloat = 1
  @Published var strokeColor = "#1e1e1e"
  @Published var backgroundColor = "transparent"
  @Published var strokeWidth = 2.0
  @Published var roughness = 1.0
  @Published var opacity = 100.0
  /// The style the properties panel edits, mapped onto the element keys.
  var style: PortElementStyle {
    get {
      PortElementStyle(
        strokeColor: strokeColor,
        backgroundColor: backgroundColor,
        strokeWidth: strokeWidth,
        roughness: roughness,
        opacity: opacity
      )
    }
    set {
      if let selected {
        // One update, one undo step: the panel writes every field in a single
        // change rather than one change per field.
        change { document in
          var elements = document.elements
          if let index = elements.firstIndex(where: { $0["id"]?.stringValue == selected }) {
            elements[index]["strokeColor"] = .string(newValue.strokeColor)
            elements[index]["backgroundColor"] = .string(newValue.backgroundColor)
            elements[index]["strokeWidth"] = .number(newValue.strokeWidth)
            elements[index]["roughness"] = .number(newValue.roughness)
            elements[index]["opacity"] = .number(newValue.opacity)
          }
          document.elements = elements
        }
      }
      strokeColor = newValue.strokeColor
      backgroundColor = newValue.backgroundColor
      strokeWidth = newValue.strokeWidth
      roughness = newValue.roughness
      opacity = newValue.opacity
    }
  }
  @Published var presenting = false
  @Published var slide = 0
  let root: URL
  private var timer: Timer?
  private var unsaved = false
  private let recoveryID = UUID().uuidString
  var interacting = false
  init() {
    root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Grafix", isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      refresh()
    } catch { self.error = error.localizedDescription }
    timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.reloadExternal() }
    }
  }
  var directory: URL { root.appendingPathComponent(collection, isDirectory: true) }
  var sceneJSON: String { String(data: (try? scene.encoded()) ?? Data(), encoding: .utf8) ?? "{}" }
  var frames: [[String: JSONValue]] {
    scene.elements.filter {
      $0["type"]?.stringValue == "frame" && $0["isDeleted"]?.boolValue != true
    }
  }
  func refresh() {
    do { files = try SceneStore(directory: directory).list() } catch {
      self.error = error.localizedDescription
    }
  }
  func switchCollection(_ name: String) {
    guard !unsaved else {
      error = "Save or export the current drawing before switching collections."
      return
    }
    collection = name
    current = nil
    scene = SceneDocument()
    history = []
    future = []
    refresh()
  }
  func newDrawing() {
    guard !unsaved else {
      error = "Save or export the current drawing before creating another."
      return
    }
    selected = nil
    current = directory.appendingPathComponent(
      "Drawing-\(UUID().uuidString.prefix(8)).excalidraw")
    scene = SceneDocument()
    history = []
    future = []
    save()
  }
  func load(_ url: URL) {
    guard !unsaved else {
      error = "Save or export the current drawing before opening another."
      return
    }
    do {
      scene = try SceneStore(directory: url.deletingLastPathComponent()).load(
        name: url.lastPathComponent)
      current = url
      history = []
      future = []
      selected = nil
    } catch { self.error = error.localizedDescription }
  }
  func save() {
    unsaved = true
    if current == nil {
      current = directory.appendingPathComponent(
        "Drawing-\(UUID().uuidString.prefix(8)).excalidraw")
    }
    do {
      try FileManager.default.createDirectory(
        at: current!.deletingLastPathComponent(), withIntermediateDirectories: true)
      scene = try SceneStore(directory: current!.deletingLastPathComponent()).save(
        scene, name: current!.lastPathComponent)
      unsaved = false
      refresh()
    } catch {
      unsaved = true
      let recovery = root.appendingPathComponent("Recovery", isDirectory: true)
        .appendingPathComponent("Recovered-\(recoveryID).excalidraw")
      do {
        try FileManager.default.createDirectory(
          at: recovery.deletingLastPathComponent(), withIntermediateDirectories: true)
        try scene.encoded().write(to: recovery, options: .atomic)
        self.error =
          "\(error.localizedDescription) Your local changes are saved separately in \(recovery.path). Export to a new file to continue."
      } catch {
        self.error =
          "Save failed, including the recovery copy. Keep this window open and export your drawing. \(error.localizedDescription)"
      }
    }
  }
  func change(_ update: (inout SceneDocument) -> Void) {
    history.append(scene)
    future = []
    update(&scene)
    unsaved = true
    save()
  }
  func undo() {
    if let previous = history.popLast() {
      future.append(scene)
      scene.root = previous.root
      unsaved = true
      save()
    }
  }
  func redo() {
    if let next = future.popLast() {
      history.append(scene)
      scene.root = next.root
      save()
    }
  }
  func setStyle(_ key: String, value: JSONValue) {
    guard let selected else { return }
    change { document in
      var elements = document.elements
      if let index = elements.firstIndex(where: { $0["id"]?.stringValue == selected }) {
        elements[index][key] = value
      }
      document.elements = elements
    }
  }
  func applyJSON(_ json: String) {
    do {
      let proposed = try SceneDocument(data: Data(json.utf8))
      change { $0.root = proposed.root }
    } catch { self.error = error.localizedDescription }
  }
  func reloadExternal() {
    guard !unsaved, !interacting, let current, let data = try? Data(contentsOf: current),
      let other = try? SceneDocument(data: data), (try? other.encoded()) != (try? scene.encoded())
    else { return }
    history.append(scene)
    future = []
    scene =
      (try? SceneStore(directory: current.deletingLastPathComponent()).load(
        name: current.lastPathComponent)) ?? other
  }
  func open() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.json, UTType(filenameExtension: "excalidraw") ?? .data]
    if panel.runModal() == .OK, let url = panel.url { load(url) }
  }
  func export() {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = current?.lastPathComponent ?? "Drawing.excalidraw"
    if panel.runModal() == .OK, let url = panel.url {
      do {
        try scene.encoded().write(to: url, options: .atomic)
        scene = try SceneStore(directory: url.deletingLastPathComponent()).load(
          name: url.lastPathComponent)
        current = url
        unsaved = false
        refresh()
      } catch { self.error = error.localizedDescription }
    }
  }
}

struct EditorView: View {
  @ObservedObject var model: EditorModel
  @State private var newCollection = ""
  @State private var showingLibrary = false
  private var metrics: PortMetrics { PortMetrics.load(dark: model.chrome.dark) }

  var body: some View {
    ZStack {
      NativeCanvas(model: model).clipped()
      VStack(spacing: 0) {
        ZStack(alignment: .top) {
          HStack {
            island {
              iconButton(["library"], "Drawings and collections", selected: showingLibrary) {
                showingLibrary.toggle()
              }
            }
            Spacer()
            island {
              HStack(spacing: 4) {
                iconButton(["present", "presentation"], "Present frames") {
                  model.slide = 0
                  model.presenting = true
                }.disabled(model.frames.isEmpty)
                // AI chat is a Grafix panel, not part of Excalidraw, so it keeps
                // a system symbol rather than borrowing an editor icon.
                symbolButton("bubble.left.and.bubble.right", "AI chat", selected: model.showingChat)
                {
                  model.showingChat.toggle()
                }
              }
            }
          }
          PortToolbar(chrome: $model.chrome)
        }.padding(16)
        HStack(alignment: .top, spacing: 12) {
          if showingLibrary {
            library.frame(width: 245)
          } else if model.tool != "selection" || model.selected != nil {
            PortPropertiesPanel(style: styleBinding, dark: model.chrome.dark)
          }
          Spacer(minLength: 0)
          if model.showingChat {
            island {
              ChatPanel(sceneJSON: model.sceneJSON, applyScene: model.applyJSON).frame(width: 320)
            }
          }
        }.padding(.horizontal, 16)
        Spacer(minLength: 12)
        HStack(alignment: .bottom, spacing: 12) {
          island {
            HStack(spacing: 0) {
              iconButton(["zoomout", "zoomOut"], "Zoom out") {
                model.zoom = max(0.15, model.zoom / 1.2)
              }
              Button("\(Int(model.zoom * 100))%") { model.zoom = 1 }.buttonStyle(.plain).font(
                .system(size: 12)
              ).frame(width: 56, height: 36).accessibilityLabel("Reset zoom to 100 percent")
              iconButton(["zoomin", "zoomIn"], "Zoom in") { model.zoom = min(5, model.zoom * 1.2) }
            }
          }
          island {
            HStack(spacing: 0) {
              iconButton(["undo"], "Undo") { model.undo() }.disabled(model.history.isEmpty)
              iconButton(["redo"], "Redo") { model.redo() }.disabled(model.future.isEmpty)
            }
          }
          Spacer()
          Text(model.current?.deletingPathExtension().lastPathComponent ?? "Untitled")
            .font(.system(size: 12)).foregroundStyle(metrics.textColor.opacity(0.65)).padding(10)
        }.padding(16)
      }
      if model.showingHelp {
        PortHelpDialog(
          liveActions: PortedCommand.liveActions, liveBindings: PortedCommand.appBindings,
          dark: model.chrome.dark
        ) {
          model.showingHelp = false
        }
      }
    }
    .foregroundStyle(metrics.textColor)
    .background(PortTheme.color("default-bg-color", dark: model.chrome.dark) ?? .white)
    .preferredColorScheme(model.chrome.dark ? .dark : .light)
    .onChange(of: model.chrome.activeTool) { _, _ in model.selected = nil }
    .alert(
      "Grafix",
      isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })
    ) {
      Button("OK") { model.error = nil }
    } message: {
      Text(model.error ?? "")
    }
    .sheet(isPresented: $model.presenting) {
      VStack {
        HStack {
          Button("Previous") { model.slide = max(0, model.slide - 1) }
          Text("Frame \(model.slide + 1) / \(model.frames.count)")
          Button("Next") { model.slide = min(model.frames.count - 1, model.slide + 1) }
          Spacer()
          Button("Done") { model.presenting = false }
        }.padding()
        NativeCanvas(model: model, presentation: true)
      }.frame(minWidth: 1000, minHeight: 700)
    }
  }

  private var styleBinding: Binding<PortElementStyle> {
    Binding(
      get: { model.style },
      set: { model.style = $0 }
    )
  }

  private var library: some View {
    island {
      VStack(alignment: .leading, spacing: 16) {
        Text("Drawings").font(.system(size: 14, weight: .semibold))
        Picker(
          "Collection",
          selection: Binding(get: { model.collection }, set: { model.switchCollection($0) })
        ) {
          ForEach(collections, id: \.self) { Text($0).tag($0) }
        }
        HStack {
          TextField("New collection", text: $newCollection).textFieldStyle(.roundedBorder)
          Button {
            let name = newCollection.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !name.contains("/"), name != ".", name != ".." else { return }
            model.switchCollection(name)
            model.newDrawing()
            newCollection = ""
          } label: {
            Image(systemName: "plus")
          }.accessibilityLabel("Create collection")
        }
        ScrollView {
          VStack(alignment: .leading, spacing: 4) {
            if model.files.isEmpty {
              Text("No drawings in this collection.").font(.caption).foregroundStyle(.secondary)
                .padding(.vertical, 10)
            }
            ForEach(model.files, id: \.self) { url in
              Button {
                model.load(url)
              } label: {
                Label(url.deletingPathExtension().lastPathComponent, systemImage: "doc")
                  .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading).padding(8)
                  .background(
                    model.current == url ? metrics.selectedBackground : .clear,
                    in: RoundedRectangle(cornerRadius: 6))
              }.buttonStyle(.plain)
            }
          }
        }.frame(maxHeight: 300)
        Divider()
        Button("New drawing", systemImage: "plus") { model.newDrawing() }
        Button("Open…", systemImage: "folder") { model.open() }
        Button("Export…", systemImage: "square.and.arrow.up") { model.export() }
      }.font(.system(size: 12)).padding(12)
    }
  }

  /// Every free-floating panel in the editor sits in the repo's island: the same
  /// background, corner radius and shadow the web editor gives it.
  private func island<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    PortIsland(metrics: metrics, content: content)
  }

  /// A chrome button that draws one of the repo's own icons. `names` holds
  /// fallbacks, because the extractor's keys follow the component names the
  /// repo happens to use.
  private func iconButton(
    _ names: [String], _ label: String, selected: Bool = false, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      ZStack {
        RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
          .fill(selected ? metrics.selectedBackground : .clear)
        portIcon(names, selected: selected)
      }
      .frame(width: metrics.buttonSize, height: metrics.buttonSize)
    }
    .buttonStyle(.plain).help(label).accessibilityLabel(label)
  }

  /// Chrome with no Excalidraw counterpart, such as Grafix's own chat panel.
  private func symbolButton(
    _ symbol: String, _ label: String, selected: Bool = false, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: symbol).font(.system(size: 15))
        .frame(width: metrics.buttonSize, height: metrics.buttonSize)
        .background(
          selected ? metrics.selectedBackground : .clear,
          in: RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous))
    }
    .buttonStyle(.plain).help(label).accessibilityLabel(label)
  }

  /// Draws the first name the extractor actually produced, so a renamed icon
  /// leaves a gap instead of crashing.
  @ViewBuilder private func portIcon(_ names: [String], selected: Bool) -> some View {
    if let name = names.first(where: { PortIcons.all[$0] != nil }) {
      PortIconView(
        name: name, size: metrics.iconSize,
        color: selected ? metrics.selectedIconColor : metrics.iconColor)
    }
  }
  private var collections: [String] {
    Array(
      Set(
        ((try? FileManager.default.contentsOfDirectory(
          at: model.root, includingPropertiesForKeys: [.isDirectoryKey])) ?? []).filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
          }.map(\.lastPathComponent) + [model.collection])
    ).sorted()
  }
}
