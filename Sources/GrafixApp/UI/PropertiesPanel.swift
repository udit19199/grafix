import GrafixCore
import GrafixPort
import SwiftUI

/// Left "selected shape actions" island. Ports Excalidraw's `SelectedShapeActions`
/// (components/Actions.tsx) with its predicates (shapeActionPredicates.ts) and the
/// property actions of actions/actionProperties.tsx.
struct PropertiesPanel: View {
  let document: EditorDocument
  @State private var open: PanelPopover?
  @State private var anchors: [PanelPopover: CGRect] = [:]
  @State private var contentHeight: CGFloat = 400

  /// `showSelectedShapeActions`: a drawing tool is active or something is selected.
  static func isVisible(_ doc: EditorDocument) -> Bool {
    doc.hasSelection || ![.selection, .hand, .eraser, .laser, .lasso].contains(doc.view.tool)
  }

  var body: some View {
    let dark = true
    _ = document.revision
    let target = PanelTarget(document)
    let maxHeight = max(160, document.viewSize.height - 166)
    return ScrollView(.vertical) {
      content(target, dark: dark)
        .background(GeometryReader { g in Color.clear.preference(key: PanelHeightKey.self, value: g.size.height) })
    }
    .frame(height: min(contentHeight, maxHeight))
    .onPreferenceChange(PanelHeightKey.self) { contentHeight = $0 }
    .padding(12)
    .frame(width: 200)
    .islandStyle(dark: dark)
    .coordinateSpace(name: "panelRoot")
    .onPreferenceChange(PanelAnchorKey.self) { anchors = $0 }
    .overlay {
      if open != nil {
        Color.black.opacity(0.001).frame(width: 6000, height: 6000).onTapGesture { open = nil }
      }
    }
    .overlay(alignment: .topLeading) { popover(target, dark: dark) }
    .onAppear {
      switch DebugChrome.open {
      case "stroke": open = .stroke
      case "background": open = .background
      case "font": open = .font
      case "start-arrowhead": open = .startArrowhead
      case "end-arrowhead": open = .endArrowhead
      default: break
      }
    }
    .onChange(of: document.selection) { _, _ in open = nil }
    .onChange(of: document.view.tool) { _, _ in open = nil }
  }

  // MARK: Sections

  @ViewBuilder private func content(_ t: PanelTarget, dark: Bool) -> some View {
    let w = PanelWriter(doc: document)
    VStack(alignment: .leading, spacing: 8) {
      if t.strokeColor {
        ColorPickerRow(
          dark: dark, title: PortStrings.text("labels.stroke"), value: t.strokeColorValue,
          picks: PortPalette.strokePicks, which: .stroke, isOpen: open == .stroke,
          onPick: w.strokeColor, onToggle: { open = open == .stroke ? nil : .stroke })
      }
      if t.backgroundColor {
        ColorPickerRow(
          dark: dark, title: PortStrings.text("labels.background"), value: t.backgroundValue,
          picks: PortPalette.backgroundPicks, which: .background, isOpen: open == .background,
          onPick: w.background, onToggle: { open = open == .background ? nil : .background })
      }
      if t.fill {
        PanelOptionRow(
          dark: dark, title: PortStrings.text("labels.fill"),
          options: [
            PanelOption(id: "hachure", icon: "fillhachure", title: PortStrings.text("labels.hachure")),
            PanelOption(id: "cross-hatch", icon: "fillcrosshatch", title: PortStrings.text("labels.crossHatch")),
            PanelOption(id: "solid", icon: "fillsolid", title: PortStrings.text("labels.solid")),
            PanelOption(id: "zigzag", icon: "fillzigzag", title: PortStrings.text("labels.zigzag")),
          ], selected: t.fillValue, onSelect: w.fill)
      }
      if t.strokeWidth {
        PanelOptionRow(
          dark: dark, title: PortStrings.text("labels.strokeWidth"),
          options: [
            PanelOption(id: "1", icon: "strokewidthbase", title: PortStrings.text("labels.thin")),
            PanelOption(id: "2", icon: "strokewidthbold", title: PortStrings.text("labels.bold")),
            PanelOption(id: "4", icon: "strokewidthextrabold", title: PortStrings.text("labels.extraBold")),
          ], selected: t.widthValue.map { String(Int($0)) }, onSelect: { w.strokeWidth(Double($0) ?? 2) })
      }
      if t.strokeStyle {
        PanelOptionRow(
          dark: dark, title: PortStrings.text("labels.strokeStyle"),
          options: [
            PanelOption(id: "solid", icon: "strokestylesolid", title: PortStrings.text("labels.strokeStyle_solid")),
            PanelOption(id: "dashed", icon: "strokestyledashed", title: PortStrings.text("labels.strokeStyle_dashed")),
            PanelOption(id: "dotted", icon: "strokestyledotted", title: PortStrings.text("labels.strokeStyle_dotted")),
          ], selected: t.strokeStyleValue, onSelect: w.strokeStyle)
      }
      if t.sloppiness {
        PanelOptionRow(
          dark: dark, title: PortStrings.text("labels.sloppiness"),
          options: [
            PanelOption(id: "0", icon: "architect", title: PortStrings.text("labels.architect")),
            PanelOption(id: "1", icon: "artist", title: PortStrings.text("labels.artist")),
            PanelOption(id: "2", icon: "cartoonist", title: PortStrings.text("labels.cartoonist")),
          ], selected: t.roughnessValue.map { String(Int($0)) }, onSelect: { w.roughness(Double($0) ?? 1) })
      }
      if t.roundness {
        PanelOptionRow(
          dark: dark, title: PortStrings.text("labels.edges"),
          options: [
            PanelOption(id: "sharp", icon: "edgesharp", title: PortStrings.text("labels.sharp")),
            PanelOption(id: "round", icon: "edgeround", title: PortStrings.text("labels.round")),
          ], selected: t.roundnessValue, onSelect: w.roundness)
      }
      if t.arrowType {
        PanelOptionRow(
          dark: dark, title: PortStrings.text("labels.arrowtypes"),
          options: [
            PanelOption(id: "sharp", icon: "arrowsharp", title: PortStrings.text("labels.sharp")),
            PanelOption(id: "round", icon: "arrowround", title: PortStrings.text("labels.round")),
            PanelOption(id: "elbow", icon: "arrowelbow", title: "Elbow"),
          ], selected: t.arrowTypeValue, onSelect: w.arrowType)
      }
      if t.text {
        fontFamilyRow(t, dark: dark, w: w)
        PanelOptionRow(
          dark: dark, title: PortStrings.text("labels.fontSize"),
          options: [
            PanelOption(id: "16", icon: "fontsizesmall", title: PortStrings.text("labels.small")),
            PanelOption(id: "20", icon: "fontsizemedium", title: PortStrings.text("labels.medium")),
            PanelOption(id: "28", icon: "fontsizelarge", title: PortStrings.text("labels.large")),
            PanelOption(id: "36", icon: "fontsizeextralarge", title: PortStrings.text("labels.veryLarge")),
          ], selected: t.fontSizeValue.map { String(Int($0)) }, onSelect: { w.fontSize(Double($0) ?? 20) })
        if t.textAlign {
          PanelOptionRow(
            dark: dark, title: PortStrings.text("labels.textAlign"),
            options: [
              PanelOption(id: "left", icon: "textalignleft", title: PortStrings.text("labels.left")),
              PanelOption(id: "center", icon: "textaligncenter", title: PortStrings.text("labels.center")),
              PanelOption(id: "right", icon: "textalignright", title: PortStrings.text("labels.right")),
            ], selected: t.textAlignValue, onSelect: w.textAlign)
        }
      }
      if t.verticalAlign {
        PanelOptionRow(
          dark: dark, title: "Vertical align",
          options: [
            PanelOption(id: "top", icon: "textaligntop", title: PortStrings.text("labels.alignTop")),
            PanelOption(id: "middle", icon: "textalignmiddle", title: PortStrings.text("labels.centerVertically")),
            PanelOption(id: "bottom", icon: "textalignbottom", title: PortStrings.text("labels.alignBottom")),
          ], selected: t.verticalAlignValue, onSelect: w.verticalAlign)
      }
      if t.arrowheads { arrowheadRow(t, dark: dark) }
      PanelRange(dark: dark, title: PortStrings.text("labels.opacity"), value: t.opacityValue, onChange: w.opacity)
      if t.layers {
        PanelSection(dark: dark, title: PortStrings.text("labels.layers")) {
          HStack(spacing: 8) {
            PanelButton(dark: dark, icon: "sendtoback", title: PortStrings.text("labels.sendToBack")) { document.reorderSelected(.back) }
            PanelButton(dark: dark, icon: "sendbackward", title: PortStrings.text("labels.sendBackward")) { document.reorderSelected(.backward) }
            PanelButton(dark: dark, icon: "bringforward", title: PortStrings.text("labels.bringForward")) { document.reorderSelected(.forward) }
            PanelButton(dark: dark, icon: "bringtofront", title: PortStrings.text("labels.bringToFront")) { document.reorderSelected(.front) }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      if t.align { alignRow(t, dark: dark) }
      if t.extraActions { actionsRow(t, dark: dark) }
    }
    .frame(width: 176, alignment: .leading)
  }

  private func fontFamilyRow(_ t: PanelTarget, dark: Bool, w: PanelWriter) -> some View {
    let p = Theme.palette(dark)
    let value = t.fontFamilyValue
    return PanelSection(dark: dark, title: PortStrings.text("labels.fontFamily")) {
      HStack(spacing: 0) {
        HStack(spacing: 8) {
          ForEach(FontChoices.top) { f in
            PanelButton(dark: dark, icon: f.icon, selected: value == f.id, title: f.title) { w.fontFamily(f.id) }
          }
        }
        Rectangle().fill(p.border).frame(width: 1, height: 16).frame(width: 16)
        Button { open = open == .font ? nil : .font } label: { Color.clear }
          .chromeStyle { hover, pressed in
            let on = open == .font || (value != nil && !FontChoices.isTop(value))
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .fill(on ? p.selectedBg : (hover ? p.panelButtonHover : p.panelButtonBg))
              .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(pressed ? p.brandActive : .clear, lineWidth: 1))
              .overlay(ChromeIcon(name: "text", color: on ? p.selectedFg : p.iconFill))
              .frame(width: 32, height: 32)
          }
          .help("Show font picker")
          .panelAnchor(.font)
      }
    }
  }

  private func arrowheadRow(_ t: PanelTarget, dark: Bool) -> some View {
    PanelSection(dark: dark, title: PortStrings.text("labels.arrowheads")) {
      HStack(spacing: 8) {
        ArrowheadTrigger(
          dark: dark, value: t.startArrowheadValue, flip: true, active: open == .startArrowhead,
          title: "Start arrowhead") { open = open == .startArrowhead ? nil : .startArrowhead }
          .panelAnchor(.startArrowhead)
        ArrowheadTrigger(
          dark: dark, value: t.endArrowheadValue, flip: false, active: open == .endArrowhead,
          title: "End arrowhead") { open = open == .endArrowhead ? nil : .endArrowhead }
          .panelAnchor(.endArrowhead)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func alignRow(_ t: PanelTarget, dark: Bool) -> some View {
    func b(_ icon: String, _ key: String, _ a: GrafixCore.Scene.Alignment) -> some View {
      PanelButton(dark: dark, icon: icon, title: PortStrings.text(key)) { document.alignSelected(a) }
    }
    return PanelSection(dark: dark, title: PortStrings.text("labels.align")) {
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 8) {
          b("alignleft", "labels.alignLeft", .left)
          b("centerhorizontally", "labels.centerHorizontally", .centerX)
          b("alignright", "labels.alignRight", .right)
          if t.distribute {
            PanelButton(dark: dark, icon: "distributehorizontally", title: PortStrings.text("labels.distributeHorizontally")) {
              document.distributeSelected(horizontally: true)
            }
          }
        }
        HStack(spacing: 8) {
          b("aligntop", "labels.alignTop", .top)
          b("centervertically", "labels.centerVertically", .centerY)
          b("alignbottom", "labels.alignBottom", .bottom)
          if t.distribute {
            PanelButton(dark: dark, icon: "distributevertically", title: PortStrings.text("labels.distributeVertically")) {
              document.distributeSelected(horizontally: false)
            }
          }
        }
      }
    }
  }

  private func actionsRow(_ t: PanelTarget, dark: Bool) -> some View {
    let locked = t.elements.allSatisfy(\.locked)
    return PanelSection(dark: dark, title: PortStrings.text("labels.actions")) {
      FlowRow(spacing: 8) {
        PanelButton(dark: dark, icon: "duplicate", title: PortStrings.text("labels.duplicateSelection")) { document.duplicateSelected() }
        PanelButton(dark: dark, icon: "trash", title: PortStrings.text("labels.delete")) { document.deleteSelected() }
        PanelButton(dark: dark, icon: "group", title: PortStrings.text("labels.group")) { document.groupSelected() }
        PanelButton(dark: dark, icon: "ungroup", title: PortStrings.text("labels.ungroup")) { document.ungroupSelected() }
        if t.link {
          PanelButton(dark: dark, icon: "link", selected: open == .link, title: PortStrings.text("toolBar.link")) {
            open = open == .link ? nil : .link
          }
          .panelAnchor(.link)
        }
        PanelButton(dark: dark, icon: locked ? "unlock" : "lock", title: locked ? "Unlock" : "Lock") { document.toggleLockSelected() }
      }
    }
  }

  // MARK: Popovers

  @ViewBuilder private func popover(_ t: PanelTarget, dark: Bool) -> some View {
    let w = PanelWriter(doc: document)
    if let open, let a = anchors[open] {
      switch open {
      case .stroke, .background:
        let isStroke = open == .stroke
        sidePopover(dark: dark, anchor: a, arrowY: 37) {
          ColorPickerPopover(
            dark: dark, value: isStroke ? t.strokeColorValue : t.backgroundValue,
            palette: isStroke ? PortPalette.strokePalette : PortPalette.backgroundPalette, isBackground: !isStroke,
            onChange: isStroke ? w.strokeColor : w.background)
        }
      case .font:
        sidePopover(dark: dark, anchor: a, arrowY: 29) {
          FontPopover(dark: dark, value: t.fontFamilyValue, onChange: { w.fontFamily($0) })
        }
      case .startArrowhead:
        ArrowheadPopover(dark: dark, value: t.startArrowheadValue, flip: true) { w.arrowhead(start: true, $0) }
          .fixedSize().offset(x: a.minX + 12, y: a.maxY + 12)
      case .endArrowhead:
        ArrowheadPopover(dark: dark, value: t.endArrowheadValue, flip: false) { w.arrowhead(start: false, $0) }
          .fixedSize().offset(x: a.minX + 12, y: a.maxY + 12)
      case .link:
        LinkPopover(dark: dark, initial: document.singleSelection?.link ?? "", onSave: { w.link($0) }, onClose: { self.open = nil })
          .fixedSize().offset(x: 200 + 8, y: a.minY - 16)
      }
    }
  }

  /// Radix `PropertiesPopover`: island to the right of the panel, 20pt away, arrow pointing back.
  private func sidePopover<C: View>(dark: Bool, anchor a: CGRect, arrowY: CGFloat, @ViewBuilder _ content: () -> C) -> some View {
    let p = Theme.palette(dark)
    return content()
      .islandStyle(dark: dark, padding: 12)
      .overlay(alignment: .topLeading) {
        PopoverArrow().fill(p.island).frame(width: 6, height: 12).offset(x: -6, y: arrowY - 6 + 8)
      }
      .fixedSize()
      .offset(x: 200 + 8, y: a.minY + 8)
  }
}

/// Wrapping horizontal flow (the `.buttonList` flex-wrap).
struct FlowRow: Layout {
  var spacing: CGFloat = 8

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    layout(proposal.width ?? .infinity, subviews).size
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    let r = layout(bounds.width, subviews)
    for (i, f) in r.frames.enumerated() {
      subviews[i].place(at: CGPoint(x: bounds.minX + f.minX, y: bounds.minY + f.minY), proposal: .unspecified)
    }
  }

  private func layout(_ width: CGFloat, _ subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
    var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
    var frames: [CGRect] = []
    for s in subviews {
      let sz = s.sizeThatFits(.unspecified)
      if x > 0, x + sz.width > width { x = 0; y += rowH + spacing; rowH = 0 }
      frames.append(CGRect(x: x, y: y, width: sz.width, height: sz.height))
      x += sz.width + spacing
      rowH = max(rowH, sz.height)
      maxX = max(maxX, x - spacing)
    }
    return (CGSize(width: maxX, height: y + rowH), frames)
  }
}

struct PanelHeightKey: PreferenceKey {
  static let defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
