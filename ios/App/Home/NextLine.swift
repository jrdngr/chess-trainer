import Game
import Model
import SwiftUI

/// Home's one line on what the Playbook grows next and when. A tap opens the
/// Playbook tree at that opening.
struct NextLine: View {
  let tree: OpeningTree
  let onOpen: (MapNode) -> Void
  @Environment(AppStore.self) private var store
  @State private var memo = Memo<MapNode?>()

  var body: some View {
    if let node = next, let runs = runsOf(node) {
      Button { onOpen(node) } label: {
        HStack(spacing: 10) {
          (Text("Next: ").foregroundStyle(Theme.accent) + Text("\(nameBelow(node.name, nil)) \(nextWhen(runs))").foregroundStyle(Theme.text))
            .font(.system(size: 15, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity, alignment: .leading)
          Icon(name: "chevron", size: 18).foregroundStyle(Theme.text3)
        }
        .padding(.leading, 15).padding(.trailing, 14).frame(minHeight: 55)
        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.surface))
        .contentShape(RoundedRectangle(cornerRadius: 18))
      }
      .buttonStyle(.plain)
    }
  }

  private func runsOf(_ node: MapNode) -> Int? {
    if case .next(let runs) = node.state { return runs }
    return nil
  }

  /// The Next opening, kept until the Playbook, the games or the form change.
  private var next: MapNode? {
    let state = store.state
    let key = state.playbookList.map { "\($0.id):\($0.nodes.count)" }.joined(separator: ",")
      + "|\(lastAddedAt(state.playbookList))|\(state.games.count)|\(state.form.stamp)"
      + "|\(state.owns(.sidePicker))"
    return memo.get(key) { nextMapNode(state, tree) }
  }
}
