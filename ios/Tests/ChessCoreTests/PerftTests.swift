import Testing
@testable import ChessCore

/// Move generation counted against the standard perft table.
struct PerftTests {
  func perft(_ board: Board, _ depth: Int) -> Int {
    if depth == 0 { return 1 }
    let moves = board.moves()
    if depth == 1 { return moves.count }
    return moves.reduce(0) { $0 + perft(board.made($1), depth - 1) }
  }

  @Test(arguments: [
    (START_FEN, [20, 400, 8902, 197_281]),
    ("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1", [48, 2039, 97_862]),
    ("8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1", [14, 191, 2812, 43_238]),
    ("r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1", [6, 264, 9467]),
    ("rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8", [44, 1486, 62_379]),
  ])
  func counts(fen: String, expected: [Int]) throws {
    let board = try #require(Board(fen: fen))
    for (i, count) in expected.enumerated() {
      #expect(perft(board, i + 1) == count, "depth \(i + 1)")
    }
  }

  @Test func sanAndFen() throws {
    let e4 = try #require(applySan(START_FEN, "e4"))
    #expect(e4.after == "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1")
    #expect(e4.uci == "e2e4")
    let line = walkSan("e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6".split(separator: " ").map(String.init))
    #expect(line.moves.count == 10)
    #expect(applySan(START_FEN, "e5") == nil)
    #expect(applySan(START_FEN, "Ng1f3")?.san == "Nf3")
    #expect(applySan(START_FEN, "e2e4")?.san == "e4")
    // The en passant square is written only when a capture can use it.
    let ep = walkSan(["e4", "c5", "e5", "d5"]).fens.last!
    #expect(ep.contains(" d6 "))
    #expect(!walkSan(["e4", "c5"]).fens.last!.contains(" c6 "))
  }

  @Test func sanMarks() {
    let mate = walkSan(["f3", "e5", "g4", "Qh4#"])
    #expect(mate.moves.last?.san == "Qh4#")
    #expect(positionStatus(mate.fens.last!).checkmate)
    #expect(legalSans("7k/P7/8/8/8/8/8/K7 w - - 0 1").prefix(4) == ["a8=N", "a8=B", "a8=R+", "a8=Q+"])
  }
}
