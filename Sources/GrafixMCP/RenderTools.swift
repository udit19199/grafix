import Foundation
import GrafixCore
import GrafixRender

private let sceneIdProp = prop(
  "string", "Scene id in the form 'Collection/Scene name', e.g. 'Personal/My scene'. Get ids from list_scenes.")

/// Renders a scene (or one frame) to PNG through the shared renderer.
func renderPNG(_ scene: Scene, frameID: String?, maxWidth: Double, padding: Double, dark: Bool) -> Data? {
  SceneRenderer.png(scene, frameID: frameID, maxWidth: CGFloat(maxWidth), padding: CGFloat(padding), dark: dark)
}

func renderTools() -> [Tool] {
  [
    Tool(
      name: "take_screenshot",
      description:
        "Render the scene (or a single slide via frameId) to a PNG image so you can check your work. Call it after substantial edits and fix overlaps, clipped text or misplaced arrows. Example: {\"sceneId\": \"Personal/Deck\", \"frameId\": \"abc\"}.",
      inputSchema: schema(
        [
          "sceneId": sceneIdProp,
          "frameId": prop("string", "Render only this frame (slide), clipped to it."),
          "maxWidth": prop("number", "Maximum image width in px. Default 1280, capped at 1920."),
          "padding": prop("number", "Padding around the content in px. Default 20."),
          "dark": prop("boolean", "Render with the dark theme. Default false."),
        ], required: ["sceneId"]),
      run: { a, ws in
        let scene = try ws.loadScene(try a.require("sceneId"))
        let frameID = try a.string("frameId")
        if let frameID, !(scene.element(frameID)?.isFrame ?? false) {
          throw ToolError("No frame '\(frameID)'. Call list_slides to see frame ids.")
        }
        let maxWidth = min(1920, max(100, try a.number("maxWidth") ?? 1280))
        let padding = max(0, try a.number("padding") ?? 20)
        guard let png = renderPNG(scene, frameID: frameID, maxWidth: maxWidth, padding: padding, dark: a.bool("dark") ?? false)
        else { throw ToolError("Nothing to render: the scene (or frame) is empty.") }
        return .image(png: png)
      })
  ]
}
