import Model
import SwiftUI

/// The tab's own page: your openings with this week's rating change on top,
/// then the graphs (the activity hero with the window's switch, Survival's
/// last runs and accuracy).
struct YourOpeningsView: View {
  let tree: OpeningTree
  @Binding var days: Int
  let onOpen: (String) -> Void
  @Environment(AppStore.self) private var store

  var body: some View {
    let score = store.state.score
    let stats = score.global
    VStack(spacing: 0) {
      LargeTitleBar(title: "Stats")
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          OpeningsLadder().padding(.top, 8)
          ActivityHero(stats: stats, days: $days).padding(.top, 16)
          SurvivalRuns()
          AccuracySection(stats: stats, days: days)
        }
        .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 44)
      }
      .defaultScrollAnchor(StatsDebug.scrollToBottom ? .bottom : .top)
    }
  }
}
