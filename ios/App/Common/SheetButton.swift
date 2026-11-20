import SwiftUI

/// A sheet's full-width button: `.btn`, `.btn.accent`, `.btn.danger`, `.btn.primary`.
struct SheetButton: View {
  enum Style { case plain, accent, danger, primary, soft, tint(SwiftUI.Color) }
  var title: String
  var icon: String?
  var style: Style
  var action: () -> Void

  init(_ title: String, icon: String? = nil, style: Style, action: @escaping () -> Void) {
    self.title = title
    self.icon = icon
    self.style = style
    self.action = action
  }

  var body: some View {
    Button(action: action) {
      HStack(spacing: 8) {
        if let icon { Icon(name: icon, size: 18) }
        Text(title).lineLimit(1)
      }
      .font(.system(size: 16, weight: .bold))
      .padding(.horizontal, 12)
    }
    .sheetStyle(style)
  }
}

private extension Button {
  @ViewBuilder func sheetStyle(_ style: SheetButton.Style) -> some View {
    switch style {
    case .accent, .primary: buttonStyle(KeyButtonStyle(kind: .primary, height: 50, radius: 16))
    case .plain, .soft: buttonStyle(KeyButtonStyle(kind: .secondary, height: 50, radius: 16))
    case .danger: buttonStyle(FlatSheetButtonStyle(ink: Theme.bad, fill: Theme.bad.opacity(0.14)))
    case .tint(let color): buttonStyle(FlatSheetButtonStyle(ink: Theme.background, fill: color))
    }
  }
}

/// A sheet button that is a flat color rather than a key: danger, and a tint of its own.
private struct FlatSheetButtonStyle: ButtonStyle {
  let ink: Color
  let fill: Color
  @Environment(\.isEnabled) private var enabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label.foregroundStyle(ink)
      .frame(maxWidth: .infinity, minHeight: 50)
      .background(RoundedRectangle(cornerRadius: 16).fill(fill))
      .opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
  }
}

