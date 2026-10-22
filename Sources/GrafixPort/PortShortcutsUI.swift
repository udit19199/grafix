import SwiftUI

/// Turns the repo's shortcut text into the shortcuts macOS menus use.
///
/// The web editor writes a binding as one string, such as "Cmd+Shift+E" or
/// "Delete". macOS wants a key plus a set of modifiers, so the components that
/// name a modifier become modifiers and the last component is the key. A binding
/// that is a gesture rather than a key, such as "Option+drag", has no menu
/// shortcut, and neither has anything this app has not ported.

extension PortShortcut {
  /// The first binding macOS can use in a menu, or nil if there is none.
  public var menuShortcut: KeyboardShortcut? {
    glyphs.lazy.compactMap(KeyboardShortcut.init(portBinding:)).first
  }
}

extension KeyboardShortcut {
  public init?(portBinding binding: String) {
    var modifiers: EventModifiers = []
    var remainder = Substring(binding)
    while let plus = remainder.firstIndex(of: "+"), plus != remainder.startIndex {
      guard let modifier = EventModifiers(portName: remainder[..<plus]) else {
        break
      }
      modifiers.insert(modifier)
      remainder = remainder[remainder.index(after: plus)...]
    }
    guard let key = KeyEquivalent(portName: remainder) else {
      return nil
    }
    self.init(key, modifiers: modifiers)
  }
}

extension EventModifiers {
  /// One modifier as the repo names it, e.g. "Cmd" or "Option".
  init?(portName name: Substring) {
    switch name {
    case "Cmd": self = .command
    case "Shift": self = .shift
    case "Option": self = .option
    case "Ctrl": self = .control
    default: return nil
    }
  }
}

extension KeyEquivalent {
  /// One key as the repo names it. Named keys such as "Delete" are not single
  /// characters, so they are mapped here; everything else must be one character.
  init?(portName name: Substring) {
    switch name {
    case "Delete": self = .delete
    case "Escape": self = .escape
    case "Enter": self = .return
    case "Spacebar": self = .space
    default:
      guard name.count == 1, let character = name.first else {
        return nil
      }
      self = KeyEquivalent(character)
    }
  }
}

extension PortShortcuts {
  /// The menu shortcut the repo gives an action, or nil when it declares none,
  /// or declares only a gesture the app cannot bind.
  public static func menuShortcut(_ action: String) -> KeyboardShortcut? {
    all.first { $0.name == action }?.menuShortcut
  }
}

extension View {
  /// Applies the repo's own binding to a menu item that has one macOS can use,
  /// and leaves the item unchanged otherwise.
  ///
  /// An action can be deliberately left without a key: a plain character like
  /// "?" belongs to the canvas, where the web editor listens for it, because a
  /// menu key equivalent would take it away from every text field in the app.
  @ViewBuilder public func repoShortcut(_ action: String?) -> some View {
    if let action, let shortcut = PortShortcuts.menuShortcut(action) {
      keyboardShortcut(shortcut)
    } else {
      self
    }
  }
}
