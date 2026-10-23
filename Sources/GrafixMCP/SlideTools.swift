import CoreGraphics
import Foundation
import GrafixCore

private let sceneIdProp = prop(
  "string", "Scene id in the form 'Collection/Scene name', e.g. 'Personal/My deck'. Get ids from list_scenes.")

let slideLayouts = ["title", "title-content", "two-column", "media-left", "media-right", "section-break", "custom"]

/// Suggested content rectangles inside a slide's safe area for a layout.
/// Coordinates are absolute scene coordinates.
func layoutRegions(_ layout: String, safeArea s: CGRect) -> [(String, CGRect)] {
  let titleHeight: CGFloat = 63
  let gap: CGFloat = 20
  let title = CGRect(x: s.minX, y: s.minY, width: s.width, height: titleHeight)
  let body = CGRect(x: s.minX, y: s.minY + titleHeight + gap, width: s.width, height: s.height - titleHeight - gap)
  func columns(_ leftFraction: CGFloat) -> (CGRect, CGRect) {
    let usable = body.width - 24
    let left = CGRect(x: body.minX, y: body.minY, width: usable * leftFraction, height: body.height)
    let right = CGRect(
      x: left.maxX + 24, y: body.minY, width: usable * (1 - leftFraction), height: body.height)
    return (left, right)
  }
  switch layout {
  case "title":
    return [("title", CGRect(x: s.minX, y: s.midY - 60, width: s.width, height: 70)),
            ("subtitle", CGRect(x: s.minX, y: s.midY + 20, width: s.width, height: 40))]
  case "title-content":
    return [("title", title), ("content", body)]
  case "two-column":
    let (l, r) = columns(0.5)
    return [("title", title), ("left", l), ("right", r)]
  case "media-left":
    let (l, r) = columns(0.45)
    return [("title", title), ("media", l), ("content", r)]
  case "media-right":
    let (l, r) = columns(0.55)
    return [("title", title), ("content", l), ("media", r)]
  case "section-break":
    return [("title", CGRect(x: s.minX, y: s.midY - 70, width: s.width, height: 90)),
            ("subtitle", CGRect(x: s.minX, y: s.midY + 30, width: s.width, height: 40))]
  default:
    return [("content", s)]
  }
}

func slideJSON(_ slide: Slide, scene: Scene) -> [String: JSONValue] {
  let count = scene.visibleElements.filter { $0.frameId == slide.frameID }.count
  var o: [String: JSONValue] = [
    "frameId": .string(slide.frameID), "name": .string(slide.name),
    "slideNumber": .number(Double(slide.number)),
    "bounds": .rect(slide.bounds), "safeArea": .rect(slide.safeArea),
    "elementCount": .number(Double(count)),
  ]
  o["presenterNotes"] = slide.notes.map(JSONValue.string) ?? .null
  return o
}

func slideTools() -> [Tool] {
  let frameIdProp = prop("string", "Frame id of the slide, from list_slides or create_slide.")
  return [
    Tool(
      name: "list_slides",
      description:
        "List a scene's slides in presentation order. Each slide is a frame: frameId, name, slideNumber (1-based), bounds, safeArea (keep content inside it), presenterNotes, elementCount.",
      inputSchema: schema(["sceneId": sceneIdProp], required: ["sceneId"]),
      run: { a, ws in
        let scene = try ws.loadScene(try a.require("sceneId"))
        return .json(.object(["slides": .array(scene.slides.map { .object(slideJSON($0, scene: scene)) })]))
      }),
    Tool(
      name: "create_slide",
      description:
        "Append a slide (a frame, 854x480 by default) after the last slide. title becomes the frame name. Returns frameId, bounds, safeArea and suggested `regions` (absolute rectangles for title/content/columns/media) for the chosen layout. Then fill the slide with edit_scene_content, setting frameId on each element. layout: title, title-content (default when title given), two-column, media-left, media-right, section-break, custom. Example: {\"sceneId\": \"Personal/Deck\", \"title\": \"Roadmap\", \"layout\": \"two-column\"}.",
      inputSchema: schema(
        [
          "sceneId": sceneIdProp,
          "title": prop("string", "Slide title, stored as the frame name."),
          "presenterNotes": prop("string", "Speaker notes, e.g. markdown bullets."),
          "layout": prop("string", "One of: \(slideLayouts.joined(separator: ", ")).", extra: ["enum": .array(slideLayouts.map(JSONValue.string))]),
          "width": prop("number", "Slide width in px. Default 854 (or the previous slide's width)."),
          "height": prop("number", "Slide height in px. Default 480 (or the previous slide's height)."),
        ], required: ["sceneId"]),
      run: { a, ws in
        let id = try a.require("sceneId")
        let title = try a.string("title")
        let layout = try a.string("layout") ?? (title == nil ? "custom" : "title-content")
        guard slideLayouts.contains(layout) else {
          throw ToolError("Unknown layout '\(layout)'. Use one of: \(slideLayouts.joined(separator: ", ")).")
        }
        let w = try a.number("width"), h = try a.number("height")
        if let w, w < 100 { throw ToolError("width must be at least 100.") }
        if let h, h < 100 { throw ToolError("height must be at least 100.") }
        let size = (w != nil || h != nil) ? CGSize(width: w ?? 854, height: h ?? (w.map { $0 * 480 / 854 } ?? 480)) : nil
        let (scene, frameID) = try ws.edit(id) {
          $0.addSlide(name: title, size: size, notes: try a.string("presenterNotes"))
        }
        guard let slide = scene.slides.first(where: { $0.frameID == frameID }) else {
          throw ToolError("Slide was created but could not be read back.")
        }
        var out = slideJSON(slide, scene: scene)
        out["layout"] = .string(layout)
        var regions: [String: JSONValue] = [:]
        for (name, rect) in layoutRegions(layout, safeArea: slide.safeArea) { regions[name] = .rect(rect) }
        out["regions"] = .object(regions)
        return .json(.object(out))
      }),
    Tool(
      name: "update_slide",
      description:
        "Change a slide's title (frame name), presenterNotes, or position. slideNumber is the new 1-based position; other slides renumber automatically. Example: {\"sceneId\": \"Personal/Deck\", \"frameId\": \"abc\", \"slideNumber\": 1}.",
      inputSchema: schema(
        [
          "sceneId": sceneIdProp, "frameId": frameIdProp,
          "title": prop("string", "New slide title."),
          "presenterNotes": prop("string", "New speaker notes (empty string clears them)."),
          "slideNumber": prop("integer", "New 1-based position in the deck."),
        ], required: ["sceneId", "frameId"]),
      run: { a, ws in
        let id = try a.require("sceneId")
        let frameID = try a.require("frameId")
        let title = try a.string("title")
        let notes = try a.string("presenterNotes")
        let number = try a.number("slideNumber").map { Int($0) }
        if title == nil && notes == nil && number == nil { throw ToolError("Pass title, presenterNotes and/or slideNumber.") }
        let (scene, _) = try ws.edit(id) { scene in
          guard scene.slideFrames.contains(where: { $0.id == frameID }) else {
            throw ToolError("No slide with frameId '\(frameID)'. Call list_slides to see frame ids.")
          }
          if let title { scene.update(frameID) { $0.name = title } }
          if let notes { scene.update(frameID) { $0.presenterNotes = notes.isEmpty ? nil : notes } }
          if let number {
            guard number >= 1 else { throw ToolError("slideNumber starts at 1.") }
            scene.moveSlide(frameID, to: number)
          }
        }
        return .json(.object(["slides": .array(scene.slides.map { .object(slideJSON($0, scene: scene)) })]))
      }),
  ]
}
