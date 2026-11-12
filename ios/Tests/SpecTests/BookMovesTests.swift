import ChessCore
import Foundation
import Model
import Testing

/// A line is book for as long as the book has each move, for either side.
@Test func bookLengthStopsAtTheFirstMoveTheBookLacks() {
  #expect(bookLength(bookIndex, line("e4 e5 Nf3 Nc6 Bc4")) == 5)
  #expect(bookLength(bookIndex, line("e4 g5 d4 h6")) == 1)
  #expect(bookLength(bookIndex, []) == 0)
}

/// Migrating an old save keeps the book moves and removes every move the book
/// lacks, yours or theirs, with everything under it and its cards.
@Test func migrationRemovesNonBookMoves() throws {
  var state = AppState()
  let id = state.ensureRepertoire(.w)
  state.addLine(id, line("e4 e5 Nf3 Nc6 Bc4"), .fixed(.book))
  state.addLine(id, line("e4 g5 d4 h6 Nc3"), .fixed(.board))
  let deep = walkSan(line("e4 g5 d4 h6")).fens[2]
  state.answered(id, deep, "d4", .good)
  #expect(!state.cards.isEmpty)
  state.version = 0

  let changed = state.migrate(bookIndex)
  #expect(changed)
  let rep = try #require(state.repertoires[id])
  #expect(nodeAtLine(rep, line("e4 e5 Nf3 Nc6 Bc4")) != nil)
  #expect(nodeAtLine(rep, line("e4 g5")) == nil)
  #expect(state.cards.isEmpty)
  #expect(rep.nodes.values.allSatisfy { inBook(bookIndex, $0.fenBefore, $0.san) })
  #expect(state.version == SAVE_VERSION)
  let again = state.migrate(bookIndex)
  #expect(!again)
}

/// A new save starts at the current version; a save from before versions starts at 0.
@Test func saveVersionDefaults() throws {
  #expect(AppState().version == SAVE_VERSION)
  let old = try JSONDecoder().decode(AppState.self, from: Data("{}".utf8))
  #expect(old.version == 0)
}
