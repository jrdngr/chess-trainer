import ChessCore
import Model
import Testing

/// Endgame rules: a move is judged by the result it keeps once little material is left.

private let START = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
/// Lucena: rook and pawn against rook.
private let LUCENA = "3K4/3P1k2/8/8/8/8/2r5/4R3 w - - 0 1"
/// Two rooks each: the heaviest rook ending that still counts.
private let ROOKS = "r1r3k1/5ppp/8/8/8/8/5PPP/R1R3K1 w - - 0 1"

@Test func phaseCountsMinorsRooksAndQueens() {
  #expect(gamePhase(START) == 24)
  #expect(gamePhase(LUCENA) == 4)
  #expect(gamePhase("4k3/8/8/8/8/8/8/Q3K2q w - - 0 1") == 8)
}

@Test func endgameStartsAtPhaseEight() {
  #expect(isEndgame(LUCENA))
  #expect(isEndgame("r1r3k1/5ppp/8/8/8/8/5PPP/R1R3K1 w - - 0 1"))
  // One knight more and it is still a middlegame.
  #expect(!isEndgame("r1r3k1/5ppp/8/8/8/8/5PPP/RNR3K1 w - - 0 1"))
  #expect(!isEndgame(START))
}

@Test func resultFollowsTheWinLine() {
  #expect(resultOf(.w, RESULT_WIN_CP) == .win)
  #expect(resultOf(.w, RESULT_WIN_CP - 1) == .draw)
  #expect(resultOf(.b, RESULT_WIN_CP) == .loss)
  #expect(resultOf(.b, -10_000) == .win)
}

@Test func missedMateInAWonEndingKeepsTheRun() {
  // The engine had mate; your move keeps a clear win. It costs a little, never the run.
  let verdict = judgeEndgame(.w, 10_000, 500)
  #expect(verdict.ok)
  #expect(verdict.lost == ENDGAME_SCORE_CAP - 500)
  // The same move from Black's side.
  #expect(judgeEndgame(.b, -10_000, -500).ok)
}

@Test func aWinGivenAwayEndsTheRun() {
  #expect(!judgeEndgame(.w, 450, 50).ok)
  // A draw given away as a loss.
  #expect(!judgeEndgame(.b, 0, 400).ok)
}

@Test func aScoreWobblingAcrossTheWinLineIsNotASlip() {
  #expect(judgeEndgame(.w, RESULT_WIN_CP + 10, RESULT_WIN_CP - 10).ok)
}

@Test func anExactResultStandsOverTheScore() {
  // A tablebase says the win is gone, however small the score's drop.
  #expect(!judgeEndgame(.w, 320, 300, exact: (before: .win, after: .draw)).ok)
  // And a draw it says is held is held, whatever the score did.
  #expect(judgeEndgame(.w, 200, -250, exact: (before: .draw, after: .draw)).ok)
}

@Test func judgeMoveSwitchesRulesInTheEndgame() {
  // A full point dropped in a level position: a blunder in the middlegame, a held draw in an ending.
  #expect(!judgeMove(START, .w, 0, -100).ok)
  #expect(judgeMove(LUCENA, .w, 0, -100).ok)
  #expect(judgeMove(ROOKS, .w, 0, -100).ok)
}

@Test func slipTextNamesTheResultGivenAway() {
  #expect(slipText(.win, .draw) == "Win slipped to a draw")
  #expect(slipText(.draw, .loss) == "Draw slipped to a loss")
  #expect(slipText(.draw, .draw) == nil)
  #expect(slipText(.draw, .win) == nil)
}

@Test func aGivenAwayEndingIsKeptFromThePositionBeforeTheMove() throws {
  // Black to move, deep into the fifty-move count, gave a won rook ending away.
  let fen = "8/8/8/4k3/8/8/2r5/4K3 b - - 87 120"
  let slip = Ending.blunder(played: "Kd4", best: "Ke4", lost: 500, reply: nil, slip: ResultSlip(from: .win, to: .draw))
  let kept = try #require(endgameGivenAway(slip, fen: fen, name: "Sicilian", at: 5))
  // Still Black to move, the fifty-move count started afresh, so the win is there to be played for.
  #expect(kept.fen == "8/8/8/4k3/8/8/2r5/4K3 b - - 0 120")
  #expect(kept.goal == .win)
  // A draw given away as a loss is kept to be held.
  let held = Ending.blunder(played: "Kd4", best: "Ke4", lost: 300, reply: nil, slip: ResultSlip(from: .draw, to: .loss))
  #expect(endgameGivenAway(held, fen: fen, name: "Sicilian", at: 5)?.goal == .hold)
  // A middlegame blunder, or a run that ended on the board, keeps nothing.
  #expect(endgameGivenAway(.blunder(played: "Kd4", best: nil, lost: 500, reply: nil, slip: nil), fen: fen, name: "", at: 5) == nil)
  #expect(endgameGivenAway(.draw, fen: fen, name: "", at: 5) == nil)
}
