import Testing
@testable import ChessCore

/// FENs that name an impossible position are refused or read safely.
struct ScrubEngineTests {
  @Test(arguments: [
    "K6P/8/8/8/8/8/8/k7 w - - 0 1",
    "K7/8/8/8/8/8/8/k6p b - - 0 1",
    "K7/8/8/8/8/8/8/k6P w - - 0 1",
  ])
  func pawnOnAnEdgeRankIsRefused(fen: String) {
    #expect(Board(fen: fen) == nil)
    #expect(legalMoves(fen).isEmpty)
  }

  @Test func castlingNeedsTheRookAtHome() {
    let sans = legalSans("4k3/8/8/8/8/8/8/4K3 w KQ - 0 1")
    #expect(!sans.contains("O-O"))
    #expect(!sans.contains("O-O-O"))
    #expect(Board(fen: "4k3/8/8/8/8/8/8/4K2R w KQ - 0 1")?.fen == "4k3/8/8/8/8/8/8/4K2R w K - 0 1")
  }

  @Test func castlingNeedsTheKingAtHome() {
    // A king in the corner with a right to castle long would step off the board.
    #expect(legalSans("k7/8/8/8/8/8/8/7K b q - 0 1").sorted() == ["Ka7", "Kb7", "Kb8"])
  }
}
