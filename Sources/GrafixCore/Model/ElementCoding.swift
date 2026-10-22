import CoreGraphics
import Foundation

/// Converts between `Element` and Excalidraw JSON.
///
/// Decoding is forgiving (missing keys get Excalidraw's defaults, like its
/// restore.ts). Encoding writes the common keys for every element plus the
/// keys belonging to its type, then any unknown keys from `extra`.
extension Element {
  /// Keys this file reads into typed fields. Everything else goes to `extra`.
  static let modelledKeys: Set<String> = [
    "id", "type", "x", "y", "width", "height", "angle", "strokeColor", "backgroundColor",
    "fillStyle", "strokeWidth", "strokeStyle", "roughness", "opacity", "roundness", "seed",
    "version", "versionNonce", "index", "isDeleted", "groupIds", "frameId", "boundElements",
    "updated", "created", "link", "locked", "customData", "text", "originalText", "fontSize",
    "fontFamily", "textAlign", "verticalAlign", "containerId", "autoResize", "lineHeight",
    "points", "startBinding", "endBinding", "startArrowhead", "endArrowhead", "elbowed",
    "polygon", "pressures", "simulatePressure", "fileId", "status", "scale", "crop", "name",
    "lastCommittedPoint", "baseline",
  ]

  public init(json: [String: JSONValue]) {
    func num(_ k: String, _ d: Double) -> Double { json[k]?.number ?? d }
    func str(_ k: String) -> String? { json[k]?.string }
    self.init(
      id: str("id") ?? Element.newID(), type: ElementType(rawValue: str("type") ?? "rectangle"),
      x: num("x", 0), y: num("y", 0), width: num("width", 0), height: num("height", 0))
    angle = num("angle", 0)
    strokeColor = str("strokeColor") ?? "#1e1e1e"
    backgroundColor = str("backgroundColor") ?? "transparent"
    fillStyle = FillStyle(rawValue: str("fillStyle") ?? "solid")
    strokeWidth = num("strokeWidth", 2)
    strokeStyle = StrokeStyle(rawValue: str("strokeStyle") ?? "solid") ?? .solid
    roughness = num("roughness", 1)
    opacity = num("opacity", 100)
    if let r = json["roundness"]?.object, let t = r["type"]?.number {
      roundness = Roundness(type: Int(t), value: r["value"]?.number)
    } else if json["strokeSharpness"]?.string == "round" {
      roundness = Roundness(type: type == .rectangle ? 3 : 2)  // legacy files
    }
    seed = Int(num("seed", Double(Element.randomSeed())))
    version = Int(num("version", 1))
    versionNonce = Int(num("versionNonce", 0))
    index = str("index")
    isDeleted = json["isDeleted"]?.bool ?? false
    groupIds = json["groupIds"]?.array?.compactMap(\.string) ?? []
    frameId = str("frameId")
    boundElements = json["boundElements"]?.array?.compactMap { item in
      guard let o = item.object, let id = o["id"]?.string else { return nil }
      return BoundElement(id: id, type: o["type"]?.string ?? "arrow")
    }
    updated = num("updated", Element.now())
    created = json["created"]?.number
    link = str("link")
    locked = json["locked"]?.bool ?? false
    customData = json["customData"]?.object

    text = str("text") ?? ""
    originalText = str("originalText") ?? text
    fontSize = num("fontSize", 20)
    fontFamily = Int(num("fontFamily", 5))
    textAlign = TextAlign(rawValue: str("textAlign") ?? "left") ?? .left
    verticalAlign = VerticalAlign(rawValue: str("verticalAlign") ?? "top") ?? .top
    containerId = str("containerId")
    autoResize = json["autoResize"]?.bool ?? true
    lineHeight = json["lineHeight"]?.number
      ?? (FontFamily(rawValue: fontFamily)?.lineHeight ?? 1.25)

    points = json["points"]?.array?.compactMap { p in
      guard let a = p.array, a.count >= 2, let px = a[0].number, let py = a[1].number else {
        return nil
      }
      return CGPoint(x: px, y: py)
    } ?? []
    startBinding = Self.decodeBinding(json["startBinding"])
    endBinding = Self.decodeBinding(json["endBinding"])
    startArrowhead = str("startArrowhead").map { Arrowhead(rawValue: $0).normalized }
    if json["endArrowhead"] == nil, type == .arrow {
      endArrowhead = .arrow
    } else {
      endArrowhead = str("endArrowhead").map { Arrowhead(rawValue: $0).normalized }
    }
    elbowed = json["elbowed"]?.bool ?? false
    polygon = json["polygon"]?.bool ?? false
    pressures = json["pressures"]?.array?.compactMap(\.number) ?? []
    simulatePressure = json["simulatePressure"]?.bool ?? true

    fileId = str("fileId")
    imageStatus = str("status") ?? "saved"
    scale = json["scale"]?.array?.compactMap(\.number) ?? [1, 1]
    crop = json["crop"].flatMap { $0.isNull ? nil : $0 }

    name = str("name")

    extra = json.filter { !Element.modelledKeys.contains($0.key) }
    extra.removeValue(forKey: "strokeSharpness")
  }

  static func decodeBinding(_ value: JSONValue?) -> PointBinding? {
    guard let o = value?.object, let id = o["elementId"]?.string else { return nil }
    var fixed: CGPoint?
    if let a = o["fixedPoint"]?.array, a.count == 2, let fx = a[0].number, let fy = a[1].number {
      fixed = CGPoint(x: fx, y: fy)
    }
    return PointBinding(
      elementId: id, fixedPoint: fixed, mode: o["mode"]?.string, focus: o["focus"]?.number,
      gap: o["gap"]?.number)
  }

  static func encodeBinding(_ b: PointBinding?) -> JSONValue {
    guard let b else { return .null }
    var o: [String: JSONValue] = ["elementId": .string(b.elementId)]
    if let f = b.fixedPoint { o["fixedPoint"] = [.number(f.x), .number(f.y)] }
    if let m = b.mode { o["mode"] = .string(m) }
    if let f = b.focus { o["focus"] = .number(f) }
    if let g = b.gap { o["gap"] = .number(g) }
    return .object(o)
  }

  public var json: [String: JSONValue] {
    var o = extra
    func opt(_ s: String?) -> JSONValue { s.map(JSONValue.string) ?? .null }
    o["id"] = .string(id)
    o["type"] = .string(type.rawValue)
    o["x"] = .number(x)
    o["y"] = .number(y)
    o["width"] = .number(width)
    o["height"] = .number(height)
    o["angle"] = .number(angle)
    o["strokeColor"] = .string(strokeColor)
    o["backgroundColor"] = .string(backgroundColor)
    o["fillStyle"] = .string(fillStyle.rawValue)
    o["strokeWidth"] = .number(strokeWidth)
    o["strokeStyle"] = .string(strokeStyle.rawValue)
    o["roughness"] = .number(roughness)
    o["opacity"] = .number(opacity)
    if let r = roundness {
      var ro: [String: JSONValue] = ["type": .number(Double(r.type))]
      if let v = r.value { ro["value"] = .number(v) }
      o["roundness"] = .object(ro)
    } else {
      o["roundness"] = .null
    }
    o["seed"] = .number(Double(seed))
    o["version"] = .number(Double(version))
    o["versionNonce"] = .number(Double(versionNonce))
    o["index"] = opt(index)
    o["isDeleted"] = .bool(isDeleted)
    o["groupIds"] = .array(groupIds.map(JSONValue.string))
    o["frameId"] = opt(frameId)
    o["boundElements"] =
      boundElements.map { .array($0.map { ["id": .string($0.id), "type": .string($0.type)] }) }
      ?? .null
    o["updated"] = .number(updated)
    if let created { o["created"] = .number(created) }
    o["link"] = opt(link)
    o["locked"] = .bool(locked)
    if let customData { o["customData"] = .object(customData) }

    switch type {
    case .text:
      o["text"] = .string(text)
      o["originalText"] = .string(originalText)
      o["fontSize"] = .number(fontSize)
      o["fontFamily"] = .number(Double(fontFamily))
      o["textAlign"] = .string(textAlign.rawValue)
      o["verticalAlign"] = .string(verticalAlign.rawValue)
      o["containerId"] = opt(containerId)
      o["autoResize"] = .bool(autoResize)
      o["lineHeight"] = .number(lineHeight)
    case .line, .arrow, .freedraw:
      o["points"] = .array(points.map { [.number($0.x), .number($0.y)] })
      if type == .freedraw {
        o["pressures"] = .array(pressures.map(JSONValue.number))
        o["simulatePressure"] = .bool(simulatePressure)
      } else {
        o["startBinding"] = Self.encodeBinding(startBinding)
        o["endBinding"] = Self.encodeBinding(endBinding)
        o["startArrowhead"] = opt(startArrowhead?.rawValue)
        o["endArrowhead"] = opt(endArrowhead?.rawValue)
        if type == .arrow { o["elbowed"] = .bool(elbowed) }
        if type == .line { o["polygon"] = .bool(polygon) }
      }
    case .image:
      o["fileId"] = opt(fileId)
      o["status"] = .string(imageStatus)
      o["scale"] = .array(scale.map(JSONValue.number))
      o["crop"] = crop ?? .null
    case .frame, .magicframe:
      o["name"] = opt(name)
    default:
      break
    }
    return o
  }
}

extension Element: Codable {
  public init(from decoder: Decoder) throws {
    let value = try JSONValue(from: decoder)
    guard let object = value.object else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "element must be an object"))
    }
    self.init(json: object)
  }

  public func encode(to encoder: Encoder) throws {
    try JSONValue.object(json).encode(to: encoder)
  }
}
