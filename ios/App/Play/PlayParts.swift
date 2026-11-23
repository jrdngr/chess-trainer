import ChessCore
import Engine
import Game
import Model
import SwiftUI

/// The compact app bar: a close button, a centred title and subtitle, and a trailing slot.
struct PlayAppBar<Trailing: View>: View {
  var title: String
  var subtitle: String?
  var onClose: () -> Void
  @ViewBuilder var trailing: Trailing

  var body: some View {
    HStack(spacing: 12) {
      Button(action: onClose) {
        Icon(name: "close", size: 20).foregroundStyle(Theme.text).frame(width: 38, height: 38).background(Circle().fill(Theme.surface))
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Close")
      VStack(spacing: 1) {
        Text(title).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.text)
        if let subtitle { Text(subtitle).font(.system(size: 13)).foregroundStyle(Theme.text2) }
      }
      .lineLimit(1).frame(maxWidth: .infinity)
      // At least the X's width even when empty, so the title stays centred; wider for what it holds.
      HStack(spacing: 10) { trailing }.fixedSize().frame(minWidth: 38, alignment: .trailing)
    }
    .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 10).frame(minHeight: 56)
  }
}

/// A filled, rounded button.
struct PlayButtonStyle: ButtonStyle {
  /// `.primary` and `.accent` are the indigo key, `.plain` and `.soft` the gray key,
  /// `.bare` for `.btn.plain`, `.danger` a flat red tint.
  enum Kind { case primary, soft, plain, accent, bare, danger }
  var kind = Kind.plain
  /// The whole button, a key's lip included.
  var height: CGFloat = 50
  var radius: CGFloat = 14
  var font: CGFloat = 16
  /// `.block`: as wide as its container.
  var block = false
  /// Side padding, when the default is too wide for the row.
  var inset: CGFloat?
  /// Drawn pressed while what it started goes on, as Show while its line plays.
  var held = false
  @Environment(\.isEnabled) private var enabled

  func makeBody(configuration: Configuration) -> some View {
    let label = configuration.label
      .font(.system(size: font, weight: .semibold))
      .padding(.horizontal, inset ?? (height < 44 ? 14 : 20))
    Group {
      if let keyKind {
        label.frame(maxWidth: block ? .infinity : nil, minHeight: height - keyKind.lip)
          .key(keyKind, radius: radius, pressed: configuration.isPressed || held)
      } else {
        label.foregroundStyle(kind == .danger ? Theme.bad : Theme.text2)
          .frame(maxWidth: block ? .infinity : nil, minHeight: height)
          .background(RoundedRectangle(cornerRadius: radius).fill(kind == .danger ? Theme.bad.opacity(0.14) : .clear))
          .contentShape(RoundedRectangle(cornerRadius: radius))
          .opacity(configuration.isPressed ? 0.6 : 1)
      }
    }
    .opacity(enabled ? 1 : 0.35)
  }

  private var keyKind: KeyKind? {
    switch kind {
    case .primary, .accent: .primary
    case .plain, .soft: .secondary
    case .bare, .danger: nil
    }
  }
}

/// A section heading with an optional note on the right.
struct PlaySection: View {
  var title: String
  var aside: String?
  var first = false

  var body: some View {
    HStack {
      Text(title)
      Spacer()
      if let aside { Text(aside).foregroundStyle(Theme.text3) }
    }
    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text2)
    .padding(.horizontal, 4).padding(.top, first ? 8 : 24).padding(.bottom, 8)
  }
}

/// The game or run announced full screen: the shared `IntroCover`, named for the mode.
struct PlayIntroCover: View {
  var trail: [String]
  /// The mode as the round is called: Play, Run or Growth.
  var mode = "Play"
  var body: some View { IntroCover(mode: mode, trail: trail) }
}

/// The evaluation over the board: `.evalbar` and its score.
struct PlayEvalBar: View {
  var line: EngineLine?
  var body: some View {
    HStack(spacing: 8) {
      GeometryReader { geo in
        Capsule().fill(Theme.surface3)
          .overlay(alignment: .leading) {
            Rectangle().fill(SwiftUI.Color(hex: 0xf5f5f7)).frame(width: geo.size.width * winFraction(line))
              .animation(.easeOut(duration: 0.35), value: winFraction(line))
          }
          .clipShape(Capsule())
      }
      .frame(height: 6)
      Text(line.map(formatScore) ?? "\u{2014}").font(.system(size: 13).monospacedDigit()).foregroundStyle(Theme.text2)
        .frame(minWidth: 48, alignment: .trailing)
    }
  }
}
