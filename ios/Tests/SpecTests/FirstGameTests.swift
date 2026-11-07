import ChessCore
import Model
import Testing

/// Tips show in order, each once; a moment passed by drops the tips before it.
@Test func tipsShowInOrderAndSkipPassedOnes() throws {
  let all = FirstGameTip.allCases
  let first = try #require(tipAt(all, .adding(ply: 0)))
  #expect(first.tip == .firstMove)
  #expect(tipAt(first.rest, .adding(ply: 0)) == nil)
  let reply = try #require(tipAt(first.rest, .adding(ply: 2)))
  #expect(reply.tip == .reply)
  // A game that never stays in the book goes from the line straight out of it.
  let out = try #require(tipAt(reply.rest, .outOfBook))
  #expect(out.tip == .outOfBook)
  #expect(out.rest == [.lens, .end])
  #expect(tipAt(out.rest, .book) == nil)
  #expect(tipAt([], .end) == nil)
}

/// The first game starts at move one as White with nothing saved, at the
/// gap of White's first move.
@Test func firstGameStartsAtMoveOne() throws {
  let tree = openingTree(bookIndex)
  var state = AppState()
  let id = state.ensureRepertoire(.w)
  let round = firstGameRound(tree)
  let selection = Selection(color: .w, opening: ANY_OPENING)
  let begun = try #require(startSurvival(survivalOptions(round, state, tree, selection, seed: 1)))
  #expect(begun.state.run.color == .w)
  #expect(begun.state.run.played.isEmpty)
  let gap = firstMoveGap(state.repertoires[id]!, bookIndex)
  #expect(gap.line.isEmpty)
  #expect(gap.repertoireId == id)
  #expect(!fillEnds(bookIndex, line("e4"), added: 1, size: 3))
}

/// The first game answers 1.e4 with e5 and 1.d4 with d5, where the book's
/// most played reply is something else; other moves are left to the book.
@Test func firstGameMeetsE4AndD4Symmetrically() {
  #expect(firstGameReply(line("e4")) == "e5")
  #expect(firstGameReply(line("d4")) == "d5")
  #expect(popularReplies(bookIndex, walkSan(line("e4")).fens.last!, GAP_SHARE).first?.san != "e5")
  #expect(firstGameReply(line("c4")) == nil)
  #expect(firstGameReply(line("e4 e5 Nf3")) == nil)
}
