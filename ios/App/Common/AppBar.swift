import SwiftUI

/// A screen's top bar: a large title, or a back button with a title and
/// subtitle, and icon buttons on the right.
struct AppBar<Actions: View>: View {
  var title: String
  var subtitle: String? = nil
  var large = false
  var onBack: (() -> Void)? = nil
  @ViewBuilder var actions: Actions

  var body: some View {
    HStack(spacing: 12) {
      if let onBack {
        IconButton(icon: "back", action: onBack)
      }
      if large {
        Text(title).font(.system(size: 30, weight: .heavy)).tracking(-0.9).foregroundStyle(Theme.text).lineLimit(1)
          .frame(maxWidth: .infinity, alignment: .leading)
      } else {
        VStack(alignment: .leading, spacing: 1) {
          Text(title).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.text).lineLimit(1)
          if let subtitle { Text(subtitle).font(.system(size: 13)).foregroundStyle(Theme.text2).lineLimit(1) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      HStack(spacing: 8) { actions }
    }
    .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 10).frame(minHeight: 56)
  }
}

extension AppBar where Actions == EmptyView {
  init(title: String, subtitle: String? = nil, large: Bool = false, onBack: (() -> Void)? = nil) {
    self.init(title: title, subtitle: subtitle, large: large, onBack: onBack) { EmptyView() }
  }
}

/// A round icon button. `plain` has no background.
struct IconButton: View {
  var icon: String
  var size: CGFloat = 20
  var plain = false
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      Icon(name: icon, size: size).foregroundStyle(plain ? Theme.text2 : Theme.text)
        .frame(width: 38, height: 38).background(Circle().fill(plain ? .clear : Theme.surface))
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
  }
}

/// A small rounded label: `.chip` and its tones.
struct Chip: View {
  enum Tone { case plain, good, accent, warn, bad }
  var text: String
  var tone: Tone = .plain

  var body: some View {
    let ink: Color = switch tone {
    case .plain: Theme.text2
    case .good: Theme.good
    case .accent: Theme.accent
    case .warn: Theme.warn
    case .bad: Theme.bad
    }
    Text(text).font(.system(size: 12, weight: .semibold)).foregroundStyle(ink)
      .padding(.horizontal, 9).padding(.vertical, 3)
      .background(Capsule().fill(tone == .plain ? Theme.surface2 : ink.opacity(0.14)))
  }
}

/// An outlined count or kind: `.ext-pill`.
struct ExtPill: View {
  var text: String
  var mistake = false

  var body: some View {
    HStack(spacing: 4) {
      if mistake { Icon(name: "warn", size: 12) }
      Text(text)
    }
    .font(.system(size: 12, weight: .semibold)).foregroundStyle(mistake ? Theme.warn : Theme.ext)
    .padding(.horizontal, 8).padding(.vertical, 2)
    .overlay(Capsule().strokeBorder(mistake ? Theme.warn : Theme.accent, lineWidth: 1.5))
  }
}

/// A section's heading over a list, with an aside.
struct SectionHead: View {
  var title: String
  var aside: String? = nil

  var body: some View {
    HStack {
      Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text2)
      Spacer()
      if let aside { Text(aside).font(.system(size: 12)).foregroundStyle(Theme.text3) }
    }
    .padding(.horizontal, 4).padding(.top, 24).padding(.bottom, 8)
  }
}

/// Nothing to show yet, and what would fill it.
struct EmptyNote: View {
  var title: String
  var hint: String

  var body: some View {
    VStack(spacing: 4) {
      Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text2)
      Text(hint).font(.system(size: 14)).foregroundStyle(Theme.text3).multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity).padding(.vertical, 40).padding(.horizontal, 20)
  }
}

/// Opens the settings of the mode in play, from its top bar.
extension EnvironmentValues {
  @Entry var openModeSettings: (() -> Void)? = nil
}

/// The mode's settings button, shown where a mode has set `openModeSettings`.
struct ModeSettingsButton: View {
  @Environment(\.openModeSettings) private var open

  var body: some View {
    if let open {
      IconButton(icon: "tune", action: open).accessibilityLabel("Settings")
    }
  }
}
