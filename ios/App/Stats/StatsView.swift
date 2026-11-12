import Book
import Model
import Shared
import SwiftUI

/// Stats: your openings, the others you have played, and the
/// activity of the whole game; every row opens that opening's own page over
/// it.
struct StatsView: View {
  let tree: OpeningTree
  let index: ReferenceIndex
  @Environment(AppStore.self) private var store
  @State private var openingId: String? = StatsDebug.openingId
  @State private var days = 30

  var body: some View {
    Group {
      if let openingId, !openingId.isEmpty {
        OpeningStatsView(tree: tree, node: nodeById(tree, openingId), days: $days, onOpen: { self.openingId = $0 }) {
          self.openingId = nil
        }
        .id(openingId)
      } else {
        YourOpeningsView(tree: tree, days: $days) { openingId = $0 }
      }
    }
    .task { StatsDebug.seedRound(store, tree) }
  }
}

/// Launch-env hooks for screenshots, in debug builds only.
enum StatsDebug {
  #if DEBUG
    private static var env: [String: String] { ProcessInfo.processInfo.environment }
  #else
    private static var env: [String: String] { [:] }
  #endif

  /// `STATS_OPEN=<opening id>` opens on that opening's page.
  static var openingId: String? { env["STATS_OPEN"] }

  /// `STATS_SCROLL=bottom` opens each page scrolled to its end.
  static var scrollToBottom: Bool { env["STATS_SCROLL"] == "bottom" }

  /// `STATS_ROUND=1` logs one Run round with nothing answered, as one
  /// Play round does, when none has been played yet.
  @MainActor static func seedRound(_ store: AppStore, _ tree: OpeningTree) {
    guard env["STATS_ROUND"] == "1", store.state.score.rounds.isEmpty else { return }
    let round = RoundRecord(mode: .run, openingId: "", color: .w, answered: 0, correct: 0, perfect: false, at: Env.now())
    store.update { $0.score = recordRound($0.score, tree, round) }
  }
}
