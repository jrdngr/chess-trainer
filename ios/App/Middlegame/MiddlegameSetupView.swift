import Model
import SwiftUI

/// The screen that decides a Middlegame run: which of your lines it plays out,
/// the opponent's strength and the clock. Start sits on top, as on Survival's.
struct MiddlegameSetupView: View {
  @Environment(AppStore.self) private var store
  let tree: OpeningTree
  let onStart: (SurvivalPrefs) -> Void
  let onExit: () -> Void

  var body: some View {
    let prefs = middlegamePrefs(store.state.settings.middlegame)
    let record = store.state.middlegame
    VStack(spacing: 0) {
      SurvivalBar(title: "Middlegame", subtitle: nil, onClose: onExit) { Color.clear.frame(width: 38, height: 1) }
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          SelectionBar().padding(.bottom, 12)
          Button { onStart(prefs) } label: { Text("Start").frame(maxWidth: .infinity) }
            .buttonStyle(PlayButtonStyle(kind: .primary, height: 56, radius: 16, font: 17))
          PlaySection(title: "Opponent steers toward")
          SegmentedControl(
            value: Binding(get: { prefs.steer }, set: { steer in set { $0.steer = steer } }),
            options: MIDDLEGAME_STEERS.map { ($0, survivalSteerLabel($0)) })
          PlaySection(title: "Opponent strength")
          SegmentedControl(
            value: Binding(get: { prefs.opponent }, set: { id in set { $0.opponent = id } }),
            options: [(value: OPPONENT_MATCH, label: "Match me")] + LEVELS.map { (value: $0.id, label: $0.name) })
          PlaySection(title: "Clock")
          SegmentedControl(
            value: Binding(get: { prefs.clock }, set: { clock in set { $0.clock = clock } }),
            options: CLOCK_MODES.map { ($0, clockLabel($0)) })
          PlaySection(title: "Feedback")
          ListCard {
            ToggleRow(label: "Move scores", on: prefs.moveScores) { set { $0.moveScores.toggle() } }
            ToggleRow(label: "Undefended flash", on: prefs.undefendedFlash) { set { $0.undefendedFlash.toggle() } }
          }
          if record.global.runs > 0 {
            PlaySection(title: "Middlegame points")
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

  private func set(_ change: (inout SurvivalPrefs) -> Void) {
    store.update { change(&$0.settings.middlegame) }
  }
}
