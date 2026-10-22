import GrafixPort
import SwiftUI

/// Which popover of the properties panel is open.
enum PanelPopover: Hashable {
  case stroke, background, startArrowhead, endArrowhead, font, link
}

/// Reports a control's frame (in the panel's coordinate space) so its popover can
/// be placed next to it.
struct PanelAnchorKey: PreferenceKey {
  static let defaultValue: [PanelPopover: CGRect] = [:]
  static func reduce(value: inout [PanelPopover: CGRect], nextValue: () -> [PanelPopover: CGRect]) {
    value.merge(nextValue()) { $1 }
  }
}

extension View {
  func panelAnchor(_ which: PanelPopover) -> some View {
    background(
      GeometryReader { geo in
        Color.clear.preference(key: PanelAnchorKey.self, value: [which: geo.frame(in: .named("panelRoot"))])
      })
  }
}

/// `fieldset > legend`: 12px label above a control, 4px below.
struct PanelSection<Content: View>: View {
  let dark: Bool
  let title: String?
  @ViewBuilder var content: () -> Content

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      if let title { Text(title).font(Theme.font(12)).foregroundStyle(Theme.palette(dark).text) }
      content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// One choice of an icon radio group.
struct PanelOption: Identifiable {
  let id: String
  let icon: String
  let title: String
  var iconView: AnyView?
}

/// A `.buttonList` of 32pt icon buttons (stroke width, fill, alignment, ...).
/// `selected` nil means the selection disagrees (mixed): nothing is highlighted.
struct PanelOptionRow: View {
  let dark: Bool
  let title: String
  let options: [PanelOption]
  let selected: String?
  let onSelect: (String) -> Void

  var body: some View {
    PanelSection(dark: dark, title: title) {
      PanelButtonList(options: options) { o in
        PanelButton(dark: dark, icon: o.icon, selected: selected == o.id, title: o.title) { onSelect(o.id) }
      }
    }
  }
}

/// Wrapping row of buttons with 8pt gaps (`.buttonList`).
struct PanelButtonList<Item: Identifiable, Cell: View>: View {
  let options: [Item]
  @ViewBuilder var cell: (Item) -> Cell

  var body: some View {
    HStack(spacing: 8) {
      ForEach(options) { cell($0) }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// `Range`: 4px track, 16px thumb, value bubble under the thumb, "0" at the left.
struct PanelRange: View {
  let dark: Bool
  let title: String
  let value: Double?
  var step: Double = 10
  let onChange: (Double) -> Void

  @State private var dragging: Double?

  var body: some View {
    let p = Theme.palette(dark)
    let shown = dragging ?? value ?? 0
    let progress = shown / 100
    PanelSection(dark: dark, title: title) {
      GeometryReader { geo in
        let thumb: CGFloat = 16
        let trackW = geo.size.width
        ZStack(alignment: .topLeading) {
          // track
          Capsule().fill(p.panelButtonBg).frame(height: 4).offset(y: 10 + thumb / 2 - 2)
          Capsule().fill(value == nil && dragging == nil ? p.panelButtonBg : p.sliderTrack)
            .frame(width: thumb / 2 + (trackW - thumb) * progress, height: 4)
            .offset(y: 10 + thumb / 2 - 2)
          Circle().fill(p.sliderThumb).frame(width: thumb, height: thumb)
            .offset(x: (trackW - thumb) * progress, y: 10)
          if shown != 0 {
            Text("\(Int(shown))").font(Theme.font(12)).foregroundStyle(p.text)
              .fixedSize()
              .position(x: thumb / 2 + (trackW - thumb) * progress, y: 10 + thumb + 4 + 8)
          }
          Text("0").font(Theme.font(12)).foregroundStyle(p.text).fixedSize()
            .position(x: 8, y: 10 + thumb + 4 + 8)
        }
        .contentShape(Rectangle())
        .gesture(
          DragGesture(minimumDistance: 0)
            .onChanged { g in
              let raw = min(max((g.location.x - thumb / 2) / (trackW - thumb), 0), 1) * 100
              let snapped = (raw / step).rounded() * step
              if snapped != dragging { dragging = snapped; onChange(snapped) }
            }
            .onEnded { _ in dragging = nil }
        )
      }
      .frame(height: 10 + 16 + 25 - 6)
    }
  }
}
