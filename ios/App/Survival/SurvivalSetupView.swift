import Model
import SwiftUI

/// The screen that decides a Survival run: what the opponent steers toward,
/// and the clock. Start sits on top, so the same run as last time is one tap.
struct SurvivalSetupView: View {
  @Environment(AppStore.self) private var store
  let tree: OpeningTree
  let onStart: (SurvivalPrefs) -> Void
  let onExit: () -> Void

  var body: some View {
    let prefs = store.state.settings.survival
    let record = store.state.survival
    VStack(spacing: 0) {
      SurvivalBar(subtitle: nil, onClose: onExit) { Color.clear.frame(width: 38, height: 1) }
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          SelectionBar().padding(.bottom, 12)
          Button { onStart(prefs) } label: { Text("Start").frame(maxWidth: .infinity) }
            .buttonStyle(PlayButtonStyle(kind: .primary, height: 56, radius: 16, font: 17))
          PlaySection(title: "Opponent steers toward")
          SegmentedControl(
            value: Binding(get: { prefs.steer }, set: { steer in set { $0.steer = steer } }),
            options: SURVIVAL_STEERS.map { ($0, survivalSteerLabel($0)) })
          note(steerNote(prefs.steer))
          PlaySection(title: "Opponent strength")
          SegmentedControl(
            value: Binding(get: { prefs.opponent }, set: { id in set { $0.opponent = id } }),
            options: [(value: OPPONENT_MATCH, label: "Match me")] + LEVELS.map { (value: $0.id, label: $0.name) })
          PlaySection(title: "Clock")
          SegmentedControl(
            value: Binding(get: { prefs.clock }, set: { clock in set { $0.clock = clock } }),
            options: CLOCK_MODES.map { ($0, clockLabel($0)) })
          note("A run lasts until your first blunder. A sound move where your prep had another is a miss: it is shown, logged for review, and the game goes on.")
          PlaySection(title: "Feedback")
          ListCard {
            ToggleRow(label: "Move scores", hint: "What each move the engine judges cost you, in centipawns, over its square",
                      on: prefs.moveScores) { set { $0.moveScores.toggle() } }
            ToggleRow(label: "Board glow", hint: "The board's edge tints green when you are better and red when you are worse",
                      on: prefs.boardGlow) { set { $0.boardGlow.toggle() } }
            ToggleRow(label: "Undefended flash", on: prefs.undefendedFlash) { set { $0.undefendedFlash.toggle() } }
          }
          PlaySection(title: "Past the opening")
          ListCard {
            ToggleRow(label: "Moments", on: prefs.moments) { set { $0.moments.toggle() } }
            ToggleRow(label: "Missions", on: prefs.missions) { set { $0.missions.toggle() } }
            ToggleRow(label: "Combo", on: prefs.combo) { set { $0.combo.toggle() } }
          }
          if record.global.runs > 0 {
            PlaySection(title: "Moves survived")
            ListCard {
              if let opening { ScoreRow(name: opening.name, score: survivalFor(record, opening.id)) }
              ScoreRow(name: "All openings", score: record.global)
            }
          }
        }
        .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 28)
      }
    }
  }

  /// The one opening selected, not Any favorite.
  private var opening: OpeningNode? {
    let id = store.state.settings.selection.opening
    return id.isEmpty || id == ANY_FAVORITE ? nil : nodeById(tree, id)
  }

  private func steerNote(_ steer: SurvivalSteer) -> String {
    switch steer {
    case .gaps: "The opponent walks you to a reply you have no answer to, and the game goes on past it."
    case .book: "The opponent plays what strong players choose most, with no idea what you have prepared."
    case .lines:
      "Your lines, weighted by what strong players choose, every reply you prepared coming up often, leaning toward the ones you miss."
    }
  }

  /// `.note`: small print under a control.
  private func note(_ text: String) -> some View {
    Text(text).font(.system(size: 12)).foregroundStyle(Theme.text3).lineSpacing(2)
      .padding(.horizontal, 4).padding(.top, 6)
  }

  /// `setSurvivalPrefs(patch)`.
  private func set(_ change: (inout SurvivalPrefs) -> Void) {
    store.update { change(&$0.settings.survival) }
  }
}

/// One opening's best and recent form, and this run's count beside it.
struct ScoreRow: View {
  var name: String
  var score: SurvivalScore
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
