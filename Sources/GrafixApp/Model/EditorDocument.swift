import AppKit
import Foundation
import GrafixCore
import Observation

/// Tools, in Excalidraw's toolbar order. Raw values match Excalidraw's tool ids.
enum Tool: String, CaseIterable, Sendable {
  case hand, selection, lasso, rectangle, diamond, ellipse, arrow, line, freedraw, text, image, eraser,
    frame, embeddable, laser

  /// Keyboard shortcut (Excalidraw: Tools.tsx / shortcuts).
  var key: Character? {
    switch self {
    case .hand: "h"
    case .selection: "v"
    case .rectangle: "r"
    case .diamond: "d"
    case .ellipse: "o"
    case .arrow: "a"
    case .line: "l"
    case .freedraw: "p"
    case .text: "t"
    case .image: "9"
    case .eraser: "e"
    case .frame: "f"
    case .laser: "k"
    default: nil
    }
  }
  var numberKey: Character? {
    switch self {
    case .selection: "1"
    case .rectangle: "2"
    case .diamond: "3"
    case .ellipse: "4"
    case .arrow: "5"
    case .line: "6"
    case .freedraw: "7"
    case .text: "8"
    case .image: "9"
    case .eraser: "0"
    default: nil
    }
  }
  /// Tools that create an element by dragging a box.
  var createsShape: Bool { [.rectangle, .diamond, .ellipse, .frame, .embeddable].contains(self) }
  var elementType: ElementType? {
    switch self {
    case .rectangle: .rectangle
    case .diamond: .diamond
    case .ellipse: .ellipse
    case .arrow: .arrow
    case .line: .line
    case .freedraw: .freedraw
    case .text: .text
    case .frame: .frame
    case .embeddable: .embeddable
    case .image: .image
    default: nil
    }
  }
}

/// View state that is not part of the drawing (Excalidraw's AppState subset).
struct ViewState: Equatable {
  var tool: Tool = .selection
  /// Keep the tool after drawing (Excalidraw's tool lock, Q).
  var toolLocked = false
  var zoom: CGFloat = 1
  /// Scene coordinate shown at the view's top-left is (-scrollX, -scrollY).
  var scrollX: CGFloat = 0
  var scrollY: CGFloat = 0
  var grid = false
  var snapToObjects = false
  var zen = false
  var viewMode = false
  var penMode = false
  var showStats = false
}

/// One open scene: content, selection, history, persistence.
///
/// Every edit goes through `commit` (one undo step) or an interaction
/// (`beginInteraction` / `updateInteraction` / `endInteraction`, one undo step
/// for a whole drag). Both notify the canvas and schedule an autosave.
@MainActor @Observable
final class EditorDocument {
  // MARK: State

  let workspace: Workspace
  private(set) var sceneID: String?
  /// The drawing. Read freely; change only via commit/interaction APIs.
  @ObservationIgnored private(set) var scene = Scene()
  /// Bumped on every scene change; SwiftUI views observe this instead of `scene`.
  private(set) var revision = 0
  var selection: Set<String> = [] {
    didSet { if selection != oldValue { selectionChanged() } }
  }
  /// When set, clicks select inside this group (double-click into a group).
  var editingGroupID: String?
  var view = ViewState()
  /// Style for new elements and the properties panel when nothing is selected.
  var style = ItemStyle()
  var lastError: String?

  // MARK: Hooks

  /// Called after any scene change (canvas re-renders).
  @ObservationIgnored var onSceneChange: (() -> Void)?
  /// Called when only selection or view state changed.
  @ObservationIgnored var onOverlayChange: (() -> Void)?

  // MARK: History

  @ObservationIgnored private var undoStack: [Snapshot] = []
  @ObservationIgnored private var redoStack: [Snapshot] = []
  private(set) var canUndo = false
  private(set) var canRedo = false
  struct Snapshot {
    var elements: [Element]
    var files: [String: JSONValue]
    var selection: Set<String>
  }
  @ObservationIgnored private var interactionStart: Snapshot?

  // MARK: Persistence

  @ObservationIgnored private var saveTask: Task<Void, Never>?
  @ObservationIgnored private var lastDiskModified: Date?
  @ObservationIgnored private var syncedIDs: Set<String> = []
  @ObservationIgnored private var watcher: Timer?
  @ObservationIgnored private var dirty = false
  @ObservationIgnored private var stateTask: Task<Void, Never>?

  init(workspace: Workspace) {
    self.workspace = workspace
    if let data = UserDefaults.standard.data(forKey: "grafix.style"),
      let saved = try? JSONDecoder().decode(ItemStyle.self, from: data)
    {
      style = saved
    }
  }

  // MARK: - Loading

  func open(_ id: String) {
    flushSave()
    do {
      let loaded = try workspace.load(id)
      sceneID = id
      scene = loaded
      syncedIDs = Set(loaded.elements.map(\.id))
      lastDiskModified = (try? workspace.info(id))?.modified
      undoStack = []
      redoStack = []
      updateHistoryFlags()
      selection = []
      editingGroupID = nil
      restoreViewport()
      revision += 1
      onSceneChange?()
      startWatching()
      publishEditorState()
    } catch {
      lastError = error.localizedDescription
    }
  }

  func close() {
    flushSave()
    watcher?.invalidate()
    sceneID = nil
    scene = Scene()
    revision += 1
    onSceneChange?()
  }

  // MARK: - Editing

  /// Applies one undoable change. Commits with the same `coalesce` key within
  /// a second merge into one undo step (sliders, repeated nudges).
  func commit(coalesce: String? = nil, _ change: (inout Scene) -> Void) {
    let now = Date()
    if let coalesce, coalesce == lastCoalesceKey, now.timeIntervalSince(lastCommitAt) < 1, canUndo {
      // Same continuous edit: keep the existing undo snapshot.
    } else {
      pushUndo(snapshot())
    }
    lastCoalesceKey = coalesce
    lastCommitAt = now
    change(&scene)
    didChangeScene()
  }

  @ObservationIgnored private var lastCoalesceKey: String?
  @ObservationIgnored private var lastCommitAt = Date.distantPast

  /// Starts a continuous edit (drag, resize, drawing). Changes until
  /// `endInteraction` form one undo step.
  func beginInteraction() {
    if interactionStart == nil { interactionStart = snapshot() }
  }

  /// Live change during an interaction. Does not autosave until the end.
  /// SwiftUI is not notified here (only the canvas); panels refresh when the
  /// interaction ends, so a drag never re-renders SwiftUI per mouse event.
  func updateInteraction(_ change: (inout Scene) -> Void) {
    change(&scene)
    onSceneChange?()
  }

  func endInteraction(commit: Bool = true) {
    guard let start = interactionStart else { return }
    interactionStart = nil
    if commit, start.elements != scene.elements {
      pushUndo(start)
      didChangeScene()
    } else if !commit {
      restore(start)
    } else {
      revision += 1
    }
  }

  var isInteracting: Bool { interactionStart != nil }

  func undo() {
    guard let previous = undoStack.popLast() else { return }
    redoStack.append(snapshot())
    restore(previous)
    updateHistoryFlags()
  }

  func redo() {
    guard let next = redoStack.popLast() else { return }
    undoStack.append(snapshot())
    restore(next)
    updateHistoryFlags()
  }

  private func snapshot() -> Snapshot {
    Snapshot(elements: scene.elements, files: scene.files, selection: selection)
  }

  private func restore(_ s: Snapshot) {
    // Bump versions of changed elements so caches and merges notice the revert.
    let current = Dictionary(scene.elements.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    var elements = s.elements
    for i in elements.indices {
      if let now = current[elements[i].id], now != elements[i] {
        elements[i].version = max(now.version, elements[i].version) + 1
        elements[i].versionNonce = Element.randomSeed()
      }
    }
    scene.elements = elements
    scene.files = s.files
    selection = s.selection.filter { id in scene.element(id).map { !$0.isDeleted } ?? false }
    didChangeScene()
  }

  private func pushUndo(_ s: Snapshot) {
    undoStack.append(s)
    if undoStack.count > 200 { undoStack.removeFirst(undoStack.count - 200) }
    redoStack = []
    updateHistoryFlags()
  }

  private func updateHistoryFlags() {
    canUndo = !undoStack.isEmpty
    canRedo = !redoStack.isEmpty
  }

  private func didChangeScene() {
    revision += 1
    dirty = true
    onSceneChange?()
    scheduleSave()
  }

  // MARK: - Selection

  var selectedElements: [Element] {
    scene.elements.filter { selection.contains($0.id) && !$0.isDeleted }
  }

  /// The single selected element, if exactly one (ignoring its label).
  var singleSelection: Element? {
    let roots = selectedElements.filter { $0.containerId == nil || !selection.contains($0.containerId!) }
    return roots.count == 1 ? roots[0] : nil
  }

  func select(_ ids: Set<String>) {
    selection = scene.withLabels(ids)
  }

  func selectAll() {
    selection = Set(scene.visibleElements.filter { !$0.locked }.map(\.id))
  }

  private func selectionChanged() {
    onOverlayChange?()
    publishEditorState()
  }

  // MARK: - Style

  /// Sets a style value on the selection (and labels for text properties) and
  /// remembers it for new elements, like Excalidraw's property actions.
  func setStyle(
    _ apply: (inout ItemStyle) -> Void, element change: @escaping (inout Element) -> Void, labels: Bool = false,
    coalesce: String? = nil
  ) {
    apply(&style)
    if let data = try? JSONEncoder().encode(style) { UserDefaults.standard.set(data, forKey: "grafix.style") }
    guard !selection.isEmpty else { return }
    let ids = selection
    commit(coalesce: coalesce) { scene in
      scene.updateEach(ids, includeLabels: labels, change)
      for id in ids {
        if scene.element(id)?.boundTextID != nil { scene.layoutLabel(of: id) }
        if let c = scene.element(id)?.containerId { scene.layoutLabel(of: c) }
      }
      scene.updateBoundArrows(of: ids)
    }
  }

  // MARK: - Viewport

  func setZoom(_ zoom: CGFloat, around screenPoint: CGPoint? = nil, viewSize: CGSize) {
    let clamped = min(max(zoom, 0.1), 30)
    let anchor = screenPoint ?? CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
    let sceneAnchor = sceneCoordinates(anchor)
    view.zoom = clamped
    view.scrollX = anchor.x / clamped - sceneAnchor.x
    view.scrollY = anchor.y / clamped - sceneAnchor.y
    onOverlayChange?()
    saveViewportSoon()
  }

  func scroll(by delta: CGPoint) {
    view.scrollX += delta.x / view.zoom
    view.scrollY += delta.y / view.zoom
    saveViewportSoon()
  }

  func sceneCoordinates(_ screen: CGPoint) -> CGPoint {
    CGPoint(x: screen.x / view.zoom - view.scrollX, y: screen.y / view.zoom - view.scrollY)
  }

  func screenCoordinates(_ scenePoint: CGPoint) -> CGPoint {
    CGPoint(x: (scenePoint.x + view.scrollX) * view.zoom, y: (scenePoint.y + view.scrollY) * view.zoom)
  }

  /// Fits `rect` (scene coords) into the view with padding (zoomToFit).
  func zoom(toFit rect: CGRect, viewSize: CGSize, padding: CGFloat = 60, maxZoom: CGFloat = 1) {
    guard rect.width > 0 || rect.height > 0, viewSize.width > 0 else { return }
    let z = min((viewSize.width - padding * 2) / max(rect.width, 1), (viewSize.height - padding * 2) / max(rect.height, 1), maxZoom)
    view.zoom = max(0.1, z)
    view.scrollX = viewSize.width / 2 / view.zoom - rect.midX
    view.scrollY = viewSize.height / 2 / view.zoom - rect.midY
    onOverlayChange?()
    saveViewportSoon()
  }

  @ObservationIgnored private var viewportTask: Task<Void, Never>?
  private func saveViewportSoon() {
    viewportTask?.cancel()
    viewportTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(400))
      guard let self, !Task.isCancelled, let id = self.sceneID else { return }
      UserDefaults.standard.set([self.view.zoom, self.view.scrollX, self.view.scrollY], forKey: "grafix.viewport.\(id)")
      self.publishEditorState()
    }
  }

  private func restoreViewport() {
    if let id = sceneID, let v = UserDefaults.standard.array(forKey: "grafix.viewport.\(id)") as? [CGFloat], v.count == 3 {
      view.zoom = v[0]
      view.scrollX = v[1]
      view.scrollY = v[2]
    } else {
      view.zoom = 1
      view.scrollX = 0
      view.scrollY = 0
      pendingFit = true
    }
  }

  /// Set when a scene opens without a saved viewport; the canvas fits content once sized.
  @ObservationIgnored var pendingFit = false

  // MARK: - Saving

  private func scheduleSave() {
    saveTask?.cancel()
    saveTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(350))
      guard !Task.isCancelled else { return }
      self?.save()
    }
  }

  /// Saves now if there are unsaved changes.
  func flushSave() {
    saveTask?.cancel()
    if dirty { save() }
  }

  /// Writes the scene under the workspace lock, merging any edits an agent made
  /// to the file since we last read it.
  private func save() {
    guard let id = sceneID, dirty, interactionStart == nil else { return }
    let local = scene
    let synced = syncedIDs
    let knownModified = lastDiskModified
    let ws = workspace
    do {
      let merged: Scene? = try ws.withLock {
        let info = try? ws.info(id)
        var result: Scene? = nil
        if let modified = info?.modified, let known = knownModified, modified > known,
          let disk = try? ws.load(id)
        {
          result = local.merged(with: disk, syncedIDs: synced)
        }
        try ws.save(result ?? local, to: id)
        return result
      }
      if let merged {
        scene = merged
        revision += 1
        onSceneChange?()
      }
      syncedIDs = Set(scene.elements.map(\.id))
      lastDiskModified = (try? ws.info(id))?.modified
      dirty = false
      snapshotRevisionIfDue()
    } catch {
      lastError = "Could not save: \(error.localizedDescription)"
    }
  }

  @ObservationIgnored private var lastRevisionAt = Date.distantPast

  /// Keeps a version-history snapshot at most every 5 minutes of editing.
  private func snapshotRevisionIfDue() {
    guard let id = sceneID, Date().timeIntervalSince(lastRevisionAt) > 300 else { return }
    lastRevisionAt = Date()
    let ws = workspace
    let snapshot = scene
    DispatchQueue.global(qos: .utility).async { _ = try? ws.saveRevision(snapshot, of: id) }
  }

  /// Replaces the scene with an older version (one undo step).
  func restore(revision: Workspace.Revision) {
    guard let old = try? workspace.loadRevision(revision) else { return }
    let current = Dictionary(scene.elements.map { ($0.id, $0.version) }, uniquingKeysWith: { a, _ in a })
    commit { scene in
      var elements = old.elements
      // Restored elements must win over the current ones when merged.
      for i in elements.indices {
        elements[i].version = max(elements[i].version, current[elements[i].id] ?? 0) + 1
        elements[i].versionNonce = Element.randomSeed()
      }
      // Elements created after the snapshot are deleted, not dropped, so merges stay consistent.
      let keep = Set(elements.map(\.id))
      for e in scene.elements where !keep.contains(e.id) {
        var gone = e
        gone.isDeleted = true
        gone.bump()
        elements.append(gone)
      }
      scene.elements = elements
      scene.files.merge(old.files) { a, _ in a }
      scene.appState = old.appState
    }
  }

  /// Polls the file for changes by agents/other apps and merges them in.
  private func startWatching() {
    watcher?.invalidate()
    watcher = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.checkDisk() }
    }
  }

  private func checkDisk() {
    guard let id = sceneID, interactionStart == nil, !dirty,
      let modified = (try? workspace.info(id))?.modified, let known = lastDiskModified, modified > known,
      let disk = try? workspace.load(id)
    else { return }
    let merged = scene.merged(with: disk, syncedIDs: syncedIDs)
    lastDiskModified = modified
    guard merged != scene else { return }
    pushUndo(snapshot())
    scene = merged
    syncedIDs = Set(scene.elements.map(\.id))
    selection = selection.filter { scene.element($0).map { !$0.isDeleted } ?? false }
    revision += 1
    onSceneChange?()
  }

  /// Tells agents (via .grafix/editor.json) what is open and selected.
  private func publishEditorState() {
    stateTask?.cancel()
    stateTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(150))
      guard let self, !Task.isCancelled else { return }
      self.workspace.writeEditorState(
        Workspace.EditorState(
          openSceneID: self.sceneID, selectedElementIDs: Array(self.selection),
          viewport: [-self.view.scrollX, -self.view.scrollY, self.viewSize.width / self.view.zoom, self.viewSize.height / self.view.zoom]))
    }
  }

  /// Last known canvas size in points (set by the canvas).
  @ObservationIgnored var viewSize = CGSize(width: 1200, height: 800)
}
