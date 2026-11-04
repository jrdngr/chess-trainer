import ChessCore
import Engine
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
      VStack(spacing: 1) {
        Text(title).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.text)
        if let subtitle { Text(subtitle).font(.system(size: 13)).foregroundStyle(Theme.text2) }
      }
      .lineLimit(1).frame(maxWidth: .infinity)
      // Holds its width even when empty, so the title stays centred.
      Color.clear.frame(width: 38, height: 1).overlay { trailing }
      ModeSettingsButton()
    }
    .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 10).frame(minHeight: 56)
  }
}

/// A filled, rounded button.
struct PlayButtonStyle: ButtonStyle {
  /// `.primary`, `.soft`, the plain `.btn`, `.accent`, `.danger`, and `.bare` for `.btn.plain`.
  enum Kind { case primary, soft, plain, accent, bare, danger }
  var kind = Kind.plain
  var height: CGFloat = 50
  var radius: CGFloat = 14
  var font: CGFloat = 16
  /// `.block`: as wide as its container.
  var block = false
  /// Side padding, when the default is too wide for the row.
  var inset: CGFloat?
  @Environment(\.isEnabled) private var enabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: font, weight: .semibold))
      .foregroundStyle(ink)
      .padding(.horizontal, inset ?? (height < 44 ? 14 : 20)).frame(maxWidth: block ? .infinity : nil, minHeight: height)
      .background(RoundedRectangle(cornerRadius: radius).fill(fill))
      .contentShape(RoundedRectangle(cornerRadius: radius))
      .opacity(enabled ? 1 : 0.35)
      .scaleEffect(configuration.isPressed ? 0.97 : 1)
  }

  private var ink: SwiftUI.Color {
    switch kind {
    case .primary: SwiftUI.Color(hex: 0x0b0b0e)
    case .accent: Theme.accentInk
    case .bare: Theme.text2
    case .danger: Theme.bad
    default: Theme.text
    }
  }

  private var fill: SwiftUI.Color {
    switch kind {
    case .primary: Theme.text
    case .soft: Theme.surface
    case .plain: Theme.surface2
    case .accent: Theme.accent
    case .bare: .clear
    case .danger: Theme.bad.opacity(0.14)
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
  /// The mode as the round is called: Play, Survival or Growth.
  var mode = "Play"
  var body: some View { IntroCover(mode: mode, trail: trail) }
}

/// The opening, on a pill over the board until your first move: `intro-pill`.
struct IntroPill: View {
  var name: String
  var body: some View {
    Text(name).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.text).lineLimit(1)
      .padding(.horizontal, 16).padding(.vertical, 6)
      .background(Capsule().fill(Theme.surface)).shadow(color: .black.opacity(0.5), radius: 15, y: 10)
      .allowsHitTesting(false)
      // Over the empty captured row above the board, not on the back rank's pieces.
      .offset(y: -36)
      .introPillIn()
  }
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

/// How the game ended: `.verdict`.
struct PlayVerdict: View {
  var over: PlayGame.Over

  var body: some View {
    let tone = over.result == .win ? Theme.good : over.result == .loss ? Theme.bad : Theme.warn
    HStack(spacing: 8) {
      Icon(name: over.result == .win ? "check" : "cross", size: over.result == .win ? 16 : 14)
        .frame(width: 26, height: 26).background(Circle().fill(tone.opacity(0.14)))
      Text(text).font(.system(size: 19, weight: .heavy)).tracking(-0.2).lineLimit(1).minimumScaleFactor(0.8)
    }
    .foregroundStyle(tone)
  }

  private var text: String {
    switch over.result {
    case .win: "Won by \(over.reason)"
    case .loss: "Lost by \(over.reason)"
    default: "Drawn by \(over.reason)"
    }
  }
}

/// Leaving your prep, said at once: `.banner`.
struct OffBookBanner: View {
  var detail: String
  var body: some View {
    HStack(spacing: 12) {
      Icon(name: "warn", size: 20).foregroundStyle(Theme.warn)
      VStack(alignment: .leading, spacing: 1) {
        Text("Out of your prep").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
        Text(detail).font(.system(size: 13)).foregroundStyle(Theme.text2)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 14).padding(.vertical, 12)
    .background(RoundedRectangle(cornerRadius: 16).fill(Theme.warn.opacity(0.14)))
  }
}
