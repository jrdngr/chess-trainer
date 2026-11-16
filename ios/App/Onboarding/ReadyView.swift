import Game
import Model
import SwiftUI

/// The Playbook as it will be, and Play to start the first run.
/// Nothing goes in until one of the buttons is tapped. `Ready`.
struct ReadyView: View {
  let tree: OpeningTree
  let rows: [PendingOpening]
  let onMore: () -> Void
  let onDone: (OnboardingNext) -> Void

  @Environment(AppStore.self) private var store
  @State private var memo = Memo<AppState>()

  var body: some View {
    let state = memo.get(pendingKey(rows)) { onboardedState(store.state, tree, rows) }
    let first = nextRound(state, tree, store.peekRoundSelection(state), AutoHistory())
    let shown = readyRows(rows)
    let moves = countOwnMoves(rows.map { (sans: $0.sans, color: $0.color) })
    VStack(spacing: 0) {
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          Icon(name: "check", size: 22).foregroundStyle(Theme.good).frame(width: 44, height: 44)
            .background(Circle().fill(Theme.good.opacity(0.14))).padding(.leading, 4)
          Text("Your Playbook is ready").font(.system(size: 30, weight: .heavy)).tracking(-0.9).foregroundStyle(Theme.text)
            .padding(.horizontal, 4).padding(.top, 14).padding(.bottom, 4)
          Text("\(plural(moves, "move")) across \(plural(shown.count, "opening"))").font(.system(size: 14)).foregroundStyle(Theme.text2)
            .padding(.horizontal, 4).padding(.bottom, 18)
          ListCard {
            ForEach(shown, id: \.key) { row in
              HStack(spacing: 12) {
                SideSquare(color: row.color)
                Text(row.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text).frame(maxWidth: .infinity, alignment: .leading)
                Text(plural(row.moves, "move")).font(.system(size: 14)).foregroundStyle(Theme.text2)
              }
              .padding(.horizontal, 16).padding(.vertical, 10).frame(minHeight: 54)
            }
          }
          BigButton(label: "Add more openings", icon: "plus", accent: false, xl: false, soft: true, action: onMore).padding(.top, 12)
        }
        .padding(.horizontal, 16).padding(.top, 56)
      }
      OnboardBar {
        BigButton(label: first != nil ? "Play" : "Go to Home") { onDone(first != nil ? .play : .home) }
        if first != nil { SkipButton(label: "Go to Home") { onDone(.home) } }
      }
    }
  }
}

/// The ready screen's rows: openings of one side with one name are one row,
/// their moves counted once each.
func readyRows(_ rows: [PendingOpening]) -> [PendingOpening] {
  var out: [PendingOpening] = []
  for row in rows {
    if let at = out.firstIndex(where: { $0.color == row.color && $0.name == row.name }) {
      out[at].key += "|" + row.key
      let group = rows.filter { $0.color == row.color && $0.name == row.name }
      out[at].moves = countOwnMoves(group.map { (sans: $0.sans, color: $0.color) })
    } else {
      out.append(row)
    }
  }
  return out
}
