import Foundation
import Testing

@testable import GrafixCore

@Test func preservesUnknownSceneDataWhenEditing() throws {
  let input = Data(
    #"{"type":"excalidraw","version":2,"future":{"nested":[true,null,"text",42.5]},"appState":{"zoom":{"value":1.5}},"files":{"image-id":{"dataURL":"data:image/png;base64,AAAA"}},"elements":[{"id":"a","type":"rectangle","x":10,"customData":{"plugin":"keep"},"roundness":{"type":3}}]}"#
      .utf8)
  var document = try SceneDocument(data: input)
  var elements = document.elements
  elements[0]["x"] = .number(20)
  document.elements = elements
  let reopened = try SceneDocument(data: document.encoded())
  let original = try SceneDocument(data: input)
  #expect(reopened.root["future"] == original.root["future"])
  #expect(reopened.root["files"] == original.root["files"])
  #expect(reopened.root["appState"] == original.root["appState"])
  #expect(reopened.elements[0]["customData"] == .object(["plugin": .string("keep")]))
  #expect(reopened.elements[0]["roundness"] == .object(["type": .number(3)]))
  #expect(reopened.elements[0]["x"] == .number(20))
}

@Test func rejectsPathsAndExternalSymlinks() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = SceneStore(directory: directory)
  for name in ["../escape", "/tmp/escape", "nested/name", "..", ""] {
    #expect(throws: SceneStoreError.self) { try store.save(SceneDocument(), name: name) }
  }
  try FileManager.default.createSymbolicLink(
    at: directory.appendingPathComponent("escape.excalidraw"),
    withDestinationURL: directory.deletingLastPathComponent().appendingPathComponent(
      "outside.excalidraw"))
  #expect(throws: SceneStoreError.self) { try store.load(name: "escape") }
}

@Test func preventsStaleSavesAndPersistsNewEdits() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = SceneStore(directory: directory)
  var current = try store.save(SceneDocument(), name: "Drawing")
  let stale = try store.load(name: "Drawing")
  current.root["title"] = .string("Updated")
  current = try store.save(current, name: "Drawing")
  #expect(throws: SceneStoreError.self) { try store.save(stale, name: "Drawing") }
  #expect(try store.load(name: "Drawing").root["title"] == .string("Updated"))
  #expect(try store.list().map(\.lastPathComponent) == ["Drawing.excalidraw"])
  #expect(throws: SceneStoreError.self) { try store.save(SceneDocument(), name: "Drawing") }
}

@Test func rejectsMalformedScenesRatherThanDroppingElements() throws {
  for json in [
    #"{"type":"other","elements":[]}"#, #"{"type":"excalidraw","elements":[{"id":"valid"},null]}"#,
    #"{"type":"excalidraw","elements":{}}"#,
  ] {
    #expect(throws: SceneStoreError.self) { try SceneDocument(data: Data(json.utf8)) }
  }
}

@Test func importedSceneCanSaveAsWithoutLosingUnknownFields() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let imported = try SceneDocument(
    data: Data(#"{"type":"excalidraw","elements":[],"future":"keep"}"#.utf8))
  let store = SceneStore(directory: directory)
  try store.save(imported.copyForNewFile(), name: "Imported")
  #expect(try store.load(name: "Imported").root["future"] == .string("keep"))
}
