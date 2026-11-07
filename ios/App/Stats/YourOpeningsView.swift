import Model
import SwiftUI

/// Rated openings shown before "Show all": the ones played last.
private let RATED_SHOWN = 6

/// The tab's own page: your favorites with this week's rating change on top,
/// then the graphs (the activity hero, the window, Survival's last runs,
/// rounds by mode and accuracy), and under them the other rated openings,
/// each with the rung it holds.
struct YourOpeningsView: View {
  let tree: OpeningTree
  @Binding var days: Int
  let onOpen: (String) -> Void
  @Environment(AppStore.self) private var store
  @State private var showAll = false

  var body: some View {
    let score = store.state.score
    let starred = store.state.settings.favoriteOpenings
    let stats = score.global
    let others = ratedOpenings(tree, score, starred)
    VStack(spacing: 0) {
      LargeTitleBar(title: "Stats")
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          FavoritesLadder().padding(.top, 8)
          ActivityHero(stats: stats, days: days).padding(.top, 16)
          SegmentedControl(value: $days, options: STATS_WINDOWS).padding(.top, 16)
          SurvivalRuns()
          ModeShare(stats: stats)
          AccuracySection(stats: stats, days: days)
          if !others.isEmpty { rated(others) }
        }
        .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 44)
      }
      .defaultScrollAnchor(StatsDebug.scrollToBottom ? .bottom : .top)
    }
  }

  private func rated(_ others: [Ranked]) -> some View {
    // Folded, the list keeps the openings played last, still in rating order.
    let recent = Set(others.jsSorted { ($1.stats.lastAt ?? 0) - ($0.stats.lastAt ?? 0) }.prefix(RATED_SHOWN).map(\.node.id))
    let shown = showAll ? others : others.filter { recent.contains($0.node.id) }
    return VStack(spacing: 0) {
      StatsSection(title: "Rated", aside: "by rating")
      ListCard {
        ForEach(shown, id: \.node.id) { RatedRow(entry: $0, onOpen: onOpen) }
        if others.count > RATED_SHOWN {
          Button { showAll.toggle() } label: {
            Text(showAll ? "Show fewer" : "Show all \(others.count)").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
              .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading).padding(.horizontal, 16).contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }
      }
    }
  }
}
