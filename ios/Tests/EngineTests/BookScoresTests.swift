import ChessCore
import Model
import Testing
@testable import Engine

struct BookScoresTests {
  /// After 1.d4 Nf6 2.Bf4 c5 3.Nc3 d5, 4.h4 costs 2.6 by Stockfish's table.
  /// Book positions are scored by Stockfish's table, not a search.
  static let fen = "rnbqkb1r/pp2pppp/5n2/2pp4/3P1B2/2N5/PPP1PPPP/R2QKBNR w KQkq - 0 1"

  /// The table sets what a book move costs; the engine's line still has to show why for it to be a
  /// blunder, and after 4.h4 cxd4 Qxd4 the pawn is back. The engine is scripted, so its line is always that one.
  @Test func bookPositionMovesAreJudgedByStockfish() async {
    let engine = TableEngine(
      scores: ["e2e3": 30, "h2h4": -40],
      lines: ["e2e3": ["e2e3", "b8c6"], "h2h4": ["h2h4", "c5d4", "d1d4", "b8c6", "d4d2", "e7e6"]])
    let base = Baseline(fen: Self.fen, cp: 30, best: "e3", bestUci: "e2e3", second: nil)
    let costly = await judge(engine, base, san: "h4", uci: "h2h4", color: .w, moments: false)
    #expect(costly.lost > 200, "the table's cost, not the engine's 70")
    #expect(costly.ok, "its line loses no material")
    let sound = await judge(engine, base, san: "e3", uci: "e2e3", color: .w, moments: false)
    #expect(sound.ok)
    #expect(sound.lost == 0)
  }

  @Test func positionsOutsideTheBookHaveNoScore() {
    #expect(BookScores.score("8/8/4k3/8/8/4K3/4P3/8 w - - 0 1", "e2e4") == nil)
    #expect(BookScores.score(Self.fen, "h2h4")?.lost ?? 0 > 200)
  }
}
