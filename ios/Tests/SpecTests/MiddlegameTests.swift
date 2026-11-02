import ChessCore
import Foundation
import Model
import Testing

/// Middlegame mode: where a middlegame starts, the band, and the handoff built from your line.

/// The QGD Exchange to 11...Bd6. Your line is the first 13 plies, to 7.Bd3.
private let QGD = line("d4 d5 c4 e6 Nc3 Nf6 cxd5 exd5 Bg5 Be7 e3 O-O Bd3 Nbd7 Qc2 Re8 Nge2 Nf8 O-O c6 Rab1 Bd6")
private let YOURS = Array(QGD.prefix(13))
private let FENS = walkSan(QGD).fens

@Test func middlegameStartsWhenBothSidesAreDeveloped() {
  // After 9...Nf8 White's minors are all out, but the king hasn't castled.
  #expect(minorsAtHome(FENS[18], .w) == 0)
  #expect(!kingHasMoved(FENS[18], .w))
  #expect(!middlegameStarted(FENS[18], ply: 18))
  // After 10.O-O: Black's only minor at home is Bc8 (the knight on f8 is not on a knight's square).
  #expect(minorsAtHome(FENS[19], .b) == 1)
  #expect(middlegameStarted(FENS[19], ply: 19))
}

@Test func middlegameStartsByMoveFifteenRegardless() {
  #expect(!middlegameStarted(START_FEN, ply: MIDDLEGAME_BY_PLY - 1))
  #expect(middlegameStarted(START_FEN, ply: MIDDLEGAME_BY_PLY))
}

@Test func aKingThatLostItsCastlingRightsHasMoved() {
  // Kings back on e1 and e8, White with no rights left, Black still with both.
  let fen = "r3k2r/pppppppp/8/8/8/8/PPPPPPPP/R3K2R w kq - 0 1"
  #expect(kingHasMoved(fen, .w))
  #expect(!kingHasMoved(fen, .b))
}

@Test func onlyMovesInsideTheBandArePicked() {
  let candidates = [
    HandoffCandidate(san: "a", weight: 50, cp: 80),
    HandoffCandidate(san: "b", weight: 1, cp: 150),
    HandoffCandidate(san: "c", weight: 50, cp: 340),
  ]
  for seed in 0..<20 {
    #expect(pickInBand(candidates, center: 200, mulberry32(UInt32(seed))) == "b")
  }
}

@Test func withNothingInTheBandTheClosestIsPlayed() {
  let candidates = [HandoffCandidate(san: "a", weight: 9, cp: -150), HandoffCandidate(san: "b", weight: 1, cp: 260)]
  #expect(pickInBand(candidates, center: 0, mulberry32(1)) == "b")
}

/// Tools that answer from tables keyed by position: the book's moves, the engine's moves, and scores by move.
private func tools(book: [String: [String]], engine: [String: [String]], scores: [String: Double] = [:], center: Double = 30) -> HandoffTools {
  HandoffTools(
    book: { fen in (book[positionKey(fen)] ?? []).map { (san: $0, games: 100) } },
    evaluate: { _ in center },
    score: { _, sans in Dictionary(uniqueKeysWithValues: sans.map { ($0, scores[$0] ?? center) }) },
    engineMoves: { fen in (engine[positionKey(fen)] ?? []).map { HandoffCandidate(san: $0, weight: 1, cp: scores[$0] ?? center) } })
}

/// The QGD's move at each of these plies, keyed by the position it is played from.
private func movesAt(_ plies: Range<Int>) -> [String: [String]] {
  Dictionary(uniqueKeysWithValues: plies.map { (positionKey(FENS[$0]), [QGD[$0]]) })
}

@Test func theEngineFillsInWhenTheBookRunsOutBeforeTheMiddlegame() async {
  // The book knows three moves past your line; the engine plays on to 10...c6.
  let t = tools(book: movesAt(13..<16), engine: movesAt(16..<20))
  let handoff = await buildHandoff(YOURS, color: .w, tools: t, seed: 1)
  #expect(handoff?.line == Array(QGD.prefix(20)))
  #expect(handoff?.kinds == Array(repeating: .prep, count: 13) + Array(repeating: .book, count: 3) + Array(repeating: .engine, count: 4))
  #expect(handoff?.prep == 13)
}

@Test func theHandoffWaitsForTheBookToEnd() async {
  // The middlegame starts at 10.O-O, but the book goes on to 11...Bd6: you take over at move 12.
  let handoff = await buildHandoff(YOURS, color: .w, tools: tools(book: movesAt(13..<22), engine: [:]), seed: 1)
  #expect(handoff?.line == QGD)
  #expect(handoff?.kinds.filter { $0 == .book }.count == 9)
  #expect(handoff.map { fenTurn(walkSan($0.line).fens.last!) } == .w)
}

@Test func bookMovesOutsideTheBandAreSkipped() async {
  // At move 7 Black's book has Nbd7 and c6; c6 would take the eval to +4.
  var book = movesAt(13..<22)
  book[positionKey(FENS[13])] = ["c6", "Nbd7"]
  for seed in 0..<10 {
    let t = tools(book: book, engine: [:], scores: ["c6": 400])
    let handoff = await buildHandoff(YOURS, color: .w, tools: t, seed: Double(seed))
    #expect(handoff?.line[13] == "Nbd7")
  }
}
