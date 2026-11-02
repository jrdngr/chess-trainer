import Model
import SwiftUI

/// A toast for each milestone earned, once the round that earned it is
/// recorded; what was already earned when the app opened is never
/// announced. Rounds only go away in a reset, which starts the record over
/// from what is still earned after it.
struct MilestoneToasts: ViewModifier {
  @Environment(AppStore.self) private var store
  @Environment(Toasts.self) private var toasts
  @State private var announced: Set<String>?

  func body(content: Content) -> some View {
    content
      .onChange(of: store.tree != nil, initial: true) { mark() }
      .onChange(of: store.state.score.rounds.count) { old, new in
        if new < old { announced = store.tree == nil ? nil : Set(earnedNow.map(\.id)) } else { announce() }
      }
  }

  private var earnedNow: [Milestone] {
    guard let tree = store.tree else { return [] }
    return milestones(store.state.score, store.state.survival, tree).filter(earned)
  }

  private func mark() {
    guard announced == nil, store.tree != nil else { return }
    announced = Set(earnedNow.map(\.id))
  }

  private func announce() {
    guard var seen = announced else { return }
    let fresh = earnedNow.filter { !seen.contains($0.id) }
    for m in fresh { seen.insert(m.id) }
    announced = seen
    if !fresh.isEmpty { toasts.show("Milestone \u{00b7} \(fresh.map(\.label).joined(separator: ", "))") }
  }
}
