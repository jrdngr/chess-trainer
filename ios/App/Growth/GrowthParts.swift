import Book
import ChessCore
import Model
import Shared
import SwiftUI

/// The pieces of Growth's sitting: `.prompt`, `.verdict`, the answer rows
/// and their eval tags, the pills over the board.

/// Who is to move and what it means: `.prompt`.
struct GrowthPrompt: View {
  var side: ChessCore.Color
  var who: String
  var ctx: String?

  var body: some View {
    VStack(spacing: 3) {
      HStack(spacing: 8) {
        SideDot(side: side)
        Text(who).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.8)
      }
      if let ctx {
        Text(ctx).font(.system(size: 13)).foregroundStyle(Theme.text3).multilineTextAlignment(.center)
      }
    }
    .frame(maxWidth: .infinity).padding(.top, 6).padding(.bottom, 2)
  }
}

/// A verdict line: `.verdict` and its tone.
struct GrowthVerdict: View {
  enum Tone { case ok, warn, no }
  var tone: Tone
  var text: String

  var body: some View {
    let ink = tone == .ok ? Theme.good : tone == .warn ? Theme.warn : Theme.bad
    HStack(spacing: 8) {
      Icon(name: tone == .ok ? "check" : tone == .warn ? "warn" : "cross", size: tone == .no ? 14 : 16)
        .frame(width: 26, height: 26).background(Circle().fill(ink.opacity(0.14)))
      Text(text).font(.system(size: 19, weight: .heavy)).tracking(-0.2).lineLimit(1).minimumScaleFactor(0.8)
    }
    .foregroundStyle(ink)
  }
}

/// The colour of an answer's arrow and row, by who recommends it: `roleColor`.
func roleColor(_ role: AnswerRole?) -> SwiftUI.Color? {
  switch role {
  case .strong: Theme.book
  case .engine: Theme.accent
  case .engineNext: SwiftUI.Color(hex: 0xb3b4ff)
  case nil: nil
  }
}

/// The tint a role gives its row: `.list-row.role-*`.
private func roleTint(_ role: AnswerRole?) -> SwiftUI.Color {
  switch role {
  case .strong: Theme.book.opacity(0.13)
  case .engine: Theme.accent.opacity(0.16)
  case .engineNext: Theme.accent.opacity(0.08)
  case nil: .clear
  }
}

/// One answer on offer: the move, how often it is played, what it does to the eval.
struct AnswerRow: View {
  var option: Reply
  var role: AnswerRole?
  var nudge: NudgedMove?
  var delta: Double?
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Text(option.san).font(.system(size: 17, weight: .bold).monospacedDigit())
          .foregroundStyle(roleColor(role) ?? Theme.text).frame(minWidth: 56, alignment: .leading)
        VStack(alignment: .leading, spacing: 4) {
          Text(meta).font(.system(size: 12.5)).foregroundStyle(Theme.text3).multilineTextAlignment(.leading)
          if let nudge, let pill = nudge.pill { NudgePill(text: pill, tone: nudge.tone) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        DeltaTag(cp: delta)
        Icon(name: "plus", size: 18).foregroundStyle(Theme.text)
      }
      .padding(.horizontal, 16).padding(.vertical, 10).frame(minHeight: 54)
      .background(roleTint(role)).contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private var meta: String {
    if option.games > 0 {
      return "\(JS.string(option.share))% of strong players' replies \u{00b7} \(formatGameCount(option.games)) games"
    }
    return option.engine ? "Engine's pick \u{00b7} past the book" : "Not in the book \u{00b7} passed by the engine"
  }
}

/// Why a move matches or breaks your patterns: `.nudge-pill`.
struct NudgePill: View {
  var text: String
  var tone: NudgeTone?

  var body: some View {
    let ink = nudgeColor(tone)
    Text(text).font(.system(size: 11, weight: .bold)).foregroundStyle(ink)
      .padding(.horizontal, 7).padding(.vertical, 2)
      .background(Capsule().fill(ink.opacity(0.14)))
  }
}

/// What an answer does to the eval bar, from your side: "+0.2", "−1.4", or "…" while the engine works.
struct DeltaTag: View {
  var cp: Double?

  var body: some View {
    let tone = cp.map(deltaTone) ?? .even
    Text(cp.map(formatDelta) ?? "\u{2026}").font(.system(size: 14).monospacedDigit())
      .foregroundStyle(tone == .good ? Theme.good : tone == .bad ? Theme.bad : Theme.text3)
      .frame(minWidth: 40, alignment: .trailing).padding(.trailing, 8)
  }
}

/// The opening on a pill over the board while the way in plays: `intro-pill`.
struct GrowthIntroPill: View {
  var name: String
  var autoplay: Bool

  var body: some View {
    HStack(spacing: 8) {
      if autoplay {
        Text("Autoplay").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.background)
          .padding(.horizontal, 9).padding(.vertical, 3).background(Capsule().fill(Theme.accent))
      }
      Text(name).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.text).lineLimit(1)
    }
    .padding(.leading, autoplay ? 8 : 16).padding(.trailing, 16).padding(.vertical, 8)
    .background(Capsule().fill(Theme.surface)).shadow(color: .black.opacity(0.5), radius: 15, y: 10)
    .allowsHitTesting(false)
    // Over the gap above the board, not on the back rank's pieces.
    .offset(y: -42)
  }
}

/// A verdict lifted onto the board: `.board-flash`.
struct BoardFlash: View {
  var text: String

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 14).fill(.black.opacity(0.35))
      Text(text).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.text)
        .padding(.leading, 22).padding(.trailing, 22).padding(.vertical, 12)
        .background(Capsule().fill(Theme.surface)).shadow(color: .black.opacity(0.5), radius: 15, y: 10)
    }
    .boardFlash()
  }
}

/// The line under the board, your added moves in green: `Strip`.
func growthStrip(_ path: [String], _ added: [Int], _ color: ChessCore.Color) -> [StripItem] {
  path.enumerated().map { i, san in
    StripItem(
      san: san, label: i % 2 == 0 ? "\(i / 2 + 1)." : nil,
      tone: added.contains(i) ? .good : (i % 2 == 0) == (color == .w) ? .mine : .theirs,
      current: i == path.count - 1)
  }
}

/// "up to 3", then "1 of 3 added": the Answer it section's aside.
func answerAside(added: Int, of size: Int) -> String {
  added > 0 ? "\(added) of \(size) added" : "up to \(size)"
}

/// The answers on offer at a hole, ranked, each in its arrow's color with its pattern pill and eval change.
struct HoleAnswerList<Source: HoleAnswers>: View {
  let source: Source
  let onPick: (String) -> Void

  var body: some View {
    let evals = source.evals
    let roles = source.roles
    let toned = source.toned
    ListCard {
      ForEach(source.ranked, id: \.san) { option in
        AnswerRow(
          option: option, role: roles.first { $0.san == option.san }?.role,
          nudge: toned.first { $0.san == option.san && $0.tone != nil }, delta: source.delta(option.san, evals)
        ) { onPick(option.san) }
      }
    }
  }
}

/// The role arrows at a hole, glowing where a move matches or breaks your patterns,
/// and a familiar move nobody recommends in gray: least important first.
@MainActor func holeArrows(_ source: some HoleAnswers) -> [BoardArrow] {
  let roles = source.roles
  let toned = source.toned
  let glow = { (san: String) in toned.first { $0.san == san && $0.tone != nil }.map { nudgeColor($0.tone) } }
  let familiar = toned.filter { move in (move.tone == .toward || move.tone == .towardFar) && !roles.contains { $0.san == move.san } }
    .map { BoardArrow(from: $0.from, to: $0.to, color: Theme.text2, glow: nudgeColor($0.tone)) }
  return familiar + roles.reversed().map { BoardArrow(from: $0.from, to: $0.to, color: roleColor($0.role) ?? Theme.accent, glow: glow($0.san)) }
}
