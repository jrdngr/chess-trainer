import Model
import SwiftUI

/// The Playbook as it will be, and the first run on Autopilot's plate.
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
    let moves = rows.reduce(0) { $0 + $1.moves }
    VStack(spacing: 0) {
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          Icon(name: "check", size: 22).foregroundStyle(Theme.good).frame(width: 44, height: 44)
            .background(Circle().fill(Theme.good.opacity(0.14))).padding(.leading, 4)
          Text("Your Playbook is ready").font(.system(size: 30, weight: .heavy)).tracking(-0.9).foregroundStyle(Theme.text)
            .padding(.horizontal, 4).padding(.top, 14).padding(.bottom, 4)
          Text("\(plural(moves, "move")) across \(plural(rows.count, "opening"))").font(.system(size: 14)).foregroundStyle(Theme.text2)
            .padding(.horizontal, 4).padding(.bottom, 18)
          ListCard {
            ForEach(rows, id: \.key) { row in
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
      if let first {
        let rep = state.repertoireList.first { $0.color == first.pick.color }
        Button { onDone(.autopilot) } label: {
          AutopilotPlate(
            name: store.catalog.map { selectionTrail(tree, $0, first.pick.opening.id).last ?? "" } ?? "",
            sans: first.pick.opening.sans, color: first.pick.color, span: roundSpan(rep, first.pick, first.at))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16).padding(.top, 24).padding(.bottom, 20)
      }
      OnboardBar {
        BigButton(label: first != nil ? "Play your first run" : "Go to Home") { onDone(first != nil ? .autopilot : .home) }
        if first != nil { SkipButton(label: "Go to Home") { onDone(.home) } }
      }
    }
  }
}
