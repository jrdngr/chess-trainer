import Book
import ChessCore
import Engine
import Model
import SwiftUI

/// Autopilot: one Survival run after another, each decided for you. Stop is
/// the close button, and stopping goes Home. `AutopilotScreen.tsx`.
struct AutopilotView: View {
  let tree: OpeningTree
  let index: ReferenceIndex
  let onExit: () -> Void

  @Environment(AppStore.self) private var store
  @State private var history = AutoHistory()
  @State private var model: RunModel?
  @State private var nothing = false
  @State private var growth: GrowthModel?
  private static let engine = BasicEngine()

  var body: some View {
    Group {
      if let growth {
        GrowthView(model: growth, onNext: next)
      } else if let model {
        if model.phase == .over, let finish = model.finish {
          EndView(model: model, finish: finish, onNext: next, onGrow: grow, onExit: exit)
        } else {
          RunView(model: model, onExit: exit)
        }
      } else if nothing {
        VStack(spacing: 12) {
          Text("Nothing to practice yet").font(.headline).foregroundStyle(Theme.text)
          Text("Your Playbook has no lines in this selection.").foregroundStyle(Theme.text2)
          Button("Back", action: onExit).buttonStyle(.bordered)
        }
      } else {
        ProgressView().tint(Theme.text2)
      }
    }
    .task { if model == nil && !nothing { begin() } }
  }

  /// The next round, picked when it starts: what the last one changed is in the store by then.
  private func begin() {
    let selection = roundSelection(store.state, tree, last: store.lastFavorite, Env.random)
    guard let round = nextRound(store.state, tree, selection, history),
      let run = RunModel(round: round, selection: selection, store: store, tree: tree, index: index, engine: Self.engine)
    else {
      nothing = true
      return
    }
    if isAnyFavorite(store.state.settings.selection) { store.lastFavorite = selection.opening }
    model = run
    run.start()
  }

  private func grow(_ offer: GrowOffer) {
    growth = GrowthModel(offer: offer, store: store, tree: tree, index: index)
  }

  private func next() {
    growth = nil
    if let model { history = afterRound(history, model.round, model.selection) }
    model?.stop()
    model = nil
    begin()
  }

  private func exit() {
    model?.stop()
    onExit()
  }
}
