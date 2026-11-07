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

/// Your openings with their tier and rating, highest first, and how far the
/// rating moved this week: the ones most worth focusing on, then Show all.
/// Tapping one selects it. `OpeningsLadder`.
struct OpeningsLadder: View {
  @Environment(AppStore.self) private var store
  @State private var showAll = false

  static let shown = 6

  struct Row {
    var node: OpeningNode
    var side: ChessCore.Color
    var label: String
    var stats: NodeStats?
    var rated: Int { stats?.rated ?? 0 }
    var rating: Double { stats?.rating ?? 0 }
    var change: Int?
    var key: String { "\(side.rawValue) \(node.id)" }
  }

  /// Rated first, highest rating first.
  static func byRating(_ rows: [Row]) -> [Row] {
    rows.jsSorted { a, b in
      let r = cmp(b.rated > 0 ? 1 : 0, a.rated > 0 ? 1 : 0)
      return r != 0 ? r : b.rating - a.rating
    }
  }

  var body: some View {
    let all = self.rows
    let rows = Self.byRating(showAll ? all : Array(all.prefix(Self.shown)))
    if !rows.isEmpty {
      HomeCard(title: "Your openings", aside: "this week") {
        VStack(spacing: 2) {
          ForEach(rows, id: \.key) { row in
            let selected = store.state.settings.selection.opening == row.node.id
              && store.state.settings.selection.color == (row.side == .w ? .w : .b)
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
          if all.count > Self.shown {
            Button { showAll.toggle() } label: {
              Text(showAll ? "Show fewer" : "Show all \(all.count)")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text2).frame(maxWidth: .infinity).padding(10)
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

  /// Every one of your openings, most worth focusing on first.
  private var rows: [Row] {
    let now = Env.now()
    return store.yourOpenings().map { opening in
      let stats = store.state.score.nodes[opening.node.id]
      let rated = stats?.rated ?? 0
      return Row(
        node: opening.node, side: opening.side, label: shortLabel(opening.name), stats: stats,
        change: stats.flatMap { rated > 0 ? Int(JSRound(ratingChange($0, 7, now))) : nil })
    }
  }
}
