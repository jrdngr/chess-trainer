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

/// The last runs' moves survived as bars, the latest lit, a dashed line at
/// the best. Follows the selection. `SurvivalRuns` in `HomeWidgets.tsx`.
struct SurvivalRuns: View {
  @Environment(AppStore.self) private var store

  var body: some View {
    let selection = store.state.settings.selection
    let score = survivalFor(store.state.survival, selection.opening == ANY_FAVORITE ? "" : selection.opening)
    let runs = score.history
    HomeCard(title: "Survival", aside: score.best > 0 ? "best \(score.best)" : nil) {
      Canvas { context, size in
        let w = size.width, h = size.height
        let base = h - 14, top = 8.0
        let maxV = Double(max(10, score.best, runs.max() ?? 0)) * 1.1
        let y = { (v: Double) in base - (v / maxV) * (base - top) }
        let slot = (w - 8) / CGFloat(HISTORY_RUNS)
        let offset = HISTORY_RUNS - runs.count
        for i in 0..<HISTORY_RUNS {
          let x = 4 + CGFloat(i) * slot + 2
          if i < offset {
            context.fill(Path(roundedRect: CGRect(x: x, y: base - 3, width: slot - 4, height: 3), cornerRadius: 1.5), with: .color(Theme.surface2))
          } else {
            let bar = max(3, base - y(Double(runs[i - offset])))
            let last = i == HISTORY_RUNS - 1
            context.fill(Path(roundedRect: CGRect(x: x, y: base - bar, width: slot - 4, height: bar), cornerRadius: 3),
                         with: .color(last ? Theme.accent : Theme.surface3))
          }
        }
        if score.best > 0 {
          var line = Path()
          line.move(to: CGPoint(x: 4, y: y(Double(score.best))))
          line.addLine(to: CGPoint(x: w - 4, y: y(Double(score.best))))
          context.stroke(line, with: .color(Theme.warn), style: StrokeStyle(lineWidth: 1.5, dash: [3, 4]))
        }
        context.draw(Text("\(HISTORY_RUNS) runs ago").font(.system(size: 10)).foregroundStyle(Theme.text3), at: CGPoint(x: 4, y: h - 2), anchor: .bottomLeading)
        context.draw(Text("last").font(.system(size: 10)).foregroundStyle(Theme.text3), at: CGPoint(x: w - 4, y: h - 2), anchor: .bottomTrailing)
      }
      .aspectRatio(320 / 92, contentMode: .fit)
    }
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
            if let s = row.stats, s.extRated > 0 {
              HStack(spacing: 8) {
                Text("Extensions").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.ext).padding(.leading, 16)
                  .frame(maxWidth: .infinity, alignment: .leading)
                TierBar(rating: s.extRating, rated: s.extRated).frame(width: 96)
                Text("\(Int(JSRound(s.extRating)))").font(.system(size: 13, weight: .bold).monospacedDigit()).foregroundStyle(Theme.text2)
                  .frame(width: 30, alignment: .trailing)
                Spacer().frame(width: 38)
              }
              .padding(.horizontal, 6).frame(minHeight: 28)
            }
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
