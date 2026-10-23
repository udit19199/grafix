import CryptoKit
import Foundation
import GrafixCore
import ImageIO

private let sceneIdProp = prop(
  "string", "Scene id in the form 'Collection/Scene name', e.g. 'Personal/My scene'. Get ids from list_scenes.")

private let mimeTypes = [
  "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif",
  "webp": "image/webp", "svg": "image/svg+xml",
]

/// Image bytes with their mime type, from a local path or a data URL.
func loadImage(path: String?, dataURL: String?) throws -> (data: Data, mime: String) {
  if let path {
    let url = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
    guard let mime = mimeTypes[url.pathExtension.lowercased()] else {
      throw ToolError("Unsupported image type '.\(url.pathExtension)'. Use png, jpg, gif, webp or svg.")
    }
    guard let data = try? Data(contentsOf: url) else { throw ToolError("Cannot read file '\(path)'.") }
    return (data, mime)
  }
  guard let dataURL, dataURL.hasPrefix("data:"), let comma = dataURL.firstIndex(of: ",") else {
    throw ToolError("dataURL must look like 'data:image/png;base64,...'.")
  }
  let header = dataURL[dataURL.index(dataURL.startIndex, offsetBy: 5)..<comma]
  let mime = header.split(separator: ";").first.map(String.init) ?? "image/png"
  guard header.contains("base64"),
    let data = Data(base64Encoded: String(dataURL[dataURL.index(after: comma)...]), options: .ignoreUnknownCharacters)
  else { throw ToolError("dataURL must be base64 encoded.") }
  return (data, mime)
}

/// Pixel size of an image, if ImageIO can read it.
func pixelSize(_ data: Data) -> CGSize? {
  guard let src = CGImageSourceCreateWithData(data as CFData, nil),
    let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
    let w = props[kCGImagePropertyPixelWidth] as? Double, let h = props[kCGImagePropertyPixelHeight] as? Double
  else { return nil }
  return CGSize(width: w, height: h)
}

func sha1Hex(_ data: Data) -> String {
  Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

func imageTools() -> [Tool] {
  [
    Tool(
      name: "add_image",
      description:
        "Embed an image in a scene as an image element. Give a local file path (png, jpg, gif, webp, svg) or a base64 dataURL, plus x and y (top-left). width/height are optional: give one to keep the aspect ratio, none for natural size (max 480 wide). frameId puts the image inside a slide. Example: {\"sceneId\": \"Personal/Deck\", \"path\": \"/Users/me/logo.png\", \"x\": 100, \"y\": 100, \"width\": 200}.",
      inputSchema: schema(
        [
          "sceneId": sceneIdProp,
          "path": prop("string", "Absolute path of a local image file. Use this or dataURL."),
          "dataURL": prop("string", "Image as 'data:image/png;base64,...'. Use this or path."),
          "x": prop("number", "Left edge in scene coordinates."),
          "y": prop("number", "Top edge in scene coordinates."),
          "width": prop("number", "Width in px (optional)."),
          "height": prop("number", "Height in px (optional)."),
          "frameId": prop("string", "Frame (slide) to place the image in (optional)."),
        ], required: ["sceneId", "x", "y"]),
      run: { a, ws in
        let id = try a.require("sceneId")
        guard let x = try a.number("x"), let y = try a.number("y") else { throw ToolError("x and y are required numbers.") }
        let path = try a.string("path"), dataURL = try a.string("dataURL")
        if (path == nil) == (dataURL == nil) { throw ToolError("Pass exactly one of path or dataURL.") }
        let (data, mime) = try loadImage(path: path, dataURL: dataURL)
        let fileID = sha1Hex(data)
        let natural = pixelSize(data) ?? CGSize(width: 320, height: 240)
        let (w, h) = fitSize(natural: natural, width: try a.number("width"), height: try a.number("height"))
        let frameID = try a.string("frameId")
        let now = Element.now()
        let (scene, elementID) = try ws.edit(id) { scene in
          if let frameID, !(scene.element(frameID)?.isFrame ?? false) {
            throw ToolError("No frame '\(frameID)'. Call list_slides to see frame ids.")
          }
          scene.files[fileID] = .object([
            "id": .string(fileID), "mimeType": .string(mime),
            "dataURL": .string("data:\(mime);base64,\(data.base64EncodedString())"),
            "created": .number(now), "lastRetrieved": .number(now),
          ])
          var e = Element.make(.image, x: x, y: y, width: w, height: h)
          e.fileId = fileID
          e.imageStatus = "saved"
          e.frameId = frameID
          scene.elements.append(e)
          return e.id
        }
        return .json(.object([
          "id": .string(elementID), "fileId": .string(fileID),
          "summary": .object(scene.element(elementID).map { scene.summary(of: $0) } ?? [:]),
        ]))
      }),
  ]
}

/// Final size from optional width/height, keeping the aspect ratio.
func fitSize(natural: CGSize, width: Double?, height: Double?) -> (Double, Double) {
  let ratio = natural.height / max(natural.width, 1)
  switch (width, height) {
  case let (w?, h?): return (w, h)
  case let (w?, nil): return (w, w * ratio)
  case let (nil, h?): return (h / max(ratio, 0.0001), h)
  default:
    let w = min(natural.width, 480)
    return (w, w * ratio)
  }
}
