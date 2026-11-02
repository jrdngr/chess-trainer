import ChessCore
import Model
import SwiftUI
import UIKit

/// What a Survival run you set up came to, in points when moments, missions
/// or the combo were on, else in moves; and a new best.
struct SurvivalSummary: View {
  let finish: Finish
  let prefs: SurvivalPrefs
  let scoredInPoints: Bool
  /// The record as it stood before this run.
  let before: SurvivalRecord

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
    let moveBest = !ended && moves > 0 && moves > before.global.best
    let pointBest = scoredInPoints && !ended && points > 0 && points > before.global.bestPoints
    if moveBest && pointBest { return "New best, in points and moves" }
    if pointBest { return "New best score" }
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
        PlaySection(title: "Missed your prep \u{00b7} \(misses.count)")
        ListCard {
          ForEach(misses, id: \.ply) { miss in
            VStack(spacing: 0) {
            Button { onSeek(miss.ply) } label: {
              HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                  Text("Move \(moveNumber(miss.ply))").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                  Text("You played \(miss.played) \u{00b7} your prep \(miss.expected)").font(.system(size: 12.5)).foregroundStyle(Theme.text3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Icon(name: "chevron", size: 18).foregroundStyle(Theme.text3)
              }
              .padding(.horizontal, 16).padding(.vertical, 10).frame(minHeight: 54).contentShape(Rectangle())
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

/// Moves survived in every opening the game went through, shallowest first, then all openings.
struct MovesSurvivedList: View {
  let tree: OpeningTree
  let line: [String]
  let record: SurvivalRecord
  let moves: Int

  var body: some View {
    VStack(spacing: 0) {
      PlaySection(title: "Moves survived")
      ListCard {
        ForEach(along, id: \.self) { id in
          ScoreRow(name: nodeById(tree, id).name, score: survivalFor(record, id), now: moves)
        }
        ScoreRow(name: "All openings", score: record.global, now: moves)
      }
    }
  }

  /// The book names some positions twice at different depths: a name already shown is not shown again.
  private var along: [String] {
    var names = Set<String>()
    return openingsAlong(tree, line).filter { names.insert(nodeById(tree, $0).name).inserted }
  }
}

/// Copy the moves I played, and Change options back to the setup.
struct SurvivalEndActions: View {
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
