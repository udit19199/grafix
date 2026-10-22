import SwiftUI

/// The keyboard-shortcuts dialog: a port of the web editor's `HelpDialog`.
///
/// Every row, caption, key chip, and header link comes from the repo through
/// `PortHelp`, so the dialog lists the same shortcuts in the same order as the
/// web editor. The native editor has not ported every action yet, so the rows it
/// does not answer are dimmed and a line above them says so: an unported feature
/// is visible rather than silently missing.

extension PortHelp {
  /// Rows that work even though no menu binds them, because the feature lives on
  /// the toolbar instead. The lock is a toolbar button, not a menu item.
  static let toolbarOnlyRows: Set<String> = ["toolBar.lock"]

  /// The actions the native editor answers unless the caller supplies its own
  /// list. The app passes the list it builds its menus from; this default keeps
  /// the offscreen snapshot meaningful on its own.
  public static let defaultLiveActions = [
    "loadScene", "saveScene", "toggleTheme", "zenMode", "zoomIn", "zoomOut", "resetZoom",
    "toggleShortcuts", "deleteSelectedElements",
  ]

  /// Bindings the editor answers that are not repo actions, so the shortcut
  /// table has nothing to name them with: undo and redo come from the app's own
  /// menus. The app passes the same list.
  public static let defaultLiveBindings = ["Cmd+Z", "Cmd+Shift+Z"]

  /// Every binding the dialog lists, for checking what the editor claims to
  /// answer.
  public static var allBindings: Set<String> {
    Set(islands.flatMap { $0.rows.flatMap(\.bindings) })
  }

  /// Whether the editor answers this row today.
  ///
  /// A row is live when the app binds one of its keys, when its label names a
  /// tool the toolbar has, or when it is one of the documented toolbar-only
  /// rows.
  public static func isImplemented(
    _ row: PortHelpRow,
    liveActions: [String],
    liveBindings: [String] = []
  ) -> Bool {
    let keys = liveActions.flatMap { PortShortcuts.glyphs(for: $0) } + liveBindings
    if row.bindings.contains(where: { binding in
      keys.contains { sameBinding($0, binding) }
    }) {
      return true
    }
    if toolbarOnlyRows.contains(row.labelKey) {
      return true
    }
    let label = PortStrings.text(row.labelKey)
    return PortTools.all.contains { $0.label == label }
  }

  /// Whether two bindings name the same keys, whatever order they list them in.
  ///
  /// The shortcut table writes "Shift+Option+D" where the dialog writes
  /// "Option+Shift+D", and both mean the same thing.
  public static func sameBinding(_ one: String, _ other: String) -> Bool {
    parts(of: one).sorted() == parts(of: other).sorted()
  }

  private static func parts(of binding: String) -> [String] {
    // The web editor splits a trailing "++" into a literal plus key.
    if binding.hasSuffix("++") {
      return binding.dropLast(2).split(separator: "+").map(String.init) + ["+"]
    }
    return binding.split(separator: "+").map(String.init)
  }

  /// The label to draw for a row, from the repo's own copy.
  public static func label(_ row: PortHelpRow) -> String {
    PortStrings.text(row.labelKey)
  }
}

public struct PortHelpDialog: View {
  /// The shortcut actions the editor answers, named as the repo names them.
  /// The dialog dims every row for an action that is not in this list.
  public let liveActions: [String]
  /// Bindings the editor answers that the repo's shortcut table does not name,
  /// such as undo and redo.
  public let liveBindings: [String]
  public let dark: Bool
  public let dismiss: () -> Void

  public init(
    liveActions: [String],
    liveBindings: [String] = [],
    dark: Bool,
    dismiss: @escaping () -> Void
  ) {
    self.liveActions = liveActions
    self.liveBindings = liveBindings
    self.dark = dark
    self.dismiss = dismiss
  }

  private var metrics: PortMetrics { PortMetrics.load(dark: dark) }
  /// .Modal__content: 1px solid var(--dialog-border-color).
  private var border: Color { PortTheme.color("dialog-border-color", dark: dark) ?? .gray }
  /// .Modal__content: border-radius: 0.75rem.
  private let cornerRadius: CGFloat = 12
  private func length(_ token: String, fallback: CGFloat) -> CGFloat {
    PortLength.parse(PortTheme.raw(token, dark: dark) ?? "") ?? fallback
  }

  public var body: some View {
    ZStack {
      (PortTheme.color("overlay-bg-color", dark: dark) ?? Color.black.opacity(0.4))
        .ignoresSafeArea()
        .onTapGesture { dismiss() }
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          title
          linkRow
          sectionHeading
          islands
          footnote
        }
        .padding(40)  // .Modal__content: padding: calc(var(--space-factor) * 10)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      // HelpDialog.scss narrows the shared dialog to 960px. Like the web
      // editor's modal, it grows to the height available and scrolls inside.
      .frame(maxWidth: 960)
      .frame(maxHeight: .infinity)
      .background(metrics.islandColor)
      .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .stroke(border, lineWidth: 1)
      )
      .portShadows(PortTheme.shadowLayers("modal-shadow", dark: dark))
      .padding(32)
    }
  }

  /// .Dialog__title: 1.25rem, ruled off from the content below it.
  private var title: some View {
    Text(PortStrings.text(PortHelp.titleKey))
      .font(.system(size: 20))
      .foregroundStyle(metrics.textColor)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.bottom, 12)
      .overlay(alignment: .bottom) {
        Rectangle().fill(border).frame(height: 1)
      }
      .padding(.bottom, 24)
      .overlay(alignment: .topTrailing) {
        Button(action: dismiss) {
          PortIconView(name: "cross", size: 24, color: metrics.disabledIconColor)
        }
        .buttonStyle(.plain)
        .offset(x: 8, y: -12)
        .accessibilityLabel("Close")
      }
  }

  /// .HelpDialog__header: the external links, wrapped in a row.
  private var linkRow: some View {
    HStack(spacing: 12) {
      ForEach(PortHelp.links, id: \.url) { link in
        Link(destination: URL(string: link.url) ?? URL(string: "https://excalidraw.com")!) {
          HStack(spacing: 8) {
            PortIconView(
              name: link.iconName, size: 16,
              color: PortTheme.color("text-primary-color", dark: dark) ?? metrics.textColor)
            Text(link.text)
              .font(.system(size: 12, weight: .semibold))
              .kerning(0.4)
          }
          .padding(.vertical, 10)
          .padding(.horizontal, 16)
          .background(
            PortTheme.color(dark ? "color-surface-high" : "color-surface-mid", dark: dark) ?? .gray,
            in: RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
          )
        }
        .buttonStyle(.plain)
        .foregroundStyle(metrics.textColor)
      }
    }
  }

  /// .HelpDialog h3: 1.125rem, 1.5rem above and below.
  private var sectionHeading: some View {
    Text(PortStrings.text(PortHelp.shortcutsKey))
      .font(.system(size: 18, weight: .bold))
      .foregroundStyle(metrics.textColor)
      .padding(.top, 24)
      .padding(.bottom, 24)
  }

  /// Two grid columns: tools over view on the left, the editor list on the
  /// right, with 1.5rem between columns and 2rem between rows.
  private var islands: some View {
    HStack(alignment: .top, spacing: 24) {
      VStack(alignment: .leading, spacing: 32) {
        ForEach(PortHelp.islands.prefix(2), id: \.captionKey) { island in
          islandView(island)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      ForEach(PortHelp.islands.dropFirst(2), id: \.captionKey) { island in
        islandView(island)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  /// .HelpDialog__island: a 1rem caption above a ruled list.
  private func islandView(_ island: PortHelpIsland) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(PortStrings.text(island.captionKey))
        .font(.system(size: 16, weight: .bold))
        .foregroundStyle(metrics.textColor)
      VStack(spacing: 0) {
        ForEach(Array(island.rows.enumerated()), id: \.offset) { index, row in
          rowView(row, isLast: index == island.rows.count - 1)
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
          .stroke(border, lineWidth: 1)
      )
    }
  }

  /// .HelpDialog__shortcut: 0.875rem label on the left, keys on the right.
  @ViewBuilder private func rowView(_ row: PortHelpRow, isLast: Bool) -> some View {
    let live = PortHelp.isImplemented(
      row, liveActions: liveActions, liveBindings: liveBindings)
    HStack(spacing: 8) {
      Text(PortHelp.label(row))
        .font(.system(size: 14))
        .foregroundStyle(metrics.textColor)
      Spacer(minLength: 8)
      keysView(row)
    }
    .padding(.vertical, 6)
    .padding(.horizontal, 12)
    .opacity(live ? 1 : 0.4)
    .overlay(alignment: .bottom) {
      if !isLast {
        Rectangle().fill(border).frame(height: 1)
      }
    }
  }

  /// The key chips, with the repo's own "or" between alternative bindings.
  private func keysView(_ row: PortHelpRow) -> some View {
    HStack(spacing: 4) {
      ForEach(Array(row.keys.enumerated()), id: \.offset) { index, chips in
        if index > 0, row.isOr {
          Text(PortStrings.text(PortHelp.orKey))
            .font(.system(size: 14))
            .foregroundStyle(metrics.disabledIconColor)
        }
        ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
          Text(chip)
            .font(.system(size: 10))
            .lineLimit(1)
            .fixedSize()
            .padding(8)
            .background(
              PortTheme.color("color-primary-light", dark: dark) ?? .gray,
              in: RoundedRectangle(cornerRadius: length("border-radius-md", fallback: 4))
            )
        }
      }
    }
  }

  /// Names the one difference from the web editor's dialog: rows the native
  /// editor does not answer yet.
  private var footnote: some View {
    Text("Dimmed rows are not ported yet.")
      .font(.system(size: 12))
      .foregroundStyle(metrics.disabledIconColor)
      .padding(.top, 24)
  }
}
