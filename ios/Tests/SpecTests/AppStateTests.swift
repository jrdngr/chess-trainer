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
  let selection = roundSelection(state, tree, last: nil)
  let round = try #require(nextRound(state, tree, selection, AutoHistory()))
  // The first run of an opening is always a position start.
  #expect(round.at == nil)
  let begun = startSurvival(survivalOptions(round, state, tree, selection, seed: 1))
  #expect(begun != nil)

  let data = try JSONEncoder().encode(state)
  #expect(try JSONDecoder().decode(AppState.self, from: data) == state)
}

/// Freeform starts from move one even when all your prep sits deep inside one opening.
@Test func freeformStartsFromMoveOne() throws {
  let tree = openingTree(bookIndex)
  var state = AppState()
  state.settings.start = .freeform
  let id = state.ensureRepertoire(.b)
  state.addLine(id, line("e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Be3 e5"), .fixed(.book))
  // Recent Tests brake the Playbook-wide Test, so a Review narrowed into the Najdorf wins.
  var history = AutoHistory()
  history.focuses = [.test, .test, .test]
  let round = try #require(nextRound(state, tree, Selection(color: .b, opening: ANY_OPENING), history))
  #expect(startsInside(round.pick.opening))
  #expect(round.pick.start == .first)
  #expect(round.at == nil)
}

/// Drill on the whole Playbook starts like a picked opening: the same deep prep is not played from move one.
@Test func drillOnWholePlaybookStartsInside() throws {
  let tree = openingTree(bookIndex)
  var state = AppState()
  let id = state.ensureRepertoire(.b)
  state.addLine(id, line("e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Be3 e5"), .fixed(.book))
  var history = AutoHistory()
  history.focuses = [.test, .test, .test]
  let round = try #require(nextRound(state, tree, Selection(color: .b, opening: ANY_OPENING), history))
  #expect(round.pick.start != .first)
}

/// A save from before the start setting opens on Drill.
@Test func oldSaveStartsOnDrill() throws {
  let data = Data(#"{"selection":{"color":"w","opening":""}}"#.utf8)
  let settings = try JSONDecoder().decode(Settings.self, from: data)
  #expect(settings.start == .drill)
}
