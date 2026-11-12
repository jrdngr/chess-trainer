import ChessCore
import Foundation
import Model
import Testing

/// A first Playbook from a starter set gives Play a round to play, and the state saves and loads.
@Test func starterSetToFirstRound() throws {
  let tree = openingTree(bookIndex)
  var state = AppState()
  state.seed(tree, STARTER_SETS[0])
  #expect(state.playbookList.count == 2)
  #expect(state.settings.selection.opening == ANY_OPENING)
  let selection = state.settings.selection
  let round = try #require(nextRound(state, tree, selection, AutoHistory()))
  // Drill starts at one of your moves, never from move one.
  #expect(round.at?.isEmpty == false)
  let begun = startRun(runOptions(round, state, tree, selection, seed: 1))
  #expect(begun != nil)

  let data = try JSONEncoder().encode(state)
  #expect(try JSONDecoder().decode(AppState.self, from: data) == state)
}

/// Freeform starts from move one even when all your prep sits deep inside one opening.
@Test func freeformStartsFromMoveOne() throws {
  let tree = openingTree(bookIndex)
  var state = AppState()
  state.settings.start = .freeform
  let id = state.ensurePlaybook(.b)
  state.addLine(id, line("e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Be3 e5"), .fixed(.book))
  state.addLine(id, line("d4 d5"), .fixed(.book))
  // Recent Tests brake the Playbook-wide Test, so a Review narrowed into the Najdorf wins.
  var history = AutoHistory()
  history.focuses = [.test, .test, .test]
  let round = try #require(nextRound(state, tree, Selection(color: .b, opening: ANY_OPENING), history))
  #expect(round.free)
  #expect(round.pick.opening.id == ANY_OPENING)
  #expect(round.at == nil)
  #expect(round.aim == nil)
}

/// Drill on the whole Playbook starts like a picked opening: the same deep prep is not played from move one.
@Test func drillOnWholePlaybookStartsInside() throws {
  let tree = openingTree(bookIndex)
  var state = AppState()
  let id = state.ensurePlaybook(.b)
  state.addLine(id, line("e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Be3 e5"), .fixed(.book))
  state.addLine(id, line("d4 d5"), .fixed(.book))
  var history = AutoHistory()
  history.focuses = [.test, .test, .test]
  let round = try #require(nextRound(state, tree, Selection(color: .b, opening: ANY_OPENING), history))
  #expect(round.at?.isEmpty == false)
}

/// A save from before the start setting opens on Drill.
@Test func oldSaveStartsOnDrill() throws {
  let data = Data(#"{"selection":{"color":"w","opening":""}}"#.utf8)
  let settings = try JSONDecoder().decode(Settings.self, from: data)
  #expect(settings.start == .drill)
}

/// A save that called Either "random" still opens on Either.
@Test func randomSideReadsAsEither() throws {
  let data = Data(#"{"color":"random","opening":""}"#.utf8)
  #expect(try JSONDecoder().decode(Selection.self, from: data).color == .either)
}

/// Freeform plays the picked side even with nothing to recommend there; only Either takes the recommendation's side.
@Test func freeformPlaysThePickedSide() throws {
  let tree = openingTree(bookIndex)
  var state = AppState()
  state.settings.start = .freeform
  state.addLine(state.ensurePlaybook(.b), line("e4 c5 d4 cxd4"), .fixed(.book))
  state.addLine(state.ensurePlaybook(.b), line("d4 d5"), .fixed(.book))
  let white = try #require(nextRound(state, tree, Selection(color: .w, opening: ANY_OPENING), AutoHistory()))
  #expect(white.free && white.pick.color == .w)
  let either = try #require(nextRound(state, tree, Selection(color: .either, opening: ANY_OPENING), AutoHistory()))
  #expect(either.pick.color == .b)
}
