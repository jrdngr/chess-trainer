import Book
import ChessCore
import Engine
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
  @State private var model: RunModel?
  @State private var nothing = false
  @State private var analyzing = false
  /// The round drawn from the deck, ready to take over once its card is on the board.
  @State private var upcoming: RunModel?
  /// The finished round's start is already counted for the next one.
  @State private var counted = false
  private static let engines = EngineSlot()
  private var engine: ChessEngine { Self.engines() }

  var body: some View {
    Group {
      if analyzing, let model {
        AnalysisTab(tree: tree, index: index, line: model.run.played, orientation: model.run.color) { analyzing = false }
      } else if let model {
        if model.phase == .over, let finish = model.finish, !model.advancing, !deals(model), model.tutorialGame == nil {
          EndView(model: model, finish: finish, onNext: home, onAnalyze: { analyzing = true }, onExit: home)
        } else {
          runView(model)
            // A fresh screen for each round: nothing carries over from the last.
            .id(ObjectIdentifier(model))
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

  /// The round on its board. Finished, its X goes Home; a Play round deals the next from its deck.
  private func runView(_ model: RunModel) -> RunView {
    var drawer: (() -> RoundCard?)? = nil
    if deals(model) { drawer = { draw() } }
    return RunView(
      model: model, onExit: { leave(model) }, onAnalyze: { analyzing = true }, onNextRun: { next() },
      onDraw: drawer, onDealt: { dealt() })
  }

  private func leave(_ model: RunModel) {
    if model.finish != nil { home() } else { exit() }
  }

  /// The next round, picked when it starts: what the last one changed is in the store by then.
  private func begin() {
    guard let run = make() else {
      nothing = true
      return
    }
    model = run
    run.start()
  }

  /// The next round's run, not yet started.
  /// The tutorial plays its games in order. An empty Playbook starts a first game as White, adding moves from move 1.
  private func make() -> RunModel? {
    // The tutorial's next game, whatever is selected.
    if let game = store.state.settings.tutorial?.next {
      return RunModel(tutorial: game, store: store, tree: tree, index: index, engine: engine)
    }
    if store.state.playbooks.values.allSatisfy({ $0.nodes.isEmpty }) {
      return RunModel(firstGame: store, tree: tree, index: index, engine: engine)
    }
    let selection = store.takeRoundSelection()
    guard let round = nextRound(store.state, tree, selection, store.autoHistory) else { return nil }
    return RunModel(round: round, selection: selection, store: store, tree: tree, index: index, engine: engine)
  }

  /// A finished Play round stays on its board and deals the next from the deck. The tutorial's games don't.
  private func deals(_ model: RunModel) -> Bool { model.round != nil && model.tutorialGame == nil }

  /// The deck was touched: the next round, picked now, its card to deal. Nil when there is none.
  private func draw() -> RoundCard? {
    if upcoming == nil {
      count()
      upcoming = make()
    }
    return upcoming?.card
  }

  /// The drawn card is on the board: its round takes over, straight onto the board.
  private func dealt() {
    guard let run = upcoming else { return next() }
    model?.stop()
    upcoming = nil
    counted = false
    run.start(dealt: true)
    model = run
  }

  /// The finished round's start counted for the next one, once.
  private func count() {
    guard !counted, let model, let round = model.round else { return }
    store.autoHistory = afterRound(store.autoHistory, round, model.selection)
    counted = true
  }

  /// Home after a finished round, its start counted for the next one.
  private func home() {
    count()
    exit()
  }

  /// Next run: straight on to the next round, its start counted like a finished one's.
  private func next() {
    count()
    model?.stop()
    model = nil
    upcoming = nil
    counted = false
    begin()
  }

  private func exit() {
    model?.stop()
    onExit()
  }
}
