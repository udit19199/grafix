import GrafixCore
import GrafixPort
import SwiftUI

/// One library tile (Excalidraw `LibraryUnit.tsx`): a 55pt rounded square with
/// the item's thumbnail; hover = surface-mid, selected/pressed = surface-high.
struct LibraryUnit: View {
  let item: ShapeLibraryItem
  let thumbnail: CGImage?
  let selected: Bool
  let palette: ChromePalette
  let radius: CGFloat
  @State private var hover = false

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: radius)
        .fill(selected ? palette.surfaceHigh : (hover ? palette.surfaceMid : .clear))
      RoundedRectangle(cornerRadius: radius)
        .strokeBorder(selected ? palette.primary : palette.border, lineWidth: 1)
      if let thumbnail {
        Image(decorative: thumbnail, scale: 2).resizable().scaledToFit().padding(2)
      } else {
        RoundedRectangle(cornerRadius: radius).fill(palette.surfaceMid.opacity(0.6)).padding(1)
      }
    }
    .aspectRatio(1, contentMode: .fit)
    .contentShape(RoundedRectangle(cornerRadius: radius))
    .onHover { hover = $0 }
    .help(item.name ?? "")
  }
}
