import ChessCore
import Game
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

/// Your openings with their form: the ones most worth focusing on, then Show all.
/// Tapping one opens it with `onOpen`, or selects it with none. `OpeningsLadder`.
struct OpeningsLadder: View {
  var onOpen: ((String) -> Void)?
  @Environment(AppStore.self) private var store
  @State private var showAll = false

  static let shown = 6

  struct Row {
    var node: OpeningNode
    var side: ChessCore.Color
    var label: String
    var bars: Int?
    var key: String { "\(side.rawValue) \(node.id)" }
  }

  var body: some View {
    let all = self.rows
    let rows = showAll ? all : Array(all.prefix(Self.shown))
    if !rows.isEmpty {
      HomeCard(title: "Your openings") {
        VStack(spacing: 2) {
          ForEach(rows, id: \.key) { row in
            let selected = onOpen == nil && store.state.settings.selection.opening == row.node.id
              && store.state.settings.selection.color == (row.side == .w ? .w : .b)
            Button {
              if let onOpen { onOpen(row.node.id); return }
              store.update { $0.settings.selection = Selection(color: row.side == .w ? .w : .b, opening: row.node.id) }
            } label: {
              HStack(spacing: 8) {
                SideDot(side: row.side)
                Text(row.label).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                  .frame(maxWidth: .infinity, alignment: .leading)
                FormBars(bars: row.bars).frame(width: 32, alignment: .trailing)
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

  /// Every one of your openings, most worth focusing on first.
  private var rows: [Row] {
    store.yourOpenings().map { opening in
      Row(node: opening.node, side: opening.side, label: shortLabel(opening.name), bars: store.state.form.bars(opening.node.id, opening.side))
    }
  }
}
