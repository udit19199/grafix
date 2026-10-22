import AppKit
import Foundation
import GrafixCore
import Observation

/// Per-window state: which collection/scene is open and which panels show.
/// Each window (or tab, Cmd+T) has its own AppModel and EditorDocument.
@MainActor @Observable
final class AppModel {
  let workspace: Workspace
  let document: EditorDocument
  var collections: [Workspace.Collection] = []
  var scenes: [Workspace.SceneInfo] = []
  /// The collection shown in the workspace sidebar.
  var currentCollection: String = Workspace.defaultCollection
  var showWorkspace = true
  /// Right sidebar: nil, "slides" or "library".
  var rightPanel: String? = nil
  var showChat = false
  var showHelp = false
  var showCommandPalette = false
  var showFind = false
  var showHistory = false
  var presenting = false
  var presentingSlide = 0
  var error: String?

  init(workspace: Workspace = Workspace()) {
    self.workspace = workspace
    self.document = EditorDocument(workspace: workspace)
    refresh()
    openInitialScene()
  }

  func refresh() {
    do {
      collections = try workspace.listCollections()
      if collections.isEmpty {
        try workspace.createCollection(Workspace.defaultCollection)
        collections = try workspace.listCollections()
      }
      if !collections.contains(where: { $0.name == currentCollection }), let first = collections.first {
        currentCollection = first.name
      }
      scenes = try workspace.listScenes(in: currentCollection)
    } catch {
      self.error = error.localizedDescription
    }
  }

  private func openInitialScene() {
    let last = UserDefaults.standard.string(forKey: "grafix.lastScene")
    if let last, (try? workspace.info(last)) != nil {
      currentCollection = String(last.split(separator: "/").first ?? "")
      refresh()
      open(last)
    } else if let first = scenes.first {
      open(first.id)
    } else {
      newScene()
    }
  }

  func open(_ sceneID: String) {
    document.open(sceneID)
    UserDefaults.standard.set(sceneID, forKey: "grafix.lastScene")
    if let c = sceneID.split(separator: "/").first.map(String.init), c != currentCollection {
      currentCollection = c
      refresh()
    }
  }

  func selectCollection(_ name: String) {
    currentCollection = name
    refresh()
  }

  @discardableResult
  func newScene(in collection: String? = nil, name: String = "Untitled") -> String? {
    do {
      let info = try workspace.createScene(in: collection ?? currentCollection, name: name, unique: true)
      refresh()
      open(info.id)
      return info.id
    } catch {
      self.error = error.localizedDescription
      return nil
    }
  }

  func newCollection(_ name: String) {
    do {
      try workspace.createCollection(name)
      currentCollection = name
      refresh()
    } catch { self.error = error.localizedDescription }
  }

  func renameScene(_ id: String, to name: String) {
    do {
      let wasOpen = document.sceneID == id
      if wasOpen { document.flushSave() }
      let info = try workspace.renameScene(id, to: name)
      refresh()
      if wasOpen { open(info.id) }
    } catch { self.error = error.localizedDescription }
  }

  func duplicateScene(_ id: String) {
    do {
      document.flushSave()
      let info = try workspace.duplicateScene(id)
      refresh()
      open(info.id)
    } catch { self.error = error.localizedDescription }
  }

  func moveScene(_ id: String, to collection: String) {
    do {
      let wasOpen = document.sceneID == id
      if wasOpen { document.flushSave() }
      let info = try workspace.moveScene(id, toCollection: collection)
      refresh()
      if wasOpen { open(info.id) }
    } catch { self.error = error.localizedDescription }
  }

  /// Moves the scene file to the Trash.
  func trashScene(_ id: String) {
    do {
      if document.sceneID == id { document.close() }
      try workspace.trashScene(id)
      refresh()
      if document.sceneID == nil {
        if let first = scenes.first { open(first.id) } else { newScene() }
      }
    } catch { self.error = error.localizedDescription }
  }

  func renameCollection(_ name: String, to newName: String) {
    do {
      document.flushSave()
      let openID = document.sceneID
      try workspace.renameCollection(name, to: newName)
      if currentCollection == name { currentCollection = newName }
      refresh()
      if let openID, openID.hasPrefix(name + "/") { open(newName + openID.dropFirst(name.count)) }
    } catch { self.error = error.localizedDescription }
  }

  func trashCollection(_ name: String) {
    do {
      if document.sceneID?.hasPrefix(name + "/") == true { document.close() }
      try workspace.trashCollection(name)
      refresh()
      if document.sceneID == nil {
        if let first = scenes.first { open(first.id) } else { newScene() }
      }
    } catch { self.error = error.localizedDescription }
  }

  var currentSceneName: String {
    document.sceneID.map { String($0.split(separator: "/").last ?? "") } ?? "Untitled"
  }

  /// Imports an .excalidraw file from disk into the current collection.
  func importFile() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.init(filenameExtension: "excalidraw") ?? .json, .json]
    panel.allowsMultipleSelection = true
    guard panel.runModal() == .OK else { return }
    var last: String?
    for url in panel.urls {
      do {
        let scene = try Scene(data: Data(contentsOf: url))
        let info = try workspace.createScene(
          in: currentCollection, name: url.deletingPathExtension().lastPathComponent, scene: scene, unique: true)
        last = info.id
      } catch { self.error = "\(url.lastPathComponent): \(error.localizedDescription)" }
    }
    refresh()
    if let last { open(last) }
  }
}
