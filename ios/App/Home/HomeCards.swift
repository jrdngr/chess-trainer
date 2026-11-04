import ChessCore
import Model
import Shared
import SwiftUI

/// A card on Home with its title and an aside.
struct HomeCard<Content: View>: View {
  var title: String
  var aside: String?
  @ViewBuilder var content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        Text(title).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.text)
        Spacer()
        if let aside { Text(aside).font(.system(size: 12.5).monospacedDigit()).foregroundStyle(Theme.text2) }
      }
      content
    }
    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 20).fill(Theme.surface))
  }
}

/// Every favorite with its tier and rating, highest first, and how far the
/// rating moved this week. Tapping one selects it. `FavoritesLadder`.
struct FavoritesLadder: View {
  @Environment(AppStore.self) private var store

  struct Row {
    var node: OpeningNode
    var side: ChessCore.Color
    var label: String
    var stats: NodeStats?
    var rated: Int { stats?.rated ?? 0 }
    var rating: Double { stats?.rating ?? 0 }
    var change: Int?
  }

  var body: some View {
    let rows = self.rows
    if !rows.isEmpty {
      HomeCard(title: "Favorites", aside: "this week") {
        VStack(spacing: 2) {
          ForEach(rows, id: \.node.id) { row in
            let selected = store.state.settings.selection.opening == row.node.id
            Button {
              store.update { $0.settings.selection = Selection(color: row.side == .w ? .w : .b, opening: row.node.id) }
            } label: {
              HStack(spacing: 8) {
                SideDot(side: row.side)
                Text(row.label).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                  .frame(maxWidth: .infinity, alignment: .leading)
                TierBar(rating: row.rating, rated: row.rated).frame(width: 96)
                Text(row.rated > 0 ? "\(Int(JSRound(row.rating)))" : "").font(.system(size: 13, weight: .bold).monospacedDigit())
                  .foregroundStyle(Theme.text2).frame(width: 30, alignment: .trailing)
                change(row.change).frame(width: 38, alignment: .trailing)
              }
              .padding(.horizontal, 6).frame(minHeight: 36)
              .background(RoundedRectangle(cornerRadius: 10).fill(selected ? Theme.accent.opacity(0.16) : .clear))
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
          }
        }
        .padding(.horizontal, -6)
      }
    }
  }

  private func change(_ c: Int?) -> some View {
    Text(c == nil ? "" : c == 0 ? "\u{2013}" : "\(c! > 0 ? "\u{25b2}" : "\u{25bc}")\(abs(c!))")
      .font(.system(size: 12, weight: .bold).monospacedDigit())
      .foregroundStyle(c == nil || c == 0 ? Theme.text3 : c! > 0 ? Theme.good : Theme.bad)
  }

  private var rows: [Row] {
    guard let tree = store.tree, let catalog = store.catalog else { return [] }
    let now = Env.now()
    return store.state.settings.favoriteOpenings.compactMap { tree.byId[$0] }.filter { $0.depth > 0 }
      .map { node in
        let stats = store.state.score.nodes[node.id]
        let rated = stats?.rated ?? 0
        return Row(
          node: node, side: sideForPick(catalog, node) ?? .w, label: favoriteLabel(catalog, node), stats: stats,
          change: stats.flatMap { rated > 0 ? Int(JSRound(ratingChange($0, 7, now))) : nil })
      }
      .jsSorted { a, b in
        let r = cmp(b.rated > 0 ? 1 : 0, a.rated > 0 ? 1 : 0)
        return r != 0 ? r : b.rating - a.rating
      }
  }
}
