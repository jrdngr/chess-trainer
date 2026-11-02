import ChessCore
import Foundation
import Model
import Testing

/// Play's settings and games in the saved state: an old save still loads, and a game is kept once.
@Test func playStateLoadsAndKeepsGames() throws {
  let old = try JSONDecoder().decode(AppState.self, from: Data(#"{"settings":{"onboarded":true}}"#.utf8))
  #expect(old.settings.play == DEFAULT_PLAY)
  #expect(old.importedGames.isEmpty)
  // A profile from before the intro pages still gets them once.
  #expect(!old.settings.seenIntro)
  let partial = try JSONDecoder().decode(AppState.self, from: Data(#"{"settings":{"play":{"level":"strong"}}}"#.utf8))
  #expect(partial.settings.play.level == "strong")
  #expect(partial.settings.play.takeBacks == DEFAULT_PLAY.takeBacks)

  var state = AppState()
  let game = try #require(playedGame(id: "g1", color: .w, moves: ["e4", "e5"], result: .win, level: levelById("club"), at: 0))
  state.recordPlayGame(game)
  state.recordPlayGame(game)
  #expect(state.importedGames == [game])
  let data = try JSONEncoder().encode(state)
  #expect(try JSONDecoder().decode(AppState.self, from: data) == state)
}
