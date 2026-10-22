import CoreGraphics
import SwiftUI
import Testing

@testable import GrafixPort

// MARK: - Tools

@Test func everyToolIsUniqueAndComplete() {
  #expect(PortTools.all.count == 18)
  #expect(Set(PortTools.all.map(\.id)).count == 18)
  for tool in PortTools.all {
    #expect(tool.label.isEmpty == false, "\(tool.id) has no label")
    #expect(tool.iconName.isEmpty == false, "\(tool.id) has no icon name")
    #expect(PortIcons.all[tool.iconName] != nil, "\(tool.id) icon \(tool.iconName) is missing")
  }
}

@Test func toolbarRowMatchesTheRenderedOrder() {
  // Toolbar.tsx renders: pen mode, lock, divider, hand, selection, rectangle,
  // diamond, ellipse, arrow, line, freedraw, text, sticky note, eraser, divider,
  // then the extra-tools menu.
  #expect(
    PortTools.toolbarRow == [
      "hand", "selection", "rectangle", "diamond", "ellipse", "arrow", "line", "freedraw", "text",
      "stickynote", "eraser",
    ])
  #expect(PortTools.selectionTools == ["selection", "lasso"])
  #expect(
    PortTools.extraTools == [
      "image", "frame", "embeddable", "autoshape", "laser", "bucketfill", "lasso",
    ])
  #expect(PortTools.unportedToolbarEntries == ["magicframe"])
  // Every toolbar and menu entry is a real tool except the recorded unported ones.
  for id in PortTools.toolbarRow + PortTools.extraTools {
    #expect(PortTools.tool(id) != nil, "\(id) is in the toolbar but has no tool")
  }
  for id in PortTools.unportedToolbarEntries {
    #expect(PortTools.tool(id) == nil, "\(id) is listed as unported but has a tool")
  }
  for id in PortTools.selectionTools {
    #expect(PortTools.tool(id) != nil, "\(id) is a selection tool but has no tool")
  }
}

@Test func toolKeyBindingsMatchTheRepo() {
  // Excalidraw assigns letters and numerals independently; both must resolve,
  // and a key must never activate a tool that needs the other shift state.
  for tool in PortTools.all {
    for letter in tool.letters {
      let byLetter = PortTools.tool(forKey: letter, shift: tool.shiftRequired)
      #expect(byLetter?.id == tool.id, "\(letter) did not resolve to \(tool.id)")
    }
    if let numericKey = tool.numericKey {
      #expect(
        PortTools.tool(forKey: numericKey, shift: tool.shiftRequired)?.id == tool.id,
        "\(numericKey) did not resolve to \(tool.id)")
    }
    // Holding the wrong shift must not reach a tool.
    if tool.shiftRequired {
      #expect(PortTools.tool(forKey: tool.letters[0], shift: false)?.shiftRequired == false)
    }
  }
  #expect(PortTools.tool(forKey: "r", shift: false)?.id == "rectangle")
  #expect(PortTools.tool(forKey: "2", shift: false)?.id == "rectangle")
  #expect(PortTools.tool(forKey: "x", shift: true)?.id == "autoshape")
  #expect(PortTools.tool(forKey: "x", shift: false)?.id == "freedraw")
  #expect(PortTools.tool(forKey: "q", shift: false) == nil)
}

@Test func theCornerBadgesComeFromTheRepo() {
  let expected = [
    "hand": "H", "selection": "V", "rectangle": "R", "diamond": "D", "ellipse": "O",
    "arrow": "A", "line": "L", "freedraw": "P", "text": "T", "stickynote": "N", "image": "9",
    "eraser": "E", "frame": "F", "autoshape": "Shift+X", "laser": "K", "bucketfill": "B",
  ]
  for (id, badge) in expected {
    #expect(PortTools.tool(id)?.keyBindingLabel == badge, "\(id) badge changed")
  }
  // Tooltips read like the web editor's, e.g. "R or 2".
  #expect(PortTools.tool("rectangle")?.shortcutHint == "R or 2")
  #expect(PortTools.tool("hand")?.shortcutHint == "H")
}

// MARK: - Shortcuts

@Test func shortcutsAreTheReposOwn() {
  #expect(PortShortcuts.all.count == 44)
  // Two actions declare no binding at all in the repo; every other action must
  // carry at least one, so a parser miss shows up here.
  let declaredEmpty: Set<String> = ["addToLibrary", "wrapSelectionInFrame"]
  for shortcut in PortShortcuts.all {
    #expect(shortcut.name.isEmpty == false)
    if declaredEmpty.contains(shortcut.name) {
      #expect(shortcut.glyphs.isEmpty, "\(shortcut.name) gained a binding upstream")
      continue
    }
    #expect(shortcut.glyphs.isEmpty == false, "\(shortcut.name) has no key binding")
    for glyph in shortcut.glyphs {
      // The web editor renders macOS bindings with "Cmd" and "Option", not
      // arrows, which is what the native menus and hints must also say.
      #expect(glyph.contains("⌘") == false, "\(shortcut.name) uses a glyph instead of Cmd")
      #expect(glyph.isEmpty == false)
    }
  }
  let byName = Dictionary(
    PortShortcuts.all.map { ($0.name, $0.glyphs) }, uniquingKeysWith: { first, _ in first })
  #expect(byName["saveScene"] == ["Cmd+S"])
  #expect(byName["loadScene"] == ["Cmd+O"])
  #expect(byName["toggleTheme"] == ["Shift+Option+D"])
  // An action with two bindings keeps both, and a platform ternary resolves to
  // the macOS branch.
  #expect(byName["commandPalette"] == ["Cmd+/", "Cmd+Shift+P"])
  #expect(byName["duplicateSelection"] == ["Cmd+D", "Option+drag"])
  #expect(byName["sendToBack"] == ["Cmd+Option+["])
  #expect(byName["bringToFront"] == ["Cmd+Option+]"])
  // "?" is a key, not a ternary.
  #expect(byName["toggleShortcuts"] == ["?"])
}

// MARK: - Palette

@Test func paletteQuickPicksMatchTheRepo() {
  #expect(PortPalette.strokePicks == ["#1e1e1e", "#e03131", "#2f9e44", "#1971c2", "#f08c00"])
  #expect(PortPalette.backgroundPicks.first == "transparent")
  #expect(PortPalette.strokePicks.count == PortPalette.topPickSlots)
  #expect(PortPalette.backgroundPicks.count == PortPalette.topPickSlots)
  #expect(PortPalette.columnsPerRow == 5)
}

@Test func paletteFamiliesAreWellFormed() {
  #expect(PortPalette.families.count == 15)
  for family in PortPalette.families {
    #expect(family.name.isEmpty == false)
    #expect(family.shades.isEmpty == false, "\(family.name) has no shades")
    for shade in family.shades {
      #expect(
        shade == "transparent" || PortRGB.parse(shade) != nil,
        "\(family.name) shade \(shade) is not a colour")
    }
  }
  // The stroke and background panels reuse the same named families, but each
  // lists them in its own order: single-value families first, then hue ramps.
  let singleValueFamilies: Set<String> = ["transparent", "white", "black"]
  let names = Set(PortPalette.families.map(\.name))
  #expect(Set(PortPalette.strokePalette.map(\.name)) == names)
  #expect(Set(PortPalette.backgroundPalette.map(\.name)) == names)
  for palette in [PortPalette.strokePalette, PortPalette.backgroundPalette] {
    for family in palette {
      if singleValueFamilies.contains(family.name) {
        #expect(family.shades.count == 1, "\(family.name) should hold a single value")
      } else {
        #expect(
          family.shades.count > PortPalette.defaultStrokeShadeIndex,
          "\(family.name) has too few shades for the default index")
      }
    }
  }
  #expect(PortPalette.topPickSlots <= PortPalette.strokePalette.count + PortPalette.families.count)
}

// MARK: - Theme tokens

@Test func themeTokensAreParsable() {
  #expect(PortTheme.tokens.light.count == 123)
  #expect(PortTheme.tokens.dark.count == 71)
  for (name, value) in PortTheme.tokens.light {
    #expect(name.hasPrefix("--"), "\(name) is not a custom property")
    #expect(value.isEmpty == false, "\(name) is empty")
  }
  for (name, value) in PortTheme.tokens.dark {
    #expect(name.hasPrefix("--"), "\(name) is not a custom property")
    #expect(value.isEmpty == false, "\(name) is empty")
  }
}

@Test func themeFollowsVarReferences() {
  // --keybinding-color is var(--color-gray-40) in the light theme.
  #expect(PortTheme.raw("keybinding-color", dark: false) == "#b8b8b8")
  #expect(PortTheme.raw("--keybinding-color", dark: false) == "#b8b8b8")
  #expect(PortTheme.raw("keybinding-color", dark: true) == "#7a7a7a")
  #expect(PortTheme.color("keybinding-color", dark: false) != nil)
  #expect(PortTheme.raw("definitely-not-a-token", dark: false) == nil)
}

@Test func darkThemeFallsBackToRoot() {
  // The repo's dark block is a set of overrides on top of :root, so a token it
  // does not set keeps the light value, exactly as CSS inheritance does.
  #expect(PortTheme.tokens.dark["--color-gray-20"] == nil)
  #expect(PortTheme.raw("color-gray-20", dark: true) == PortTheme.raw("color-gray-20", dark: false))
  #expect(PortTheme.raw("color-gray-80", dark: true) == "#3d3d3d")
  // --default-border-color is var(--color-surface-high), which each theme sets.
  let light = PortTheme.rgb("default-border-color", dark: false)
  let dark = PortTheme.rgb("default-border-color", dark: true)
  #expect(light != nil && dark != nil)
  #expect(light != dark)
  // A token only the dark theme declares still resolves.
  #expect(PortTheme.rgb("color-primary-darkest", dark: true) != nil)
}

@Test func metricsComeFromTheStylesheets() {
  for dark in [false, true] {
    let metrics = PortMetrics.load(dark: dark)
    #expect(metrics.buttonSize == 32)  // --default-button-size: 2rem
    #expect(metrics.iconSize == 16)  // --default-icon-size: 1rem
    #expect(metrics.cornerRadius == 8)  // --border-radius-lg: 0.5rem
    #expect(metrics.islandPadding == 4)  // --space-factor: 0.25rem
    #expect(metrics.dividerHeight == 24)  // 1.5rem
    #expect(metrics.keybindingFontSize == 10)  // 0.625rem
    #expect(metrics.dropdownMinWidth == 190)  // 11.875rem
    #expect(metrics.dropdownOffset == 6)  // 0.375rem
    #expect(metrics.islandShadows.isEmpty == false, "the island lost its shadow")
  }
}

// MARK: - Colour parsing

@Test func parsesEveryColourFormTheRepoUses() {
  #expect(PortRGB.parse("#fff") == PortRGB(red: 1, green: 1, blue: 1))
  #expect(PortRGB.parse("#b8b8b8")!.red == Double(0xb8) / 255)
  let withAlpha = PortRGB.parse("#1e1e1eff")!
  #expect(abs(withAlpha.alpha - 1) < 0.0001)
  let half = PortRGB.parse("#00000080")!
  #expect(abs(half.alpha - Double(0x80) / 255) < 0.0001)
  #expect(PortRGB.parse("rgb(255, 0, 0)") == PortRGB(red: 1, green: 0, blue: 0))
  #expect(PortRGB.parse("rgba(0, 0, 0, 0.5)")!.alpha == 0.5)
  #expect(PortRGB.parse("white") == PortRGB(red: 1, green: 1, blue: 1))
  #expect(PortRGB.parse("black") == PortRGB(red: 0, green: 0, blue: 0))
  #expect(PortRGB.parse("transparent") == .clear)
  #expect(PortRGB.parse("none") == nil)
  #expect(PortRGB.parse("var(--color-primary)") == nil)
  #expect(PortRGB.parse("") == nil)
  // hsl(0, 0%, 50%) is mid grey.
  let grey = PortRGB.parse("hsl(0, 0%, 50%)")!
  #expect(abs(grey.red - 0.5) < 0.0001)
  #expect(abs(grey.red - grey.blue) < 0.0001)
}

@Test func colourDarknessMatchesTheReposYIQTest() {
  // isColorDark() uses a YIQ contrast threshold; the picker's outline test uses
  // COLOR_OUTLINE_CONTRAST_THRESHOLD = 240 and outlines a swatch when it is NOT
  // dark, so only a near-white value like #ffffff (YIQ 255) gets the hairline.
  #expect(PortRGB.parse("#1e1e1e")!.isDark())
  #expect(PortRGB.parse("#ffffff")!.isDark(threshold: 240) == false)
  #expect(PortRGB.parse("#ebebeb")!.isDark(threshold: 240))  // YIQ 235 < 240
  #expect(PortRGB.parse("#3d3d3d")!.isDark(threshold: 240))
  // Transparent is never dark, which is why it is drawn as a checkerboard.
  #expect(PortRGB.parse("transparent")!.isDark() == false)
}

// MARK: - Lengths and shadows

@Test func parsesLengths() {
  #expect(PortLength.parse("2rem") == 32)
  #expect(PortLength.parse("0.625rem") == 10)
  #expect(PortLength.parse("12px") == 12)
  #expect(PortLength.parse("0") == 0)
  #expect(PortLength.parse("4") == 4)
  #expect(PortLength.parse("auto") == nil)
  #expect(PortLength.parse("50%") == nil)
  #expect(PortLength.remSize == 16)
}

@Test func parsesShadowLayers() {
  let island = PortTheme.shadowLayers("shadow-island", dark: false)
  #expect(island.count == 3, "the island shadow has three layers in the repo")
  for layer in island {
    #expect(layer.blur >= 0)
  }
  let layers = PortShadowLayer.parseList(
    "0 0 1px 0 rgba(0, 0, 0, 0.17), 0 7px 14px rgba(0, 0, 0, 0.05)")
  #expect(layers.count == 2)
  #expect(layers[0].offsetY == 0)
  #expect(abs(layers[0].color.alpha - 0.17) < 0.0001)
  #expect(layers[1].offsetY == 7)
  #expect(layers[1].blur == 14)
  #expect(layers[1].spread == 0)
  #expect(PortShadowLayer.parseList("none").isEmpty)
}

// MARK: - Strings

@Test func stringsReadLikeTheWebEditor() {
  #expect(PortStrings.all.count == 404)
  #expect(PortStrings.text("labels.stroke") == "Stroke")
  #expect(PortStrings.text("labels.background") == "Background")
  #expect(PortStrings.text("toolBar.selection") == "Selection")
  #expect(PortStrings.text("toolBar.lock") == "Keep selected tool active after drawing")
  #expect(PortStrings.text("toolBar.penMode") == "Pen mode - prevent touch")
  #expect(PortStrings.text("toolBar.magicframe") == "Wireframe to code")
  // The shortcuts dialog needs this one, which the command palette owns.
  #expect(PortStrings.text("commandPalette.title") == "Command palette")
  // An unknown key comes back as itself so a missing string is visible.
  #expect(PortStrings.text("nope.notAKey") == "nope.notAKey")
}

// MARK: - Shortcuts dialog

@Test func helpDialogIsTheReposOwn() {
  // Three islands: Tools, View, Editor, exactly as HelpDialog.tsx groups them.
  #expect(
    PortHelp.islands.map(\.captionKey) == [
      "helpDialog.tools", "helpDialog.view", "helpDialog.editor",
    ])
  #expect(PortHelp.links.count == 4, "the dialog lost a header link")
  for link in PortHelp.links {
    #expect(link.url.hasPrefix("https://"), "\(link.url) is not a web address")
    #expect(link.text.isEmpty == false, "\(link.url) has no label")
    #expect(PortIcons.all[link.iconName] != nil, "\(link.iconName) has no icon")
  }
  for island in PortHelp.islands {
    #expect(island.rows.isEmpty == false, "\(island.captionKey) has no rows")
    for row in island.rows {
      let label = PortHelp.label(row)
      #expect(
        PortStrings.text(row.labelKey) != row.labelKey, "\(row.labelKey) is not a real string")
      #expect(label.isEmpty == false)
      #expect(row.keys.isEmpty == false, "\(row.labelKey) has no keys")
      for chips in row.keys {
        #expect(chips.isEmpty == false, "\(row.labelKey) has an empty binding")
        for chip in chips {
          #expect(chip.isEmpty == false)
        }
      }
    }
  }
}

@Test func helpKeyChipsMatchTheReposDisplayRule() {
  let rows = Dictionary(
    PortHelp.islands.flatMap(\.rows).map { ($0.labelKey, $0) },
    uniquingKeysWith: { first, _ in first })
  // A numeral or letter is shown as its own chip, an alternative is flagged.
  #expect(rows["toolBar.selection"]?.keys == [["V"], ["1"]])
  #expect(rows["toolBar.selection"]?.isOr == true)
  #expect(rows["toolBar.hand"]?.keys == [["H"]])
  // "Cmd++" is a binding that ends in a literal plus key, not an empty chip.
  #expect(rows["buttons.zoomIn"]?.keys == [["Cmd", "+"]])
  // A sequence stays unflagged: the repo joins those keys with nothing.
  #expect(rows["helpDialog.curvedArrow"]?.isOr == false)
  #expect(rows["helpDialog.curvedArrow"]?.keys.count == 4)
  // Bindings the dialog takes straight from the shortcut table.
  #expect(rows["labels.sendToBack"]?.bindings == ["Cmd+Option+["])
  #expect(rows["commandPalette.title"]?.bindings == ["Cmd+/", "Cmd+Shift+P"])
}

@Test func helpToolRowsLineUpWithTheToolbar() {
  // The dialog names tools through string keys, and the tool table carries the
  // same words, which is what lets the dialog mark a tool row as live. Three
  // rows name toolbar-adjacent things that are not tools at all.
  let notTools: Set<String> = ["toolBar.lock", "toolBar.link", "toolBar.convertElementType"]
  let toolRows = PortHelp.islands.flatMap(\.rows).filter {
    $0.labelKey.hasPrefix("toolBar.") && !notTools.contains($0.labelKey)
  }
  #expect(toolRows.count >= 15)
  let labels = Set(PortTools.all.map(\.label))
  for row in toolRows {
    #expect(labels.contains(PortHelp.label(row)), "\(row.labelKey) names no tool")
  }
  // The three exceptions really are missing from the tool table, which is why
  // they are listed above rather than matched.
  let strings = Set(PortTools.all.map(\.label))
  for key in notTools {
    #expect(strings.contains(PortStrings.text(key)) == false, "\(key) is now a tool")
  }
}

@Test func helpRowsAreDimmedOnlyWhenTheEditorLacksTheAction() {
  let live = PortHelp.defaultLiveActions
  let rows = Dictionary(
    PortHelp.islands.flatMap(\.rows).map { ($0.labelKey, $0) },
    uniquingKeysWith: { first, _ in first })
  func isLive(_ key: String) -> Bool {
    rows[key].map {
      PortHelp.isImplemented(
        $0, liveActions: live, liveBindings: PortHelp.defaultLiveBindings)
    } ?? false
  }
  // Menu-bound actions, and the tool rows whose tools the toolbar has.
  #expect(isLive("buttons.zenMode"))
  #expect(isLive("buttons.resetZoom"))
  #expect(isLive("buttons.zoomIn"))
  #expect(isLive("labels.toggleTheme"))
  #expect(isLive("labels.delete"))
  #expect(isLive("toolBar.rectangle"))
  #expect(isLive("toolBar.image"))
  // The lock is a toolbar button rather than a menu item, and still works.
  #expect(isLive("toolBar.lock"))
  // Everything the editor does not answer yet stays dimmed.
  #expect(isLive("commandPalette.title") == false)
  #expect(isLive("labels.group") == false)
  #expect(isLive("labels.alignTop") == false)
  #expect(isLive("labels.eyeDropper") == false)
  #expect(isLive("toolBar.link") == false)
  #expect(isLive("helpDialog.createFlowchart") == false)
  // Undo and redo come from the app's own menus, so the editor declares them as
  // plain bindings rather than as repo actions.
  #expect(isLive("buttons.undo"))
  #expect(isLive("buttons.redo"))
}

@Test func appBindingsAreRowsTheDialogLists() {
  // The app's own keys must be rows in the dialog, or the dimming would claim
  // the editor answers something the dialog never shows.
  for binding in ["Cmd+Z", "Cmd+Shift+Z"] {
    #expect(
      PortHelp.allBindings.contains(binding),
      "\(binding) is not a binding the shortcuts dialog lists")
  }
}

@Test func everyLiveActionIsARealShortcut() {
  // A typo in the live list would silently dim a row that works.
  for action in PortHelp.defaultLiveActions {
    #expect(
      PortShortcuts.all.contains { $0.name == action },
      "\(action) is not a shortcut in the repo")
  }
}

@Test func menuShortcutsComeFromTheReposBindings() {
  // Every binding the editor relies on resolves to a real macOS shortcut.
  #expect(PortShortcuts.menuShortcut("saveScene") == KeyboardShortcut("S", modifiers: .command))
  #expect(PortShortcuts.menuShortcut("loadScene") == KeyboardShortcut("O", modifiers: .command))
  #expect(
    PortShortcuts.menuShortcut("toggleTheme")
      == KeyboardShortcut("D", modifiers: [.shift, .option]))
  #expect(PortShortcuts.menuShortcut("zenMode") == KeyboardShortcut("Z", modifiers: .option))
  #expect(PortShortcuts.menuShortcut("zoomIn") == KeyboardShortcut("+", modifiers: .command))
  #expect(PortShortcuts.menuShortcut("resetZoom") == KeyboardShortcut("0", modifiers: .command))
  #expect(PortShortcuts.menuShortcut("toggleShortcuts") == KeyboardShortcut("?", modifiers: []))
  // Delete parses too; it is the canvas rather than a menu item that answers it.
  #expect(
    PortShortcuts.menuShortcut("deleteSelectedElements") == KeyboardShortcut(.delete, modifiers: [])
  )
  // "Option+drag" is a gesture, so the next binding macOS can use is the one
  // that becomes the menu key.
  #expect(
    PortShortcuts.menuShortcut("duplicateSelection") == KeyboardShortcut("D", modifiers: .command))
  // A name the repo does not define resolves to nothing rather than trapping.
  #expect(PortShortcuts.menuShortcut("notAnAction") == nil)
}

@Test func bindingsMatchWhateverOrderTheModifiersComeIn() {
  // The shortcut table and the dialog word the theme toggle differently.
  #expect(PortHelp.sameBinding("Shift+Option+D", "Option+Shift+D"))
  #expect(PortHelp.sameBinding("Cmd++", "Cmd++"))
  #expect(PortHelp.sameBinding("Cmd++", "Cmd+") == false)
  #expect(PortHelp.sameBinding("Cmd+S", "Cmd+O") == false)
  #expect(PortHelp.sameBinding("Cmd+S", "S") == false)
}

// MARK: - Editor chrome

@Test func chromeSelectionSlotFollowsThePreferredTool() {
  var chrome = PortEditorChrome()
  #expect(chrome.selectionTool == "selection")
  chrome.preferredSelectionTool = "lasso"
  #expect(chrome.selectionTool == "lasso")
  // A junk preference falls back to the first selection tool.
  chrome.preferredSelectionTool = "rectangle"
  #expect(chrome.selectionTool == "selection")
  // Every toolbar slot draws an icon, including the preferred selection tool.
  for id in PortTools.toolbarRow {
    let drawn = id == "selection" ? chrome.selectionTool : id
    #expect(PortIcons.all[drawn] != nil, "\(drawn) has no icon")
  }
}

@Test func toolbarIconsForChromeExist() {
  // The chrome outside the toolbar uses the repo's own glyphs too.
  for name in [
    "undo", "redo", "zoomin", "zoomout", "library", "present", "penmode", "lock", "unlock",
  ] {
    #expect(PortIcons.all[name] != nil, "chrome icon \(name) is missing")
  }
}
