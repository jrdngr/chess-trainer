import Book
import ChessCore
import Engine
import Model
import SwiftUI

/// Autopilot: a Survival run decided for you. Its end screen goes back Home,
/// where the next run waits on Play's button; the close button stops it early.
struct AutopilotView: View {
  let tree: OpeningTree
  let index: ReferenceIndex
  /// Analysis on a line grown here, seen from a side, opened over the mode.
  let onAnalyze: ([String], ChessCore.Color) -> Void
  let onExit: () -> Void

  @Environment(AppStore.self) private var store
  @State private var model: RunModel?
  @State private var nothing = false
  @State private var analyzing = false
  private static let engine = BasicEngine()

  var body: some View {
    Group {
      if analyzing, let model {
        AnalysisTab(tree: tree, index: index, line: model.run.played, orientation: model.run.color) { analyzing = false }
      } else if let model {
        if model.phase == .over, let finish = model.finish {
          EndView(model: model, finish: finish, onNext: home, onAnalyze: { analyzing = true }, onExit: home)
        } else {
          RunView(model: model, onExit: exit)
        }
      } else if nothing {
        VStack(spacing: 12) {
          Text("Nothing to practice yet").font(.headline).foregroundStyle(Theme.text)
          Text("Your Playbook has no lines in this selection.").foregroundStyle(Theme.text2)
          Button("Back", action: onExit).buttonStyle(PlayButtonStyle(kind: .primary, height: 56, radius: 16, font: 17, block: true))
        }
      } else {
        ProgressView().tint(Theme.text2)
      }
    }
    .task { if model == nil && !nothing { begin() } }
  }

  /// The next round, picked when it starts: what the last one changed is in the store by then.
  /// An empty Playbook starts a first game as White, adding moves from move 1.
  private func begin() {
    if store.state.repertoires.values.allSatisfy({ $0.nodes.isEmpty }) {
      guard let run = RunModel(firstGame: store, tree: tree, index: index, engine: Self.engine) else {
        nothing = true
        return
      }
      model = run
      run.start()
      return
    }
    let selection = store.takeRoundSelection()
    guard let round = nextRound(store.state, tree, selection, store.autoHistory),
      let run = RunModel(round: round, selection: selection, store: store, tree: tree, index: index, engine: Self.engine)
    else {
      nothing = true
      return
    }
    model = run
    run.start()
  }

  /// Home after a finished round, its start counted for the next one.
  private func home() {
    if let model, let round = model.round { store.autoHistory = afterRound(store.autoHistory, round, model.selection) }
    exit()
  }

  private func exit() {
    model?.stop()
    onExit()
  }
}
