import Book
import ChessCore
import Engine
import Game
import Model
import SwiftUI

/// Play: a Run run decided for you. A finished round stays on its board with
/// the deck under it, and the next round is drawn from the deck; the close button leaves.
/// A tutorial game also stays on its board when it ends, with no deck: its X goes back Home.
struct PlayView: View {
  let tree: OpeningTree
  let index: ReferenceIndex
  /// Analysis on a line grown here, seen from a side, opened over the mode.
  let onAnalyze: ([String], ChessCore.Color) -> Void
  let onExit: () -> Void

  @Environment(AppStore.self) private var store
  @State private var session: PlaySession?
  @State private var analyzing = false

  var body: some View {
    Group {
      if let session {
        content(session)
      } else {
        ProgressView().tint(Theme.text2)
      }
    }
    .task {
      if session == nil {
        let made = PlaySession(store: store, tree: tree, index: index)
        session = made
        made.open()
      }
    }
  }

  @ViewBuilder private func content(_ session: PlaySession) -> some View {
    if analyzing, let model = session.model {
      AnalysisTab(tree: tree, index: index, line: model.run.played, orientation: model.run.color) { analyzing = false }
    } else if let model = session.model {
      if model.phase == .over, let finish = model.finish, !model.advancing, !session.deals(model), model.tutorialGame == nil {
        EndView(model: model, finish: finish, onNext: home, onAnalyze: { analyzing = true }, onExit: home)
      } else {
        runView(session, model)
          // A fresh screen for each round: nothing carries over from the last.
          .id(ObjectIdentifier(model))
      }
    } else if session.nothing {
      VStack(spacing: 12) {
        Text("Nothing to practice yet").font(.headline).foregroundStyle(Theme.text)
        Text("Your Playbook has no lines in this selection.").foregroundStyle(Theme.text2)
        Button("Back", action: onExit).buttonStyle(PlayButtonStyle(kind: .primary, height: 56, radius: 16, font: 17, block: true))
      }
    } else {
      ProgressView().tint(Theme.text2)
    }
  }

  /// The round on its board. Finished, its X goes Home; a Play round deals the next from its deck.
  private func runView(_ session: PlaySession, _ model: RunModel) -> RunView {
    var drawer: (() -> RoundCard?)? = nil
    if session.deals(model) { drawer = { session.draw()?.card } }
    return RunView(
      model: model, onExit: { leave(session) }, onAnalyze: { analyzing = true }, onNextRun: { session.next() },
      onDraw: drawer, onDealt: { session.dealt() })
  }

  private func leave(_ session: PlaySession) {
    session.leave()
    onExit()
  }

  /// Home after a finished round, its start counted for the next one.
  private func home() {
    session?.home()
    onExit()
  }
}
