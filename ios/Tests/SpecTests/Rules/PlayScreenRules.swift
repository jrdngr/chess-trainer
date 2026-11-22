import ChessCore
import Model
import Testing

@Suite("docs/rules/play-screen.md") struct PlayScreenRules {
  /// Rule 3: the header puts the opening's family on a line over a deeper name, and nothing over a name that is its own family.
  @Test func headerShowsFamilyOverDeeperName() {
    #expect(familyAbove(bookIndex, "Sicilian Defense: Najdorf Variation") == "Sicilian Defense")
    #expect(familyAbove(bookIndex, "Queen's Gambit Declined: Exchange Variation") == "Queen's Gambit Declined")
    #expect(familyAbove(bookIndex, "Sicilian Defense") == nil)
    #expect(familyAbove(bookIndex, "Freeform") == nil)
  }

  /// Rule 9: a pawn reaching the last rank offers queen, knight, rook and bishop, in that order, and only the ones allowed.
  @Test func promotionOffersEachPieceQueenFirst() {
    let fen = "1r6/4P2k/6p1/p6p/8/6P1/5P1P/4R1K1 w - - 0 1"
    #expect(promotionChoices(legalMoves(fen), from: "e7", to: "e8").map(\.san) == ["e8=Q", "e8=N", "e8=R", "e8=B"])
    let allowed = legalMoves(fen).filter { ["e8=N", "e8=Q+", "e8=Q"].contains($0.san) }
    #expect(promotionChoices(allowed, from: "e7", to: "e8").map(\.promotion) == [.q, .n])
    #expect(promotionChoices(legalMoves(fen), from: "e1", to: "e6").isEmpty)
  }
}
