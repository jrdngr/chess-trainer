import SwiftUI

/// A sheet's full-width button: `.btn`, `.btn.accent`, `.btn.danger`, `.btn.primary`.
struct SheetButton: View {
  enum Style { case plain, accent, danger, primary, soft }
  var title: String
  var icon: String?
  var style: Style
  var action: () -> Void
  @Environment(\.isEnabled) private var enabled

  init(_ title: String, icon: String? = nil, style: Style, action: @escaping () -> Void) {
    self.title = title
    self.icon = icon
    self.style = style
    self.action = action
  }

  var body: some View {
    let (fg, bg): (SwiftUI.Color, SwiftUI.Color) = switch style {
    case .plain: (Theme.text, Theme.surface2)
    case .soft: (Theme.text, Theme.surface)
    case .accent: (Theme.buttonInk, Theme.button)
    case .danger: (Theme.bad, Theme.bad.opacity(0.14))
    case .primary: (Theme.background, SwiftUI.Color(hex: 0xf5f5f7))
    }
    Button(action: action) {
      HStack(spacing: 8) {
        if let icon { Icon(name: icon, size: 18) }
        Text(title).lineLimit(1)
      }
      .font(.system(size: 16, weight: .bold)).foregroundStyle(fg)
      .frame(maxWidth: .infinity, minHeight: 50).padding(.horizontal, 12)
      .background(RoundedRectangle(cornerRadius: 16).fill(bg))
      .opacity(enabled ? 1 : 0.45)
    }
    .buttonStyle(.plain)
  }
}

