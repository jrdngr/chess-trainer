import SwiftUI

/// A screen's bar: back, a large or centred title, and actions.
struct OnbAppBar<Actions: View>: View {
  var title: String
  var subtitle: String?
  var large = false
  var onBack: (() -> Void)?
  @ViewBuilder var actions: Actions

  var body: some View {
    HStack(spacing: 12) {
      if let onBack { RoundIconButton(icon: "back", action: onBack) }
      if large {
        Text(title).font(.system(size: 30, weight: .heavy)).tracking(-0.9).foregroundStyle(Theme.text)
          .frame(maxWidth: .infinity, alignment: .leading).lineLimit(1).minimumScaleFactor(0.7)
      } else {
        VStack(spacing: 1) {
          Text(title).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.text).lineLimit(1)
          if let subtitle { Text(subtitle).font(.system(size: 13)).foregroundStyle(Theme.text2).lineLimit(1) }
        }
        .frame(maxWidth: .infinity)
      }
      actions
    }
    .padding(.horizontal, 20).padding(.top, large ? 14 : 10).padding(.bottom, 10).frame(minHeight: 56)
  }
}

extension OnbAppBar where Actions == AnyView {
  /// A bar with no actions: a back button is balanced by a gap so the title stays centred.
  init(title: String, subtitle: String? = nil, large: Bool = false, onBack: (() -> Void)? = nil) {
    self.title = title
    self.subtitle = subtitle
    self.large = large
    self.onBack = onBack
    self.actions = AnyView(Group { if onBack != nil && !large { Color.clear.frame(width: 38, height: 38) } })
  }
}

/// The answer that stays put under a list that scrolls: `.onboard-bar`.
struct OnboardBar<Content: View>: View {
  @ViewBuilder var content: Content

  var body: some View {
    VStack(spacing: 4) { content }
      .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 12)
      .frame(maxWidth: .infinity)
      .background(Theme.background.opacity(0.92))
      .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.07)).frame(height: 1) }
  }
}

/// A big button: `.btn` with `.accent`, `.xl` and `.block` as asked.
struct BigButton: View {
  var label: String
  var icon: String?
  var accent = true
  var xl = true
  var soft = false
  var disabled = false
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 8) {
        if let icon { Icon(name: icon, size: 18) }
        Text(label).font(.system(size: xl ? 17 : 16, weight: .semibold)).lineLimit(1)
      }
      .foregroundStyle(accent ? Theme.accentInk : Theme.text)
      .frame(maxWidth: .infinity, minHeight: xl ? 56 : 50)
      .background(RoundedRectangle(cornerRadius: xl ? 16 : 14).fill(accent ? Theme.accent : soft ? Theme.surface : Theme.surface2))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(disabled).opacity(disabled ? 0.35 : 1)
  }
}

/// "Skip for now", "Go to Home": `.onboard-skip`.
struct SkipButton: View {
  var label: String
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(label).font(.system(size: 15)).foregroundStyle(Theme.text2).padding(.horizontal, 12).padding(.vertical, 8)
    }
    .buttonStyle(.plain)
  }
}

/// "3 moves", "1 move".
func plural(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }
