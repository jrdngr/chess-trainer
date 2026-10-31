import Model
import SwiftUI

/// A rating's place between its tier and the next: `RankBar` in `ScoreBar.tsx`.
struct RankBar<Centre: View>: View {
  var rank: Rank
  @ViewBuilder var centre: Centre

  var body: some View {
    let fill = SwiftUI.Color(hexString: (rank.held ?? rank.next ?? UNRATED).color)
    VStack(spacing: 6) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(rank.heldLabel).frame(maxWidth: .infinity, alignment: .leading)
        centre.font(.system(size: 14, weight: .heavy).monospacedDigit()).foregroundStyle(Theme.text)
        Text(rank.nextLabel ?? "").frame(maxWidth: .infinity, alignment: .trailing)
      }
      .font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.text2).lineLimit(1)
      GeometryReader { geo in
        ZStack(alignment: .leading) {
          Capsule().fill(Theme.surface3)
          paint(rank.rating).frame(width: geo.size.width)
            .mask(alignment: .leading) { Capsule().frame(width: geo.size.width * rank.progress) }
            .shadow(color: fill.opacity(0.7), radius: 4)
        }
      }
      .frame(height: 8)
    }
  }
}

/// The rating of the opening you have selected: its tier, its rating and how
/// far it is from the next. Nothing for Any opening or Any favorite. `ScoreStrip`.
struct ScoreStrip: View {
  @Environment(AppStore.self) private var store

  var body: some View {
    let selection = store.state.settings.selection
    if let tree = store.tree, selection.opening != "", selection.opening != ANY_FAVORITE {
      let node = nodeById(tree, selection.opening)
      let stats = nodeStats(store.state.score, node.id)
      let favorite = store.state.settings.favoriteOpenings.contains(node.id)
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 4) {
          if !favorite { Icon(name: "star", size: 11) }
          Text(node.name).lineLimit(1)
        }
        .font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.text3)
        RankBar(rank: rankOf(stats.rating, stats.rated)) {
          Text(stats.rated == 0 ? NEW_LABEL : "\(Int(JSRound(stats.rating)))").font(.system(size: 16, weight: .heavy).monospacedDigit())
        }
      }
      .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 13)
      .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
    }
  }
}
