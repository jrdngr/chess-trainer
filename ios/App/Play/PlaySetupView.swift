import Model
import SwiftUI

/// What kind of game, and what to keep from it: `Setup.tsx`.
struct PlaySetupView: View {
  @Environment(AppStore.self) private var store
  let onStart: (PlayPrefs) -> Void
  let onExit: () -> Void

  var body: some View {
    let prefs = store.state.settings.play
    VStack(spacing: 0) {
      PlayAppBar(title: "Play", onClose: onExit) { Color.clear.frame(height: 1) }
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          SelectionBar().padding(.bottom, 12)
          Button { onStart(prefs) } label: { Text("Start").frame(maxWidth: .infinity) }
            .buttonStyle(PlayButtonStyle(kind: .primary, height: 56, radius: 16, font: 17))
          PlaySection(title: "Strength")
          SegmentedControl(
            value: Binding(get: { prefs.level }, set: { id in set { $0.level = id } }),
            options: LEVELS.map { ($0.id, $0.name) })
          PlaySection(title: "Keeping the opening")
          ListCard {
            ToggleRow(label: "Save the opening", hint: "Write the first \(OPENING_PLIES / 2) moves into your Playbook when the game ends",
                      on: prefs.save) { set { $0.save.toggle() } }
            ToggleRow(label: "Warn me off book", hint: "Say so the moment you leave your own prep, and remember it for practice",
                      on: prefs.warnOffBook) { set { $0.warnOffBook.toggle() } }
          }
          PlaySection(title: "Help")
          ListCard {
            ToggleRow(label: "Show the evaluation", hint: "A bar above the board while you play", on: prefs.showEval) { set { $0.showEval.toggle() } }
            ToggleRow(label: "Take backs", hint: "Undo your last move and the reply", on: prefs.takeBacks) { set { $0.takeBacks.toggle() } }
          }
        }
        .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 28)
      }
    }
  }

  /// `setModePrefs('play', patch)`.
  private func set(_ change: (inout PlayPrefs) -> Void) {
    store.update { change(&$0.settings.play) }
  }
}
