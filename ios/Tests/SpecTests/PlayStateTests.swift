import ChessCore
import Foundation
import Model
import Testing

/// Play's settings in the saved state: an old save still loads, and a save round-trips.
@Test func playStateLoadsAndKeepsGames() throws {
  let old = try JSONDecoder().decode(AppState.self, from: Data(#"{"settings":{"onboarded":true}}"#.utf8))
  #expect(old.settings.play == DEFAULT_PLAY)
  // A profile from before the intro pages still gets them once.
  #expect(!old.settings.seenIntro)
  let partial = try JSONDecoder().decode(AppState.self, from: Data(#"{"settings":{"play":{"level":"strong"}}}"#.utf8))
  #expect(partial.settings.play.level == "strong")
  #expect(partial.settings.play.takeBacks == DEFAULT_PLAY.takeBacks)

  var state = AppState()
  state.settings.play.level = "strong"
  let data = try JSONEncoder().encode(state)
  #expect(try JSONDecoder().decode(AppState.self, from: data) == state)
}
