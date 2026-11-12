import ChessCore
import Foundation
import Model
import Testing

@Test func endgamesSaveWithTheState() throws {
  var state = AppState()
  state.endgames.review(ENDGAME_LIBRARY[0], success: true, mission: true)
  state.endgames.sawIntro(ENDGAME_LIBRARY[0].id)
  let data = try JSONEncoder().encode(state)
  #expect(try JSONDecoder().decode(AppState.self, from: data) == state)
  // A save from before Endgame mode starts with an empty record.
  let old = try JSONDecoder().decode(AppState.self, from: Data("{}".utf8))
  #expect(old.endgames == EndgameRecord())
}
