import SwiftUI

/// The parts of the editor the toolbar reflects. Kept in one value so the
/// toolbar, the panels, and the canvas all read the same state.
public struct PortEditorChrome: Sendable, Equatable {
  public var activeTool: String
  public var preferredSelectionTool: String
  public var toolLocked: Bool
  public var penMode: Bool
  public var dark: Bool
  public var zenMode: Bool
  public var extraToolsOpen: Bool
  /// Whether the shortcuts dialog is open.
  public var showingHelp: Bool

  public init(
    activeTool: String = "selection",
    preferredSelectionTool: String = "selection",
    toolLocked: Bool = false,
    penMode: Bool = false,
    dark: Bool = false,
    zenMode: Bool = false,
    extraToolsOpen: Bool = false,
    showingHelp: Bool = false
  ) {
    self.activeTool = activeTool
    self.preferredSelectionTool = preferredSelectionTool
    self.toolLocked = toolLocked
    self.penMode = penMode
    self.dark = dark
    self.zenMode = zenMode
    self.extraToolsOpen = extraToolsOpen
    self.showingHelp = showingHelp
  }

  /// The tool the selection slot draws: whichever the user last picked.
  public var selectionTool: String {
    PortTools.selectionTools.contains(preferredSelectionTool)
      ? preferredSelectionTool : PortTools.selectionTools.first ?? "selection"
  }
}

/// Picks the first icon name the extractor actually produced. The repo renames
/// icons between releases, so a missing name should degrade, not crash.
enum PortIconName {
  static func first(_ candidates: [String]) -> String? {
    candidates.first { PortIcons.all[$0] != nil }
  }

  static let penMode = ["penmode", "pencil", "pen", "handdraw"]
  static let locked = ["locked", "lock"]
  static let unlocked = ["unlocked", "unlock"]
  static let dots = ["dots", "ellipsis", "more", "ellipsishorizontal", "dotshorizontal"]
}

/// Draws an icon, or nothing when the extractor did not produce that name.
struct PortIconSlot: View {
  let names: [String]
  let size: CGFloat
  let color: Color
  /// Fillable tools draw their icon filled while the tool is active, which is
  /// what the web editor's `.fillable.ToolIcon--checked` rule does.
  var filled: Bool = false

  var body: some View {
    if let name = names.first(where: { PortIcons.all[$0] != nil }) {
      if filled, let icon = PortIcons.icon(name) {
        FilledIcon(icon: icon, size: size, color: color)
      } else {
        PortIconView(name: name, size: size, color: color)
      }
    }
  }
}

/// The same icon drawn with every shape filled, for the active state of a
/// tool whose shapes can take a background colour.
private struct FilledIcon: View {
  let icon: PortIcon
  let size: CGFloat
  let color: Color

  var body: some View {
    ZStack {
      ForEach(Array(icon.shapes.enumerated()), id: \.offset) { _, shape in
        Path(SVGPath.cgPath(shape.d, size: CGSize(width: size, height: size)))
          .fill(color)
      }
    }
    .frame(width: size, height: size)
  }
}

/// The editor toolbar, laid out the way the web editor lays it out: a floating
/// rounded panel with the pen and lock controls, the tool buttons, and the
/// "more tools" menu.
public struct PortToolbar: View {
  @Binding var chrome: PortEditorChrome

  public init(chrome: Binding<PortEditorChrome>) {
    self._chrome = chrome
  }

  private var metrics: PortMetrics { PortMetrics.load(dark: chrome.dark) }

  public var body: some View {
    HStack(spacing: metrics.rowGap) {
      penModeButton
      lockButton
      divider
      ForEach(toolbarSlots, id: \.self) { id in
        toolButton(id)
      }
      divider
      extraToolsTrigger
    }
    .padding(metrics.islandPadding)
    .background(
      RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
        .fill(metrics.islandColor)
        .portShadows(metrics.islandShadows)
    )
    .overlay(alignment: .topTrailing) { extraToolsMenu }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(PortStrings.text("buttons.menu"))
  }

  /// The tool buttons in rendered order. The selection entry is drawn as
  /// whichever selection tool the user last picked.
  private var toolbarSlots: [String] {
    PortTools.toolbarRow.map { $0 == "selection" ? chrome.selectionTool : $0 }
  }

  // MARK: - controls

  private var divider: some View {
    Rectangle()
      .fill(metrics.borderColor)
      .frame(width: 1, height: metrics.dividerHeight)
  }

  /// The web editor only shows this button when it detects a pen, because that
  /// is the only reason to switch modes. A desktop app has no such signal, so
  /// the button stays available.
  private var penModeButton: some View {
    chromeButton(
      names: PortIconName.penMode,
      label: PortStrings.text("toolBar.penMode"),
      checked: chrome.penMode
    ) {
      chrome.penMode.toggle()
    }
  }

  private var lockButton: some View {
    // The repo's lock button carries the Q shortcut in its title.
    chromeButton(
      names: chrome.toolLocked ? PortIconName.locked : PortIconName.unlocked,
      label: "\(PortStrings.text("toolBar.lock")) — Q",
      checked: chrome.toolLocked
    ) {
      chrome.toolLocked.toggle()
    }
  }

  private func chromeButton(
    names: [String], label: String, checked: Bool, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      ZStack {
        RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
          .fill(checked ? metrics.selectedBackground : .clear)
        PortIconSlot(
          names: names,
          size: metrics.iconSize,
          color: checked ? metrics.selectedIconColor : metrics.iconColor
        )
      }
      .frame(width: metrics.buttonSize, height: metrics.buttonSize)
    }
    .buttonStyle(.plain)
    .help(label)
    .accessibilityLabel(label)
  }

  private func toolButton(_ id: String) -> some View {
    let tool = PortTools.tool(id)
    let label = tool?.label ?? id
    let checked = chrome.activeTool == id
    // The hand button hides its key badge in the web editor, and zen mode hides
    // every key badge.
    let showBadge = !chrome.zenMode && id != "hand"
    let badge = showBadge ? tool?.keyBindingLabel : nil
    let hint = tool?.shortcutHint ?? ""
    return Button {
      selectTool(id)
    } label: {
      // The icon fills the whole 2rem button and the key badge sits at its
      // bottom-right corner, which is what .ToolIcon__keybinding does in
      // css at bottom: 2px, right: 3px.
      ZStack(alignment: .bottomTrailing) {
        PortIconSlot(
          names: [tool?.iconName ?? id],
          size: metrics.iconSize,
          color: checked ? metrics.selectedIconColor : metrics.iconColor,
          filled: checked && (tool?.fillable ?? false)
        )
        .frame(width: metrics.buttonSize, height: metrics.buttonSize)
        if let badge, !badge.isEmpty {
          Text(badge)
            .font(.system(size: metrics.keybindingFontSize))
            .foregroundStyle(checked ? metrics.selectedKeybindingColor : metrics.keybindingColor)
            .padding(.trailing, 3)
            .padding(.bottom, 2)
        }
      }
      .background(
        RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
          .fill(checked ? metrics.selectedBackground : .clear)
      )
    }
    .buttonStyle(.plain)
    .help(hint.isEmpty ? label : "\(label) — \(hint)")
    .accessibilityLabel(label)
    .accessibilityAddTraits(checked ? [.isSelected] : [])
  }

  private var extraToolsTrigger: some View {
    let active = PortTools.extraTools.first { $0 == chrome.activeTool }
    let iconName = active.flatMap { PortTools.tool($0)?.iconName }
    return Button {
      chrome.extraToolsOpen.toggle()
    } label: {
      ZStack {
        RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
          .fill(active != nil ? metrics.selectedBackground : .clear)
        PortIconSlot(
          names: iconName.map { [$0] } ?? PortIconName.dots,
          size: metrics.iconSize,
          color: active != nil ? metrics.selectedIconColor : metrics.iconColor
        )
      }
      .frame(width: metrics.buttonSize, height: metrics.buttonSize)
    }
    .buttonStyle(.plain)
    .help(PortStrings.text("toolBar.extraTools"))
    .accessibilityLabel(PortStrings.text("toolBar.extraTools"))
  }

  @ViewBuilder private var extraToolsMenu: some View {
    if chrome.extraToolsOpen {
      VStack(alignment: .leading, spacing: 0) {
        ForEach(PortTools.extraTools, id: \.self) { id in
          extraToolItem(id)
        }
        ForEach(PortTools.unportedToolbarEntries, id: \.self) { id in
          unportedItem(id)
        }
      }
      .frame(minWidth: metrics.dropdownMinWidth, alignment: .leading)
      .padding(4)
      .background(
        RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
          .fill(metrics.islandColor)
          .portShadows(PortTheme.shadowLayers("shadow-island", dark: chrome.dark))
      )
      .offset(y: metrics.dropdownOffset + metrics.buttonSize + metrics.islandPadding * 2)
      .fixedSize()
    }
  }

  private func extraToolItem(_ id: String) -> some View {
    let tool = PortTools.tool(id)
    let checked = chrome.activeTool == id
    return Button {
      selectTool(id)
      chrome.extraToolsOpen = false
    } label: {
      HStack(spacing: 8) {
        PortIconSlot(
          names: [tool?.iconName ?? id],
          size: metrics.iconSize,
          color: checked ? metrics.selectedIconColor : metrics.iconColor,
          filled: checked && (tool?.fillable ?? false)
        )
        .frame(width: metrics.iconSize)
        Text(tool?.label ?? id)
          .font(.system(size: 13))
          .foregroundStyle(metrics.textColor)
        if let key = tool?.keyBindingLabel, !key.isEmpty {
          Spacer(minLength: 12)
          Text(key)
            .font(.system(size: metrics.keybindingFontSize))
            .foregroundStyle(metrics.keybindingColor)
        }
      }
      .padding(.horizontal, 8)
      .frame(height: metrics.buttonSize)
      .background(
        RoundedRectangle(cornerRadius: metrics.cornerRadius - 2, style: .continuous)
          .fill(checked ? metrics.selectedBackground : .clear)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(tool?.label ?? id)
  }

  /// Toolbar entries the repo offers that Grafix cannot do yet. They are shown
  /// and disabled, so a missing feature is visible rather than quietly absent.
  private func unportedItem(_ id: String) -> some View {
    HStack(spacing: 8) {
      PortIconSlot(
        names: [id, "magicframe", "sparkles"], size: metrics.iconSize,
        color: metrics.disabledIconColor
      )
      .frame(width: metrics.iconSize)
      Text(PortStrings.text("toolBar.\(id)")).font(.system(size: 13))
        .foregroundStyle(metrics.disabledIconColor)
      Spacer(minLength: 12)
      Text("Not ported yet").font(.system(size: metrics.keybindingFontSize))
        .foregroundStyle(metrics.disabledIconColor)
    }
    .padding(.horizontal, 8)
    .frame(height: metrics.buttonSize)
    .accessibilityLabel("\(PortStrings.text("toolBar.\(id)")) — not ported yet")
  }

  // MARK: - behaviour

  /// Mirrors setActiveTool(): picking a tool clears the selection in the canvas,
  /// and picking the tool that is already active returns to the previous one for
  /// the tools the repo marks as toggles.
  private func selectTool(_ id: String) {
    if id == chrome.selectionTool && chrome.activeTool == id {
      // Pointer-clicking the active selection tool switches to lasso, the way
      // the web editor's SelectionToolButton does.
      let next = chrome.selectionTool == "selection" ? "lasso" : "selection"
      chrome.preferredSelectionTool = next
      chrome.activeTool = next
      return
    }
    chrome.activeTool = id
  }
}
