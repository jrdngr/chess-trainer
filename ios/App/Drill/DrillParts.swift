import ChessCore
import Model
import SwiftUI

/// What each grade button says.
let GRADE_LABELS: [Grade: String] = [.again: "Guessed", .hard: "Hard", .good: "Knew it", .easy: "Easy"]

/// The count in the app bar: `.chip.num.wide`.
struct CountChip: View {
  var text: String
  var body: some View {
    Text(text).font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.text2)
      .padding(.horizontal, 10).padding(.vertical, 4).frame(minWidth: 52)
      .background(Capsule().fill(Theme.surface2))
  }
}

/// Whose move, and where in the sitting: `.prompt`.
struct DrillPrompt: View {
  var side: ChessCore.Color
  var title: String
  var context: String

  var body: some View {
    VStack(spacing: 3) {
      HStack(spacing: 8) {
        SideDot(side: side)
        Text(title).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.text)
      }
      Text(context).font(.system(size: 13)).foregroundStyle(Theme.text3)
    }
    .frame(maxWidth: .infinity).padding(.top, 6).padding(.bottom, 2)
  }
}

/// A verdict with its icon: `.verdict` and its tones.
struct DrillVerdict: View {
  enum Tone { case ok, no, warn }
  var tone: Tone
  var text: String

  var body: some View {
    let ink = tone == .ok ? Theme.good : tone == .no ? Theme.bad : Theme.warn
    HStack(spacing: 8) {
      Icon(name: tone == .ok ? "check" : tone == .no ? "cross" : "warn", size: tone == .no ? 14 : 16)
        .frame(width: 26, height: 26).background(Circle().fill(ink.opacity(0.14)))
      Text(text).font(.system(size: 19, weight: .heavy)).tracking(-0.2).lineLimit(1).minimumScaleFactor(0.8)
    }
    .foregroundStyle(ink)
  }
}

/// Two values side by side, the prepared one green, the played one red: `.compare`.
struct CompareCards: View {
  var good: (key: String, value: String)
  var bad: (key: String, value: String)
  /// The played move first, as the Why sheet has it.
  var badFirst = false

  var body: some View {
    HStack(spacing: 10) {
      if badFirst { card(bad, Theme.bad); card(good, Theme.good) } else { card(good, Theme.good); card(bad, Theme.bad) }
    }
  }

  private func card(_ pair: (key: String, value: String), _ ink: SwiftUI.Color) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(pair.key).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text3)
      Text(pair.value).font(.system(size: 22, weight: .heavy)).tracking(-0.2).foregroundStyle(ink).lineLimit(1)
    }
    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.vertical, 12)
    .background(RoundedRectangle(cornerRadius: 18).fill(Theme.surface))
  }
}

/// The four grades, the given one selected: `.grades.sm`.
struct GradeRow: View {
  var selected: Grade
  var onPick: (Grade) -> Void

  var body: some View {
    HStack(spacing: 8) {
      ForEach(Grade.allCases, id: \.self) { g in
        Button { onPick(g) } label: {
          Text(GRADE_LABELS[g]!).font(.system(size: 13, weight: .bold))
            .foregroundStyle(g == .again ? Theme.bad : g == .easy ? Theme.good : Theme.text)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(RoundedRectangle(cornerRadius: 11).fill(g == selected ? Theme.surface3 : Theme.surface))
            .overlay { if g == selected { RoundedRectangle(cornerRadius: 11).strokeBorder(Theme.text, lineWidth: 2) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
    }
  }
}

/// Movetext on a card: `.card.movetext`.
struct MoveTextCard: View {
  var text: String
  var body: some View {
    Text(text).font(.system(size: 13, design: .monospaced)).lineSpacing(9).foregroundStyle(Theme.text2)
      .frame(maxWidth: .infinity, alignment: .leading).padding(16)
      .background(RoundedRectangle(cornerRadius: 18).fill(Theme.surface))
  }
}

/// A soft button that fills its share of a row.
struct SoftButton: View {
  var title: String
  var action: () -> Void
  var body: some View {
    Button(action: action) { Text(title).lineLimit(1).minimumScaleFactor(0.8).frame(maxWidth: .infinity) }
      .buttonStyle(PlayButtonStyle(kind: .soft))
  }
}

/// Continue, after a miss: `.btn.primary.sm` with its arrow.
struct ContinueButton: View {
  var action: () -> Void
  var body: some View {
    Button(action: action) { HStack(spacing: 8) { Text("Continue"); Icon(name: "next", size: 16) } }
      .buttonStyle(PlayButtonStyle(kind: .primary, height: 38, radius: 11, font: 14))
  }
}

/// The squares a move went from and to, in one tone.
func squares(_ move: LegalMove?, _ tone: SwiftUI.Color) -> [String: SwiftUI.Color] {
  guard let move else { return [:] }
  return [move.from: tone, move.to: tone]
}

extension View {
  /// The board dimmed while a miss is explained: `dimmed`.
  func dimmed(_ on: Bool) -> some View {
    colorMultiply(on ? SwiftUI.Color(white: 0.8) : .white).saturation(on ? 0.8 : 1).animation(.easeInOut(duration: 0.2), value: on)
  }
}
