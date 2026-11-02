import Model
import SwiftUI

/// Rated openings shown before "Show all": the ones played last.
private let RATED_SHOWN = 6

/// The tab's own page: your favorites and then the other rated openings, each
/// with the rung it holds, and under them the activity that is true of the
/// whole game.
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
    let mine = starredOpenings(tree, score, starred)
    let others = ratedOpenings(tree, score, starred)
    VStack(spacing: 0) {
      LargeTitleBar(title: "Stats")
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          StatsSection(title: "Favorites", aside: mine.isEmpty ? nil : "by rating", first: true)
          favorites(mine)
          if !others.isEmpty { rated(others) }
          StatsSection(title: "Activity")
          activity(stats)
          StatsSection(title: "Window")
          SegmentedControl(value: $days, options: STATS_WINDOWS)
          StatsSection(title: "Rounds a day")
          StatsCard { LineChart(points: dailyRounds(stats, days), color: Theme.accent) }
          AccuracySection(stats: stats, days: days)
          StatsSection(title: "By mode", aside: "rounds")
          StatsCard {
            BarList(rows: ACTIVITY_MODES.map { .init(label: modeName($0), value: stats.byMode[$0]?.rounds ?? 0) }, color: Theme.accent)
          }
          StatsNote(text: Text("Only Survival moves a rating. Drill and Growth are counted here and nowhere else."), center: true)
            .padding(.top, 12)
        }
        .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 44)
      }
      .defaultScrollAnchor(StatsDebug.scrollToBottom ? .bottom : .top)
    }
  }

  @ViewBuilder private func favorites(_ mine: [Ranked]) -> some View {
    if mine.isEmpty {
      StatsCard {
        Text("No favorites yet. Add openings to favorites in the picker to keep them here. Every opening Survival plays has a rating, which goes up when you find your prep and down when you miss it.")
          .font(.system(size: 13)).foregroundStyle(Theme.text2)
      }
    } else {
      ListCard { ForEach(mine, id: \.node.id) { RatedRow(entry: $0, onOpen: onOpen) } }
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

  private func activity(_ stats: NodeStats) -> some View {
    let rounds = roundsOf(stats)
    let daysPlayed = streak(stats)
    let acc = accuracy(answered: stats.answered, correct: stats.correct)
    return StatsHero(big: "\(rounds)", label: rounds == 1 ? "round" : "rounds") {
      FlowRow(spacing: 8) {
        if daysPlayed > 0 { StatsPill(dot: Theme.warn, bold: "\(daysPlayed)", text: "day streak") }
        if let acc { StatsPill(bold: percentText(acc), text: "accuracy") }
        StatsPill(bold: "\(stats.answered)", text: "answered")
      }
      .padding(.top, 16)
    }
  }
}

/// Accuracy over the window, a seven-day average.
struct AccuracySection: View {
  var stats: NodeStats
  var days: Int

  var body: some View {
    StatsSection(title: "Accuracy", aside: "seven-day average")
    StatsCard { LineChart(points: rollingAccuracy(stats, days), color: Theme.good, max: 1, percent: true) }
  }
}
