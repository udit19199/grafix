import Foundation
import GrafixCore

func editorTools() -> [Tool] {
  [
    Tool(
      name: "get_editor_state",
      description:
        "What the Grafix app shows right now: the open scene (sceneId), the selected element ids with summaries, and the visible viewport. Call this first for requests like 'change the selected box' or 'add to this drawing', then use edit_scene_content with those ids. Returns openSceneId null when the app is not running or nothing is open.",
      inputSchema: schema(),
      run: { _, ws in
        guard let state = ws.readEditorState() else {
          return .json(.object([
            "running": false, "openSceneId": .null, "selection": [],
            "note": "No editor state found. The Grafix app is probably not open.",
          ]))
        }
        var out: [String: JSONValue] = [
          "running": true, "updated": iso(state.updated),
          "openSceneId": state.openSceneID.map(JSONValue.string) ?? .null,
          "selectedElementIds": .array(state.selectedElementIDs.map(JSONValue.string)),
        ]
        if let v = state.viewport, v.count == 4 {
          out["viewport"] = .object(["x": .num(v[0]), "y": .num(v[1]), "width": .num(v[2]), "height": .num(v[3])])
        }
        if let sceneID = state.openSceneID, let scene = try? ws.load(sceneID) {
          out["selection"] = .array(state.selectedElementIDs.compactMap { scene.element($0) }.map { .object(scene.summary(of: $0)) })
        } else {
          out["selection"] = []
        }
        return .json(.object(out))
      })
  ]
}
