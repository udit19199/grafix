import Foundation
import GrafixCore

/// Every tool the server exposes, in listing order.
func allTools() -> [Tool] {
  workspaceTools() + contentTools() + slideTools() + imageTools() + editorTools() + renderTools() + guideTools()
}

private let sceneIdProp = prop(
  "string", "Scene id in the form 'Collection/Scene name', e.g. 'Personal/My scene'. Get ids from list_scenes.")

/// Metadata for one scene (loads the file to count elements and slides).
func sceneMetadata(_ info: Workspace.SceneInfo, workspace: Workspace) -> JSONValue {
  var o: [String: JSONValue] = [
    "id": .string(info.id), "name": .string(info.name), "collection": .string(info.collection),
    "modified": iso(info.modified),
  ]
  if let scene = try? workspace.load(info.id) {
    o["elementCount"] = .number(Double(scene.visibleElements.count))
    o["slideCount"] = .number(Double(scene.slideFrames.count))
  }
  return .object(o)
}

func workspaceTools() -> [Tool] {
  [
    Tool(
      name: "list_collections",
      description:
        "List collections (folders that hold scenes). Returns name, sceneCount and modified for each. A collection's id is its name, e.g. 'Personal'.",
      inputSchema: schema(),
      run: { _, ws in
        let list = try ws.listCollections().map { c -> JSONValue in
          .object(["id": .string(c.name), "name": .string(c.name), "sceneCount": .number(Double(c.sceneCount)), "modified": iso(c.modified)])
        }
        return .json(.object(["collections": .array(list)]))
      }),
    Tool(
      name: "create_collection",
      description: "Create a new empty collection (folder). Example: {\"name\": \"Pitch decks\"}. Fails if it already exists.",
      inputSchema: schema(["name": prop("string", "Collection name, no '/' characters.")], required: ["name"]),
      run: { a, ws in
        let name = try a.require("name")
        do { try ws.createCollection(name) } catch WorkspaceError.alreadyExists {
          throw ToolError("Collection '\(name)' already exists. Call list_collections.")
        }
        return .json(.object(["id": .string(name), "name": .string(name)]))
      }),
    Tool(
      name: "update_collection",
      description:
        "Rename a collection. Scene ids inside it change from 'Old/Scene' to 'New/Scene'. Example: {\"collectionId\": \"Personal\", \"name\": \"Personal stuff\"}.",
      inputSchema: schema(
        [
          "collectionId": prop("string", "Current collection name."),
          "name": prop("string", "New collection name."),
        ], required: ["collectionId", "name"]),
      run: { a, ws in
        let id = try a.require("collectionId")
        let name = try a.require("name")
        try requireCollection(id, ws)
        do { try ws.renameCollection(id, to: name) } catch WorkspaceError.alreadyExists {
          throw ToolError("A collection named '\(name)' already exists.")
        }
        return .json(.object(["id": .string(name), "name": .string(name), "previousId": .string(id)]))
      }),
    Tool(
      name: "delete_collection",
      description:
        "Delete a collection and every scene in it by moving its folder to the macOS Trash (recoverable from Finder). Example: {\"collectionId\": \"Old\"}.",
      inputSchema: schema(["collectionId": prop("string", "Collection name.")], required: ["collectionId"]),
      run: { a, ws in
        let id = try a.require("collectionId")
        try requireCollection(id, ws)
        try ws.trashCollection(id)
        return .text("Moved collection '\(id)' to the Trash.")
      }),
    Tool(
      name: "list_scenes",
      description:
        "List scenes, newest first. Returns id ('Collection/Scene name'), name, collection, modified, elementCount, slideCount. Pass collectionId to limit to one collection; omit for all scenes.",
      inputSchema: schema(["collectionId": prop("string", "Optional collection name, e.g. 'Personal'.")]),
      run: { a, ws in
        let infos: [Workspace.SceneInfo]
        if let c = try a.string("collectionId") {
          try requireCollection(c, ws)
          infos = try ws.listScenes(in: c)
        } else {
          infos = try ws.allScenes()
        }
        return .json(.object(["scenes": .array(infos.map { sceneMetadata($0, workspace: ws) })]))
      }),
    Tool(
      name: "create_scene",
      description:
        "Create an empty scene. Example: {\"name\": \"Login flow\", \"collectionId\": \"Personal\"}. collectionId defaults to 'Personal' and is created if missing. Returns the new scene id ('Personal/Login flow'). Fails if the name is taken.",
      inputSchema: schema(
        [
          "name": prop("string", "Scene name, no '/' characters."),
          "collectionId": prop("string", "Collection name. Default 'Personal'."),
        ], required: ["name"]),
      run: { a, ws in
        let name = try a.require("name")
        let collection = try a.string("collectionId") ?? Workspace.defaultCollection
        do {
          let info = try ws.createScene(in: collection, name: name)
          return .json(sceneMetadata(info, workspace: ws))
        } catch WorkspaceError.alreadyExists {
          throw ToolError("Scene '\(collection)/\(name)' already exists. Choose another name or call get_scene_content to edit it.")
        }
      }),
    Tool(
      name: "get_scene",
      description:
        "Scene metadata plus a slide list summary (frameId, name, slideNumber per slide). Does not return elements; use get_scene_content or search_scene_content for those.",
      inputSchema: schema(["sceneId": sceneIdProp], required: ["sceneId"]),
      run: { a, ws in
        let info = try ws.requireScene(try a.require("sceneId"))
        let scene = try ws.loadScene(info.id)
        var meta = sceneMetadata(info, workspace: ws).object ?? [:]
        meta["slides"] = .array(scene.slides.map { s in
          .object(["frameId": .string(s.frameID), "name": .string(s.name), "slideNumber": .number(Double(s.number))])
        })
        meta["fileCount"] = .number(Double(scene.files.count))
        return .json(.object(meta))
      }),
    Tool(
      name: "update_scene",
      description:
        "Rename and/or move a scene. Example: {\"sceneId\": \"Personal/Draft\", \"name\": \"Final\"} or {\"sceneId\": \"Personal/Final\", \"collectionId\": \"Work\"}. Returns the new scene id (ids change on rename or move).",
      inputSchema: schema(
        [
          "sceneId": sceneIdProp,
          "name": prop("string", "New scene name."),
          "collectionId": prop("string", "Collection to move the scene to."),
        ], required: ["sceneId"]),
      run: { a, ws in
        var info = try ws.requireScene(try a.require("sceneId"))
        let name = try a.string("name")
        let collection = try a.string("collectionId")
        if name == nil && collection == nil { throw ToolError("Pass name and/or collectionId.") }
        do {
          try ws.withLock {
            if let name, name != info.name { info = try ws.renameScene(info.id, to: name) }
            if let collection, collection != info.collection { info = try ws.moveScene(info.id, toCollection: collection) }
          }
        } catch WorkspaceError.alreadyExists(let n) {
          throw ToolError("'\(n)' already exists at the destination.")
        }
        return .json(sceneMetadata(info, workspace: ws))
      }),
    Tool(
      name: "delete_scene",
      description:
        "Delete a scene by moving its file to the macOS Trash (recoverable from Finder). Example: {\"sceneId\": \"Personal/Old\"}.",
      inputSchema: schema(["sceneId": sceneIdProp], required: ["sceneId"]),
      run: { a, ws in
        let info = try ws.requireScene(try a.require("sceneId"))
        try ws.trashScene(info.id)
        return .text("Moved scene '\(info.id)' to the Trash.")
      }),
    Tool(
      name: "duplicate_scene",
      description:
        "Copy a scene in the same collection as '<name> copy'. Returns the new scene id. Example: {\"sceneId\": \"Personal/Deck\"}.",
      inputSchema: schema(["sceneId": sceneIdProp], required: ["sceneId"]),
      run: { a, ws in
        let info = try ws.requireScene(try a.require("sceneId"))
        return .json(sceneMetadata(try ws.duplicateScene(info.id), workspace: ws))
      }),
  ]
}

func requireCollection(_ name: String, _ ws: Workspace) throws {
  guard (try? ws.listCollections().contains { $0.name == name }) == true else {
    throw ToolError("No collection '\(name)'. Call list_collections to see names.")
  }
}
