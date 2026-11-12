import Book
import ChessCore
import Model
import Shared
import SwiftUI

// The pieces of Growth's sitting: `.verdict`, the answer rows and their eval tags.

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
          Text(meta).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.text2).lineLimit(1)
          if let nudge, let note = nudge.pill { NudgeNote(text: note, tone: nudge.tone) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        DeltaTag(cp: delta)
      }
      .padding(.horizontal, 16).padding(.vertical, 8).frame(minHeight: 50)
      .background(roleTint(role)).contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private var meta: String {
    if option.games > 0 { return "\(Int(JSRound(option.share)))% of games" }
    return "Rarely played"
  }
}

/// Why a move matches or breaks your patterns, in the pattern's color.
struct NudgeNote: View {
  var text: String
  var tone: NudgeTone?

  var body: some View {
    Text(text).font(.system(size: 12, weight: .semibold)).foregroundStyle(nudgeColor(tone)).lineLimit(1)
  }
}

/// What an answer does to the eval bar, from your side: "+0.2", "−1.4", or "…" while the engine works.
/// Gray unless the move is clearly worse, so a normal book move doesn't read as a mistake.
struct DeltaTag: View {
  var cp: Double?
  /// A loss past this many centipawns shows red.
  static let clearlyWorse: Double = 50

  var body: some View {
    let worse = (cp ?? 0) < -Self.clearlyWorse
    Text(cp.map(formatDelta) ?? "\u{2026}").font(.system(size: 14).monospacedDigit())
      .foregroundStyle(worse ? Theme.bad : Theme.text3)
      .frame(minWidth: 40, alignment: .trailing)
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

/// The answers on offer at a hole, ranked, each in its arrow's color with its pattern note and eval change.
struct HoleAnswerList<Source: HoleAnswers>: View {
  let source: Source
  /// How many answers to list, best first; nil lists them all.
  var limit: Int? = nil
  let onPick: (String) -> Void

  var body: some View {
    let evals = source.evals
    let roles = source.roles
    let toned = source.toned
    ListCard {
      ForEach(limit.map { Array(source.ranked.prefix($0)) } ?? source.ranked, id: \.san) { option in
        AnswerRow(
          option: option, role: roles.first { $0.san == option.san }?.role,
          nudge: toned.first { $0.san == option.san && $0.tone != nil }, delta: source.delta(option.san, evals)
        ) { onPick(option.san) }
        .id(option.san)
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
