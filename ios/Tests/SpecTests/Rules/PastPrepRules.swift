import ChessCore
import Foundation
import Model
import Testing

private var ctx: RunContext { RunContext(index: bookIndex, prefs: autoRun(DEFAULT_PLAY), play: true) }

/// A Play session on a White Ruy Lopez, standing at `played`.
private func session(at played: [String] = []) throws -> RunSession {
  let tree = openingTree(bookIndex)
  let white = rep(.w, ["e4 e5 Nf3 Nc6 Bb5"])
  var s = beginSession(try #require(startRun(StartOptions(steer: .lines, tree: tree, reps: [white], node: tree.root, color: .w))))
  s.state.run.played = played
  s.state.run.fen = walkSan(played).fens[played.count]
  s.state.run.target = []
  return s
}

/// Your move, judged by the engine.
private func judged(_ san: String, lost: Double = 0, ok: Bool = true, moment: Bool = false, found: Bool = false, missedMate: Bool = false) -> Judgement {
  Judgement(san: san, ok: ok, lost: lost, best: "e4", before: 0, after: -lost, moment: moment, found: found, reply: nil, missedMate: missedMate)
}

private func has(_ effects: [Effect], _ match: (Effect) -> Bool) -> Bool { effects.contains(where: match) }

/// At the end of the Ruy Lopez prep, on White's turn with nothing prepared.
private func prepDone() throws -> RunSession {
  prepRanOut(try session(at: line("e4 e5 Nf3 Nc6 Bb5 a6")), bookIndex).session
}

private let START = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
/// Lucena: rook and pawn against rook.
private let LUCENA = "3K4/3P1k2/8/8/8/8/2r5/4R3 w - - 0 1"
/// Two rooks each: the heaviest rook ending that still counts.
private let ROOKS = "r1r3k1/5ppp/8/8/8/8/5PPP/R1R3K1 w - - 0 1"

@Suite("docs/rules/past-prep.md") struct PastPrepRules {
  /// Rule 1: a prepared move reviews its card by speed and pops its time.
  @Test func preparedMoveGradedAndTimed() throws {
    let move = try #require(legalMoves(START_FEN).first { $0.san == "e4" })
    let step = playPrepared(try session(), ctx, move, 2, 0)
    #expect(has(step.effects) { if case .answered(_, _, "e4", .easy) = $0 { true } else { false } })
    #expect(has(step.effects) { if case .pop(let pop) = $0 { pop.text == "2.0s" && pop.found } else { false } })
  }

  /// Rule 2: a miss fails the card, shows the prepared move, and the run goes on.
  @Test func missGoesOn() throws {
    let step = judgedMove(try session(), ctx, judged("d4", lost: 20), 1, 0)
    #expect(step.session.ending == nil)
    #expect(step.session.state.misses.count == 1 && step.session.prepStatus == .off)
    #expect(has(step.effects) { if case .missed(_, _, "d4", "e4") = $0 { true } else { false } })
    #expect(has(step.effects) { if case .miss(let flash) = $0 { flash.expected == "e4" } else { false } })
  }

  /// Rule 3: the blunder line, and a blunder ends the run.
  @Test func blunderEndsTheRun() throws {
    #expect(blunderLimit(.w, 0) == 70)
    #expect(blunderLimit(.w, 300) == 120)
    #expect(blunderLimit(.b, -300) == 120)
    #expect(blunderLimit(.b, 300) == 70)
    #expect(judgeByEval(.w, 0, -70).ok && !judgeByEval(.w, 0, -71).ok)
    let step = judgedMove(try prepDone(), ctx, judged("h3", lost: 200, ok: false), 1, 0)
    guard case .blunder(played: "h3", _, _, _, _) = step.session.ending else { Issue.record("no blunder"); return }
  }

  /// Rule 3: a costly move is a blunder only when the engine's line shows why. After 1.e4 d5,
  /// 2.Qg4 drops the queen to Bxg4, so its line runs to that capture; a line that wins the pawn
  /// back, or one the best line is just as far down in, shows nothing; a mate soon is a reason.
  @Test func aBlunderNeedsAReasonTheLineShows() throws {
    let fen = try #require(walkSan(line("e4 d5")).fens.last)
    let best = ["e4d5", "d8d5", "b1c3", "d5a5"]
    let dropsQueen = ["d1g4", "c8g4", "f1e2", "g4e2", "g1e2"]
    #expect(punishment(fen, .w, yours: dropsQueen, best: best, mated: nil) == ["c8g4"])
    #expect(punishment(fen, .w, yours: best, best: best, mated: nil) == nil, "the pawn traded back costs nothing")
    #expect(punishment(fen, .w, yours: dropsQueen, best: dropsQueen, mated: nil) == nil, "the best line loses as much")
    let quiet = ["a2a3", "e7e5", "b2b3", "b8c6"]
    #expect(punishment(fen, .w, yours: quiet, best: best, mated: 4) == ["e7e5", "b2b3", "b8c6"], "a mate within 4 moves")
    #expect(punishment(fen, .w, yours: quiet, best: best, mated: 5) == nil, "a mate further off is no reason")
  }

  /// Rule 3: material is counted against the best line, with each trade finished. After 1.e4 d5 2.exd5, not taking
  /// back leaves Black a pawn behind Qxd5, though the board is no worse than now; after 1.e4 d5, a line cut off
  /// before White takes back on e4 counts that trade finished.
  @Test func materialIsCountedAgainstTheBestLineWithTradesFinished() throws {
    let taken = try #require(walkSan(line("e4 d5 exd5")).fens.last)
    let quiet = ["a7a6", "c2c4", "b8d7", "b1c3", "g8f6", "g1f3"]
    let retake = ["d8d5", "b1c3", "d5a5", "g1f3", "g8f6"]
    #expect(punishment(taken, .b, yours: quiet, best: retake, mated: nil) == ["c2c4"], "the pawn not taken back")
    let fen = try #require(walkSan(line("e4 d5")).fens.last)
    let best = ["e4d5", "d8d5", "b1c3", "d5a5"]
    #expect(punishment(fen, .w, yours: ["b1c3", "d5e4"], best: best, mated: nil) == nil, "Nxe4 is still to come")
  }

  /// Rule 3: a move that leaves material hanging shows the capture, even where the engine's line plays a quiet move first.
  /// In a Sicilian endgame after 19.Nd5, 19...b6 hangs the pawn to Nxb6; the engine's line opens 20.Rd1.
  @Test func aHangingMoveShowsItsCapture() throws {
    let fen = try #require(walkSan(line(
      "e4 c5 Nf3 Nc6 d4 cxd4 Nxd4 g6 c4 Bg7 Be3 Nf6 Nc3 O-O Be2 e5 Nb3 d6 Qd3 Be6 Rd1 Re8 Qd2 Qc7 Qxd6 Qxd6 Rxd6 Rad8 Rd1 Rxd1+ Kxd1 Rd8+ Kc2 a6 f3 h6 Nd5"
    )).fens.last)
    let yours = ["b7b6", "h1d1", "d8b8", "d5b6"]
    #expect(punishment(fen, .b, yours: yours, best: ["f6d7", "h1d1"], mated: nil) == ["d5b6"])
  }

  /// Rule 3: a pawn the best line would only lose later never excuses one given away now. After 19.Nd5, 19...b6
  /// drops the pawn to Nxb6; the best line, 19...Nd7, loses the d-pawn to Rxd4 by Black's sixth move.
  @Test func laterLossesOnTheBestLineExcuseNothing() throws {
    let fen = try #require(walkSan(line(
      "e4 c5 Nf3 Nc6 d4 cxd4 Nxd4 g6 c4 Bg7 Be3 Nf6 Nc3 O-O Be2 e5 Nb3 d6 Qd3 Be6 Rd1 Re8 Qd2 Qc7 Qxd6 Qxd6 Rxd6 Rad8 Rd1 Rxd1+ Kxd1 Rd8+ Kc2 a6 f3 h6 Nd5"
    )).fens.last)
    let yours = ["b7b6", "d5b6", "g7f8", "h1d1", "f6d7", "b6d7", "c6b4", "c2b1", "d8d7", "d1d7", "e6d7", "b3c5", "d7c8", "c5d3", "b4c6"]
    let best = ["f6d7", "h1d1", "d8c8", "b3c5", "d7c5", "e3c5", "g7f8", "c5e3", "c6d4", "e3d4", "e5d4", "d1d4", "b7b5", "c2b1", "e6d5"]
    #expect(punishment(fen, .b, yours: yours, best: best, mated: nil) == ["d5b6"])
  }

  /// Rule 3: a pawn your own line wins back by your fifth move shows nothing. After 1.e4 e5 2.Nf3 Nc6 3.Bc4, 3...Nd4
  /// gives up e5 to Nxe5, and Qg5 takes g2 and then e4 back.
  @Test func materialWonBackShowsNothing() throws {
    let fen = try #require(walkSan(line("e4 e5 Nf3 Nc6 Bc4")).fens.last)
    let yours = ["c6d4", "f3e5", "d8g5", "e5f7", "g5g2", "h1f1", "g2e4"]
    #expect(punishment(fen, .b, yours: yours, best: ["g8f6", "d2d3", "f8c5", "e1g1"], mated: nil) == nil)
  }

  /// Rule 3: the line shown runs on through the trade counted on its last move's square. In the King's Indian after
  /// 11.h3, 11...Re8 lets 12.Nb5 win d6: ...Nc5 defends it, but Bxc5 dxc5 Rxc5 nets a pawn, so the line plays that out.
  @Test func theLineShowsTheTradeItCounts() throws {
    let fen = try #require(walkSan(line("d4 Nf6 c4 g6 Nc3 Bg7 e4 d6 f3 O-O Be3 e5 d5 c6 g4 cxd5 cxd5 Nbd7 Rc1 h6 h3")).fens.last)
    let yours = ["f8e8", "c3b5", "d7c5", "e3c5", "d6c5", "c1c5"]
    #expect(punishment(fen, .b, yours: yours, best: ["f6e8"], mated: nil) == ["c3b5", "d7c5", "e3c5", "d6c5", "c1c5"])
  }

  /// Rules 4 and 5: past a clean prep, a common move costing 40 or less is a book move and moves no card.
  @Test func bookMovesAfterACleanPrep() throws {
    let done = try prepDone()
    #expect(done.prepStatus == .complete && done.bookTo == 6 && !done.bookOver)
    let step = judgedMove(done, ctx, judged("Ba4", lost: 40), 1, 0)
    #expect(step.session.bookMoves == 1 && !step.session.bookOver)
    #expect(!has(step.effects) { if case .answered = $0 { true } else if case .missed = $0 { true } else { false } })
    #expect(has(step.effects) { if case .pop(let pop) = $0 { pop.book } else { false } })
    var missed = try session(at: line("e4 e5 Nf3 Nc6 Bb5 a6"))
    missed.prepStatus = .off
    #expect(prepRanOut(missed, bookIndex).session.bookTo == nil)
  }

  /// Rule 6: a costlier or uncommon move ends the book phase without ending the run.
  @Test func otherMovesEndTheBookPhase() throws {
    let costly = judgedMove(try prepDone(), ctx, judged("Ba4", lost: 41), 1, 0)
    #expect(costly.session.bookOver && costly.session.ending == nil)
    let rare = judgedMove(try prepDone(), ctx, judged("Kf1", lost: 30), 1, 0)
    #expect(rare.session.bookOver && rare.session.bookMoves == 0)
  }

  /// Rule 7: a moment found on a prepared position is not a moment.
  @Test func momentsOnlyPastPrep() throws {
    let inPrep = judgedMove(try session(), ctx, judged("d4", moment: true, found: true), 1, 0)
    #expect(!has(inPrep.effects) { if case .moment = $0 { true } else { false } })
    let past = judgedMove(try prepDone(), ctx, judged("Bxc6", moment: true, found: true), 1, 0)
    #expect(has(past.effects) { if case .moment(found: true) = $0 { true } else { false } })
  }


  /// Rule 9: a missed mate in a won ending is noted, and the run goes on.
  @Test func missedMateGoesOn() throws {
    let step = judgedMove(try prepDone(), ctx, judged("Ba4", lost: 30, missedMate: true), 1, 0)
    #expect(step.session.ending == nil)
    #expect(has(step.effects) { if case .note(let note) = $0 { note?.text == "Missed mate" } else { false } })
  }

  /// Rule 8.
  @Test func phaseCountsMinorsRooksAndQueens() {
    #expect(gamePhase(START) == 24)
    #expect(gamePhase(LUCENA) == 4)
    #expect(gamePhase("4k3/8/8/8/8/8/8/Q3K2q w - - 0 1") == 8)
  }

  /// Rule 8.
  @Test func endgameStartsAtPhaseEight() {
    #expect(isEndgame(LUCENA))
    #expect(isEndgame("r1r3k1/5ppp/8/8/8/8/5PPP/R1R3K1 w - - 0 1"))
    // One knight more and it is still a middlegame.
    #expect(!isEndgame("r1r3k1/5ppp/8/8/8/8/5PPP/RNR3K1 w - - 0 1"))
    #expect(!isEndgame(START))
  }

  /// Rule 8.
  @Test func resultFollowsTheWinLine() {
    #expect(resultOf(.w, RESULT_WIN_CP) == .win)
    #expect(resultOf(.w, RESULT_WIN_CP - 1) == .draw)
    #expect(resultOf(.b, RESULT_WIN_CP) == .loss)
    #expect(resultOf(.b, -10_000) == .win)
  }

  /// Rule 9.
  @Test func missedMateInAWonEndingKeepsTheRun() {
    // The engine had mate; your move keeps a clear win. It costs a little, never the run.
    let verdict = judgeEndgame(.w, 10_000, 500)
    #expect(verdict.ok)
    #expect(verdict.lost == ENDGAME_SCORE_CAP - 500)
    // The same move from Black's side.
    #expect(judgeEndgame(.b, -10_000, -500).ok)
  }

  /// Rule 8.
  @Test func aWinGivenAwayEndsTheRun() {
    #expect(!judgeEndgame(.w, 450, 50).ok)
    // A draw given away as a loss.
    #expect(!judgeEndgame(.b, 0, 400).ok)
  }

  /// Rule 8.
  @Test func aScoreWobblingAcrossTheWinLineIsNotASlip() {
    #expect(judgeEndgame(.w, RESULT_WIN_CP + 10, RESULT_WIN_CP - 10).ok)
  }

  /// Rule 8.
  @Test func anExactResultStandsOverTheScore() {
    // A tablebase says the win is gone, however small the score's drop.
    #expect(!judgeEndgame(.w, 320, 300, exact: (before: .win, after: .draw)).ok)
    // And a draw it says is held is held, whatever the score did.
    #expect(judgeEndgame(.w, 200, -250, exact: (before: .draw, after: .draw)).ok)
  }

  /// Rule 8.
  @Test func judgeMoveSwitchesRulesInTheEndgame() {
    // A full point dropped in a level position: a blunder in the middlegame, a held draw in an ending.
    #expect(!judgeMove(START, .w, 0, -100).ok)
    #expect(judgeMove(LUCENA, .w, 0, -100).ok)
    #expect(judgeMove(ROOKS, .w, 0, -100).ok)
  }

  /// Rule 8.
  @Test func endgameRulesStayOnOnceTheGameReachedAnEndgame() {
    // A full point dropped from a level position with material back on the board: a held draw once the game has been an endgame.
    #expect(!judgeMove(START, .w, 0, -100).ok)
    #expect(judgeMove(START, .w, 0, -100, reached: true).ok)
    #expect(!endgameReached([]))
    #expect(!endgameReached(["e4", "e5", "Nf3"]))
  }

  /// Rule 10.
  @Test func slipTextNamesTheResultGivenAway() {
    #expect(slipText(.win, .draw) == "Win slipped to a draw")
    #expect(slipText(.draw, .loss) == "Draw slipped to a loss")
    #expect(slipText(.draw, .draw) == nil)
    #expect(slipText(.draw, .win) == nil)
  }

  /// Rule 10.
  @Test func aGivenAwayEndingIsKeptFromThePositionBeforeTheMove() throws {
    // Black to move, deep into the fifty-move count, gave a won rook ending away.
    let fen = "8/8/8/4k3/8/8/2r5/4K3 b - - 87 120"
    let slip = Ending.blunder(played: "Kd4", best: "Ke4", lost: 500, line: [], slip: ResultSlip(from: .win, to: .draw))
    let kept = try #require(endgameGivenAway(slip, fen: fen, name: "Sicilian", at: 5))
    // Still Black to move, the fifty-move count started afresh, so the win is there to be played for.
    #expect(kept.fen == "8/8/8/4k3/8/8/2r5/4K3 b - - 0 120")
    #expect(kept.goal == .win)
    // A draw given away as a loss is kept to be held.
    let held = Ending.blunder(played: "Kd4", best: "Ke4", lost: 300, line: [], slip: ResultSlip(from: .draw, to: .loss))
    #expect(endgameGivenAway(held, fen: fen, name: "Sicilian", at: 5)?.goal == .hold)
    // A middlegame blunder, or a run that ended on the board, keeps nothing.
    #expect(endgameGivenAway(.blunder(played: "Kd4", best: nil, lost: 500, line: [], slip: nil), fen: fen, name: "", at: 5) == nil)
    #expect(endgameGivenAway(.draw, fen: fen, name: "", at: 5) == nil)
  }
}
