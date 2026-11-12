import ChessCore
import Foundation
import Model
import Testing

@Suite("docs/rules/playbook.md") struct PlaybookRules {
  /// Rule 1: a line is book for as long as the book has each move, for either side.
  @Test func bookLengthStopsAtTheFirstMoveTheBookLacks() {
    #expect(bookLength(bookIndex, line("e4 e5 Nf3 Nc6 Bc4")) == 5)
    #expect(bookLength(bookIndex, line("e4 g5 d4 h6")) == 1)
    #expect(bookLength(bookIndex, []) == 0)
  }


  /// Rule 2: migrating an old save keeps the book moves and removes every move the book
  /// lacks, yours or theirs, with everything under it and its cards.
  @Test func migrationRemovesNonBookMoves() throws {
    var state = AppState()
    let id = state.ensurePlaybook(.w)
    state.addLine(id, line("e4 e5 Nf3 Nc6 Bc4"), .fixed(.book))
    state.addLine(id, line("e4 g5 d4 h6 Nc3"), .fixed(.board))
    let deep = walkSan(line("e4 g5 d4 h6")).fens[2]
    state.answered(id, deep, "d4", .good)
    #expect(!state.cards.isEmpty)
    state.version = 0

    let changed = state.migrate(bookIndex)
    #expect(changed)
    let rep = try #require(state.playbooks[id])
    #expect(nodeAtLine(rep, line("e4 e5 Nf3 Nc6 Bc4")) != nil)
    #expect(nodeAtLine(rep, line("e4 g5")) == nil)
    #expect(state.cards.isEmpty)
    #expect(rep.nodes.values.allSatisfy { inBook(bookIndex, $0.fenBefore, $0.san) })
    #expect(state.version == SAVE_VERSION)
    let again = state.migrate(bookIndex)
    #expect(!again)
  }

}
