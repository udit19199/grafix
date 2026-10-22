import CoreGraphics
import Testing

@testable import GrafixPort

/// The 18 toolbar tool keys the app expects to render.
private let toolbarToolKeys = [
  "hand", "selection", "lasso", "rectangle", "diamond", "ellipse", "arrow", "line",
  "freedraw", "autoshape", "text", "stickynote", "image", "eraser", "frame", "embeddable",
  "laser", "bucketfill",
]

/// Every path the extractor writes lives in a 512x512 box; a little slack covers rounding.
private let authoringBox = CGRect(x: -1, y: -1, width: 514, height: 514)

private func isInsideAuthoringBox(_ path: CGPath) -> Bool {
  if path.isEmpty {
    return true
  }
  let bounds = path.boundingBox
  if bounds.isNull || bounds.isInfinite {
    return true
  }
  return authoringBox.contains(bounds)
}

@Test func toolbarToolIconsExist() {
  #expect(toolbarToolKeys.count == 18)
  for key in toolbarToolKeys {
    #expect(PortIcons.all[key] != nil, "missing toolbar icon \(key)")
    #expect(PortIcons.icon(key) != nil, "icon(_:) disagrees with all for \(key)")
  }
}

@Test func everyIconHasConvertibleShapes() {
  #expect(PortIcons.all.isEmpty == false)
  for (key, icon) in PortIcons.all {
    #expect(icon.name == key)
    #expect(icon.shapes.isEmpty == false, "\(key) has no shapes")
    for shape in icon.shapes {
      #expect(shape.d.hasPrefix("M"), "\(key) shape does not start with M: \(shape.d)")
      #expect(shape.d.contains(where: { $0.isLowercase }) == false, "\(key) has relative commands")
      if shape.filled {
        #expect(shape.strokeWidth == 0, "\(key) filled shape has a stroke width")
      } else {
        #expect(shape.strokeWidth > 0, "\(key) stroked shape has no stroke width")
      }
      let path = SVGPath.cgPath(shape.d, size: CGSize(width: 64, height: 64))
      #expect(path.isEmpty == false, "\(key) shape parsed to an empty path")
      #expect(isInsideAuthoringBox(path), "\(key) shape leaves the 512 box")
    }
  }
}

@Test func unknownIconNamesReturnNothing() {
  #expect(PortIcons.icon("definitely-not-an-icon") == nil)
  #expect(PortIcons.repoCommit.isEmpty == false)
}

@Test func parsesAndScalesAKnownPath() {
  let path = SVGPath.cgPath(
    "M0 0 L512 0 C512 256 256 512 0 512 Z",
    size: CGSize(width: 32, height: 32)
  )
  #expect(path.isEmpty == false)
  let bounds = path.boundingBox
  #expect(abs(bounds.minX - 0) < 0.01)
  #expect(abs(bounds.minY - 0) < 0.01)
  #expect(abs(bounds.maxX - 32) < 0.01)
  #expect(abs(bounds.maxY - 32) < 0.01)
}

@Test func scalesToNonSquareSizes() {
  let path = SVGPath.cgPath("M0 0 L512 0 L512 512 L0 512 Z", size: CGSize(width: 20, height: 10))
  #expect(path.isEmpty == false)
  let bounds = path.boundingBox
  #expect(abs(bounds.width - 20) < 0.01)
  #expect(abs(bounds.height - 10) < 0.01)
}

@Test func malformedPathsNeverTrap() {
  let malformed = [
    "",
    " ",
    "Z",
    "zzz",
    "M",
    "M0",
    "M0 0 L",
    "M0 0 C 1 2 3",
    "M0 0 L C Z",
    "M0 0 L nope",
    "undefined",
    "M0 0 L8 8 Z Z Z",
    "M0 0 L32 32 X 5 5",
    "🚫 M0 0",
  ]
  let box = CGRect(x: -0.5, y: -0.5, width: 33, height: 33)
  for input in malformed {
    let path = SVGPath.cgPath(input, size: CGSize(width: 32, height: 32))
    if path.isEmpty {
      continue
    }
    let bounds = path.boundingBox
    #expect(bounds.isNull == false, "unexpected null bounds for \(input)")
    #expect(bounds.isInfinite == false, "unexpected infinite bounds for \(input)")
    #expect(box.contains(bounds), "malformed path \(input) escaped the 32 box: \(bounds)")
  }
}

@Test func zeroAndNegativeSizesProduceEmptyPaths() {
  #expect(SVGPath.cgPath("M0 0 L512 512", size: CGSize(width: 0, height: 32)).isEmpty)
  #expect(SVGPath.cgPath("M0 0 L512 512", size: CGSize(width: 32, height: -1)).isEmpty)
}
