import Book
import ChessCore
import Model
import SwiftUI

/// Play: the setup, then a game against the engine.
struct PlayView: View {
  @Environment(AppStore.self) private var store
  let tree: OpeningTree
  let index: ReferenceIndex
  let onExit: () -> Void
  @State private var game: PlayGame?

  var body: some View {
    Group {
      if let game {
        PlayGameView(game: game, tree: tree, onNew: { self.game = nil }, onClose: onExit).id(game.gameId)
      } else {
        PlaySetupView(onStart: start, onExit: onExit)
      }
    }
    .task { debugOpen() }
  }

  private func start(_ prefs: PlayPrefs) {
    game = PlayGame(prefs: prefs, selection: store.takeRoundSelection(), store: store, tree: tree)
  }

  /// Debug builds open a game with `PLAY_SCREEN=game` (or `over`, resigned),
  /// playing `PLAY_MOVES=n` moves of yours first, for screenshots.
  private func debugOpen() {
    #if DEBUG
      let env = ProcessInfo.processInfo.environment
      guard game == nil, let screen = env["PLAY_SCREEN"], screen != "setup" else { return }
      start(store.state.settings.play)
      guard let game else { return }
      let moves = Int(env["PLAY_MOVES"] ?? "") ?? 0
      Task {
        var played = 0
        while played < moves {
          try? await Task.sleep(for: .milliseconds(200))
          guard game.myTurn, !game.held, !game.thinking else { continue }
          if let move = legalMoves(game.fen).first(where: { $0.piece != .p || played % 2 == 0 }) ?? legalMoves(game.fen).first {
            game.play(move)
            played += 1
          }
        }
        while game.thinking || !game.myTurn { try? await Task.sleep(for: .milliseconds(200)) }
        if screen == "over" { game.resign() }
      }
    #endif
  }
}
