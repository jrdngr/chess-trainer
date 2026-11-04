import Book
import ChessCore
import Model
import SwiftUI

/// Play: a game against the engine on your saved settings (the setup first
/// when `straight` is off). The game's settings button opens the setup over it.
struct PlayView: View {
  @Environment(AppStore.self) private var store
  let tree: OpeningTree
  let index: ReferenceIndex
  let onExit: () -> Void
  /// Start a game at once, without the setup screen.
  var straight = false
  @State private var game: PlayGame?
  @State private var settings = false
  /// Whether the first game has been started: until then a straight start shows nothing.
  @State private var opened = false

  var body: some View {
    Group {
      if let game {
        PlayGameView(game: game, tree: tree, onNew: { self.game = nil }, onClose: onExit).id(game.gameId)
          .environment(\.openModeSettings) { settings = true }
      } else if straight && !opened {
        Theme.background.ignoresSafeArea()
      } else {
        PlaySetupView(onStart: start, onExit: onExit)
      }
    }
    .sheet(isPresented: $settings) {
      PlaySetupView(onStart: { prefs in
        settings = false
        start(prefs)
      }, onExit: { settings = false }, startLabel: "Restart")
      .presentationBackground(Theme.background)
    }
    .task {
      debugOpen()
      if straight && !opened && game == nil { start(store.state.settings.play) }
      opened = true
    }
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
