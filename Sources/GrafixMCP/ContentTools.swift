import Foundation
import GrafixCore

private let sceneIdProp = prop(
  "string", "Scene id in the form 'Collection/Scene name', e.g. 'Personal/My scene'. Get ids from list_scenes.")

/// Full Excalidraw JSON for the scene, without deleted elements or file data.
func contentJSON(of scene: Scene) -> JSONValue {
  var files: [String: JSONValue] = [:]
  for (id, value) in scene.files {
    var f = value.object ?? [:]
    f.removeValue(forKey: "dataURL")
    files[id] = .object(f)
  }
  return .object([
    "type": "excalidraw",
    "elements": .array(scene.visibleElements.map { .object($0.json) }),
    "appState": .object(scene.appState),
    "files": .object(files),
  ])
}

/// Search that can optionally include deleted elements (marked `isDeleted`).
func searchElements(
  _ scene: Scene, query: String?, types: Set<String>?, frameID: String?, limit: Int, includeDeleted: Bool
) -> [JSONValue] {
  var copy = scene
  let deleted = Set(scene.elements.filter(\.isDeleted).map(\.id))
  if includeDeleted { for i in copy.elements.indices { copy.elements[i].isDeleted = false } }
  return copy.search(query: query, types: types, frameID: frameID, limit: limit).map { e in
    var s = copy.summary(of: e)
    if deleted.contains(e.id) { s["isDeleted"] = true }
    return .object(s)
  }
}

func contentTools() -> [Tool] {
  [
    Tool(
      name: "get_scene_content",
      description:
        "Return the scene's full Excalidraw JSON: non-deleted elements, appState and file metadata (image data URLs are omitted to stay small). Use real element ids from here for edit_scene_content update/delete. For big scenes prefer search_scene_content.",
      inputSchema: schema(["sceneId": sceneIdProp], required: ["sceneId"]),
      run: { a, ws in .json(contentJSON(of: try ws.loadScene(try a.require("sceneId")))) }),
    Tool(
      name: "search_scene_content",
      description:
        "Find elements and return compact summaries (id, type, x, y, width, height, label/text, colors, frameId, bindings). query matches text, labels and frame names, ignoring case, spaces and dashes. Example: {\"sceneId\": \"Personal/Deck\", \"query\": \"login\", \"types\": [\"rectangle\"]}.",
      inputSchema: schema(
        [
          "sceneId": sceneIdProp,
          "query": prop("string", "Text to look for in element text, labels or frame names."),
          "types": prop(
            "array", "Only these element types, e.g. [\"rectangle\",\"arrow\",\"text\",\"frame\"].",
            extra: ["items": .object(["type": "string"])]),
          "frameId": prop("string", "Only the frame with this id and elements inside it."),
          "limit": prop("integer", "Max results. Default 25, max 500."),
          "includeDeleted": prop("boolean", "Also return soft-deleted elements. Default false."),
        ], required: ["sceneId"]),
      run: { a, ws in
        let scene = try ws.loadScene(try a.require("sceneId"))
        let limit = max(1, min(500, Int(try a.number("limit") ?? 25)))
        let types = try a.stringList("types").map(Set.init)
        let found = searchElements(
          scene, query: try a.string("query"), types: types, frameID: try a.string("frameId"),
          limit: limit, includeDeleted: a.bool("includeDeleted") ?? false)
        return .json(.object(["count": .number(Double(found.count)), "elements": .array(found)]))
      }),
    Tool(
      name: "edit_scene_content",
      description:
        "Add, update, delete and reorder elements in one atomic call. Order of operations: delete, update, add, zOrder. "
        + "add: array of element skeletons WITHOUT id (required: type, x, y, width, height; text needs only type,x,y,text); "
        + "give each a tempId to reference it from other skeletons (frameId, containerId, startBinding.elementId, endBinding.elementId) in the same call. "
        + "Shape text goes in label: {\"text\":\"Hello\"} (never a separate text element). Arrows between shapes need startBinding and endBinding. "
        + "update: array of {id, ...fields} with real ids. delete: array of ids. zOrder: array of {id, at:\"front\"|\"back\"} or {id, above|below: otherId}. "
        + "add/update may be JSON arrays or strings containing JSON arrays. Call read_diagram_format first if unsure. "
        + "Example add: [{\"tempId\":\"a\",\"type\":\"rectangle\",\"x\":0,\"y\":0,\"width\":160,\"height\":85,\"label\":{\"text\":\"Start\"}},"
        + "{\"tempId\":\"b\",\"type\":\"rectangle\",\"x\":300,\"y\":0,\"width\":160,\"height\":85,\"label\":{\"text\":\"End\"}},"
        + "{\"type\":\"arrow\",\"x\":0,\"y\":0,\"startBinding\":{\"elementId\":\"a\",\"mode\":\"inside\"},\"endBinding\":{\"elementId\":\"b\",\"mode\":\"inside\"}}]. "
        + "Returns created (tempId -> real id), updated/deleted ids, warnings and a summary of created elements.",
      inputSchema: schema(
        [
          "sceneId": sceneIdProp,
          "add": jsonArrayProp("Element skeletons to create (no id; use tempId)."),
          "update": jsonArrayProp("Patches [{\"id\": \"realId\", \"strokeColor\": \"#e03131\"}]."),
          "delete": jsonArrayProp("Element ids to delete, e.g. [\"abc\",\"def\"]."),
          "zOrder": jsonArrayProp("Moves like [{\"id\":\"abc\",\"at\":\"front\"}] or [{\"id\":\"abc\",\"above\":\"def\"}]."),
        ], required: ["sceneId"]),
      run: { a, ws in
        let id = try a.require("sceneId")
        let request = EditRequest(
          delete: try a.stringList("delete") ?? [], update: try a.objectList("update") ?? [],
          add: try a.objectList("add") ?? [], zOrder: try a.objectList("zOrder") ?? [])
        if request.delete.isEmpty && request.update.isEmpty && request.add.isEmpty && request.zOrder.isEmpty {
          throw ToolError("Nothing to do: pass at least one of add, update, delete, zOrder.")
        }
        let (scene, result): (Scene, EditResult)
        do {
          (scene, result) = try ws.edit(id) { try $0.apply(request) }
        } catch let e as EditError {
          throw ToolError("Edit rejected, nothing was saved: \(e.message)")
        }
        var out = result.json.object ?? [:]
        out["createdSummary"] = .array(result.createdIDs.compactMap { scene.element($0) }.map { .object(scene.summary(of: $0)) })
        return .json(.object(out))
      }),
  ]
}
