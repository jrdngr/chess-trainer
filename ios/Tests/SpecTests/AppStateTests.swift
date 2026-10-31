import ChessCore
import Foundation
import Model
import Testing

/// A first Playbook from a starter set gives Autopilot a round to play, and the state saves and loads.
@Test func starterSetToFirstRound() throws {
  let tree = openingTree(bookIndex)
  var state = AppState()
  state.seed(tree, STARTER_SETS[0])
  #expect(state.repertoireList.count == 2)
  #expect(state.settings.selection.opening == ANY_FAVORITE)
  let rand = mulberry32(1)
  let selection = roundSelection(state, tree, last: nil, rand)
  let round = try #require(nextRound(state, tree, selection, AutoHistory()))
  // The first run of an opening is always a position start.
  #expect(round.at == nil)
  let begun = startSurvival(survivalOptions(round, state, tree, selection, seed: 1))
  #expect(begun != nil)

  let data = try JSONEncoder().encode(state)
  #expect(try JSONDecoder().decode(AppState.self, from: data) == state)
}
