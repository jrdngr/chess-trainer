import ChessCore
import Model
import Testing
@testable import Engine

struct BookScoresTests {
  /// After 1.d4 Nf6 2.Bf4 c5 3.Nc3 d5, 4.h4 drops a pawn to ...cxd4 and Qb6. Our own
  /// search scores it under the blunder line; Stockfish's table catches it.
  static let fen = "rnbqkb1r/pp2pppp/5n2/2pp4/3P1B2/2N5/PPP1PPPP/R2QKBNR w KQkq - 0 1"

  @Test func bookPositionMovesAreJudgedByStockfish() async {
    let engine = BasicEngine()
    let base = await baseline(engine, Self.fen, moments: false)!
    let blunder = await judge(engine, base, san: "h4", uci: "h2h4", color: .w, moments: false)
    #expect(!blunder.ok)
    #expect(blunder.lost > 200)
    let sound = await judge(engine, base, san: "e3", uci: "e2e3", color: .w, moments: false)
    #expect(sound.ok)
    #expect(sound.lost == 0)
  }

  @Test func positionsOutsideTheBookHaveNoScore() {
    #expect(BookScores.score("8/8/4k3/8/8/4K3/4P3/8 w - - 0 1", "e2e4") == nil)
    #expect(BookScores.score(Self.fen, "h2h4")?.lost ?? 0 > 200)
  }
}
