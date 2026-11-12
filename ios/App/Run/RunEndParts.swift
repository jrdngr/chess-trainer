import ChessCore
import Game
import Model
import SwiftUI
import UIKit

/// What a run you set up came to, in points when moments, missions
/// or the combo were on, else in moves; and a new best.
struct RunSummary: View {
  let finish: Finish
  let prefs: RunPrefs
  let scoredInPoints: Bool
  /// The record as it stood before this run.
  let before: RunRecord
  /// The record keeps points alone (Middlegame's), so only a points best counts.
  var pointsOnly = false

  var body: some View {
    let state = finish.ended
    let extras = state.extras
    VStack(spacing: 4) {
      Text(endingTitle(finish.how, state.run.played.count)).font(.system(size: 13)).foregroundStyle(Theme.text2)
      if scoredInPoints {
        Text("\(extras.points) point\(extras.points == 1 ? "" : "s")").font(.system(size: 26, weight: .bold).monospacedDigit())
          .foregroundStyle(Theme.text).padding(.top, 4)
        Text("Survived \(state.moves) move\(state.moves == 1 ? "" : "s")").font(.system(size: 13)).foregroundStyle(Theme.text)
        if !extraStats.isEmpty {
          Text(extraStats.joined(separator: " \u{00b7} ")).font(.system(size: 13)).foregroundStyle(Theme.text2)
        }
      } else {
        Text("Survived \(state.moves) move\(state.moves == 1 ? "" : "s")").font(.system(size: 22, weight: .bold))
          .foregroundStyle(Theme.text).padding(.top, 4)
      }
      if let best = newBestText {
        Text(best).font(.system(size: 13)).foregroundStyle(Theme.good).padding(.top, 4)
      }
    }
    .frame(maxWidth: .infinity).padding(.vertical, 20).padding(.horizontal, 16)
    .background(RoundedRectangle(cornerRadius: 18).fill(Theme.surface))
  }

  private var ended: Bool {
    if case .ended = finish.how { return true }
    return false
  }

  private var newBestText: String? {
    let moves = finish.ended.moves, points = finish.ended.extras.points
    let moveBest = !pointsOnly && !ended && moves > 0 && moves > before.global.best
    let pointBest = scoredInPoints && !ended && points > 0 && points > before.global.bestPoints
    if moveBest && pointBest { return "New best, in points and moves" }
    if pointBest { return pointsOnly ? "New best" : "New best score" }
    return moveBest ? "New best" : nil
  }

  private var extraStats: [String] {
    let x = finish.ended.extras
    var out: [String] = []
    let moments = x.moments.found + x.moments.missed
    if prefs.moments && moments > 0 { out.append("Moments \(x.moments.found) of \(moments)") }
    let missions = x.missions.done + x.missions.failed
    if prefs.missions && missions > 0 { out.append("Missions \(x.missions.done) of \(missions)") }
    if prefs.combo && x.bestCombo >= 3 { out.append("Best combo \u{00d7}\(comboMultiplier(x.bestCombo))") }
    return out
  }
}

/// The prepared positions answered with something else, each one a jump to it.
struct MissedPrepList: View {
  let misses: [Miss]
  var hints: [Int: TidyFind] = [:]
  var onTidy: ((TidyFind) -> Void)? = nil
  let onSeek: (Int) -> Void

  var body: some View {
    if !misses.isEmpty {
      VStack(spacing: 0) {
        PlaySection(title: "Missed your prep")
        ListCard {
          ForEach(misses, id: \.ply) { miss in
            VStack(spacing: 0) {
            Button { onSeek(miss.ply) } label: {
              HStack(spacing: 12) {
                Text("\(moveNumber(miss.ply))\(miss.ply % 2 == 0 ? "." : "...") \(miss.played)")
                  .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                Text("your prep \(miss.expected)").font(.system(size: 14)).foregroundStyle(Theme.text3)
                  .frame(maxWidth: .infinity, alignment: .leading)
                Icon(name: "chevron", size: 18).foregroundStyle(Theme.text3)
              }
              .padding(.horizontal, 16).frame(minHeight: 48).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let hint = hints[miss.ply], let onTidy { OffPrepHint(find: hint, onTidy: { onTidy(hint) }, compact: true) }
            }
          }
        }
      }
    }
  }
}

/// This run's count beside the best, for the opening it was played in and for all openings.
struct MovesSurvivedList: View {
  let tree: OpeningTree
  let line: [String]
  /// The opening the run was played in.
  let opening: String
  let record: RunRecord
  let moves: Int
  /// What the record counts: moves survived, or Middlegame's points.
  var title = "Moves survived"

  var body: some View {
    VStack(spacing: 0) {
      PlaySection(title: title, aside: "Best").padding(.trailing, 12)
      ListCard {
        if let shown { row(nodeById(tree, shown).name, runFor(record, shown)) }
        row("All openings", record.global)
      }
    }
  }

  /// The run's opening when the game went through it, else the deepest opening the game reached.
  private var shown: String? {
    let along = openingsAlong(tree, line)
    return along.contains(opening) ? opening : along.last
  }

  private func row(_ name: String, _ score: RunScore) -> some View {
    HStack(spacing: 12) {
      Text(name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
        .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
      Text("\(moves)").foregroundStyle(Theme.text)
      Text("\(score.best)").foregroundStyle(Theme.text2).frame(minWidth: 36, alignment: .trailing)
    }
    .font(.system(size: 15).monospacedDigit())
    .padding(.horizontal, 16).frame(minHeight: 48)
  }
}

/// Copy the moves I played, and Change options back to the setup.
struct RunEndActions: View {
  @Environment(Toasts.self) private var toasts
  @Environment(AppStore.self) private var store
  /// The moves as text: the run, and the blunder that ended it.
  let played: String
  let onChangeOptions: (() -> Void)?

  var body: some View {
    VStack(spacing: 0) {
      Button {
        UIPasteboard.general.string = played
        Haptics.buzz(10, on: store.state.settings.hapticFeedback)
        toasts.show("Moves copied")
      } label: {
        Label { Text("Copy the moves I played") } icon: { Icon(name: "download", size: 16) }.frame(maxWidth: .infinity)
      }
      .buttonStyle(PlayButtonStyle(kind: .plain, height: 38, radius: 12, font: 14))
      .disabled(played.isEmpty).padding(.top, 8)
      if let onChangeOptions {
        Button("Change options", action: onChangeOptions)
          .font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text2)
          .frame(maxWidth: .infinity, minHeight: 50).buttonStyle(.plain).padding(.top, 20)
      }
    }
  }
}

/// One opening's best and recent form, and this run's count beside it.
struct ScoreRow: View {
  var name: String
  var score: RunScore
  var now: Int?

  var body: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text(name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
        Text(meta).font(.system(size: 12.5)).foregroundStyle(Theme.text3)
      }
      .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
      if let now { Text("\(now)").foregroundStyle(Theme.text2) }
      Text("best \(score.best)").foregroundStyle(Theme.text2)
    }
    .font(.system(size: 14).monospacedDigit())
    .padding(.horizontal, 16).padding(.vertical, 10).frame(minHeight: 54)
  }

  private var meta: String {
    if score.runs == 0 && score.ended == 0 { return "No runs yet" }
    let form = recentForm(score)
    return [
      "\(score.runs) run\(score.runs == 1 ? "" : "s")",
      score.ended > 0 ? "\(score.ended) ended" : nil,
      form.map { "recent form \(Int($0))" },
    ].compactMap { $0 }.joined(separator: " \u{00b7} ")
  }
}
