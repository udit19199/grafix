import GrafixPort
import SwiftUI

/// Excalidraw theme colours used by the chat panel (css/theme.scss tokens).
struct ChatPalette {
  let dark: Bool
  func token(_ name: String, _ fallback: Color) -> Color { PortTheme.color(name, dark: dark) ?? fallback }
  var panel: Color { token("--island-bg-color", dark ? Color(white: 0.11) : .white) }
  var text: Color { token("--text-primary-color", dark ? .white : Color(white: 0.12)) }
  var muted: Color { token("--color-gray-60", Color.gray) }
  var border: Color { token("--sidebar-border-color", Color.gray.opacity(0.3)) }
  var inputBG: Color { token("--input-bg-color", dark ? Color(white: 0.15) : .white) }
  var inputBorder: Color { token("--input-border-color", Color.gray.opacity(0.4)) }
  var hover: Color { token("--input-hover-bg-color", Color.gray.opacity(0.12)) }
  var brand: Color { token("--color-primary", Color(red: 0.41, green: 0.39, blue: 0.86)) }
  var brandTint: Color { token("--color-surface-primary-container", brand.opacity(0.18)) }
  var onBrandTint: Color { token("--color-on-primary-container", text) }
  var danger: Color { Color(red: 0.86, green: 0.2, blue: 0.2) }
  var success: Color { Color(red: 0.2, green: 0.62, blue: 0.35) }
}
