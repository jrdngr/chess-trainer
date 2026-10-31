import Model
import SwiftUI

/// Home: the Autopilot button, named for the next round's opening. `HomeScreen.tsx`.
struct HomeView: View {
  let tree: OpeningTree
  let onPlay: () -> Void
  @Environment(AppStore.self) private var store

  var body: some View {
    let state = store.state
    VStack(alignment: .leading, spacing: 18) {
      Text("Playbook").font(.largeTitle.bold()).foregroundStyle(Theme.text)
      Button(action: onPlay) {
        VStack(alignment: .leading, spacing: 6) {
          Text("Autopilot").font(.title2.bold()).foregroundStyle(Theme.text)
          Text(openingName(tree, state.settings.selection.opening)).foregroundStyle(Theme.text2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.surface))
      }
      HStack(spacing: 12) {
        tile("\(state.survival.global.best)", "Best run")
        tile("\(streak(state.score.global))", "Day streak")
        tile("\(state.score.global.byMode[.survival]?.rounds ?? 0)", "Runs")
      }
      if !state.settings.favoriteOpenings.isEmpty {
        Text("Favorites").font(.headline).foregroundStyle(Theme.text)
        ForEach(state.settings.favoriteOpenings, id: \.self) { id in
          let stats = nodeStats(state.score, id)
          let rank = rankOf(stats.rating, stats.rated)
          HStack {
            Text(openingName(tree, id)).foregroundStyle(Theme.text)
            Spacer()
            Text(rank.heldLabel).foregroundStyle(Theme.text2)
            Text("\(Int(JSRound(stats.rating)))").monospacedDigit().foregroundStyle(Theme.text)
          }
          .padding(.vertical, 4)
        }
      }
      Spacer()
    }
    .padding()
  }

  private func tile(_ value: String, _ label: String) -> some View {
    VStack {
      Text(value).font(.title2.bold().monospacedDigit()).foregroundStyle(Theme.text)
      Text(label).font(.caption).foregroundStyle(Theme.text2)
    }
    .frame(maxWidth: .infinity).padding(.vertical, 12)
    .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
  }
}
