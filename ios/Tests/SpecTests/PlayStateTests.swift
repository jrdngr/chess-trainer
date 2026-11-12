import ChessCore
import Foundation
import Model
import Testing

/// An old save still loads, and a save round-trips.
@Test func oldSavesLoadAndSavesRoundTrip() throws {
  let old = try JSONDecoder().decode(AppState.self, from: Data(#"{"settings":{"onboarded":true}}"#.utf8))
  // A profile from before the intro pages still gets them once.
  #expect(!old.settings.seenIntro)

  var state = AppState()
  state.settings.boardTheme = .walnut
  let data = try JSONEncoder().encode(state)
  #expect(try JSONDecoder().decode(AppState.self, from: data) == state)
}
