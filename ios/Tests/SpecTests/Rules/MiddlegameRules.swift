import ChessCore
import Foundation
import Model
import Testing

/// The QGD Exchange to 11...Bd6. Your line is the first 13 plies, to 7.Bd3.
private let QGD = line("d4 d5 c4 e6 Nc3 Nf6 cxd5 exd5 Bg5 Be7 e3 O-O Bd3 Nbd7 Qc2 Re8 Nge2 Nf8 O-O c6 Rab1 Bd6")
private let YOURS = Array(QGD.prefix(13))
private let FENS = walkSan(QGD).fens

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

/// A run started at the QGD handoff, White to play move 12.
private func handoffRun() throws -> (session: RunSession, tree: OpeningTree) {
  let tree = openingTree(bookIndex)
  var state = AppState()
  state.seed(tree, STARTER_SETS[0])
  var opts = StartOptions(steer: .lines, tree: tree, reps: state.playbookList, node: nodeById(tree, ""), color: .w)
  opts.at = QGD
  opts.seed = 1
  let begun = try #require(startRun(opts))
  return (beginMiddlegame(begun), tree)
}

@Suite("docs/rules/middlegame.md") struct MiddlegameRules {
  /// Rule 6.
  @Test func middlegameStartsWhenBothSidesAreDeveloped() {
    // After 9...Nf8 White's minors are all out, but the king hasn't castled.
    #expect(minorsAtHome(FENS[18], .w) == 0)
    #expect(!kingHasMoved(FENS[18], .w))
    #expect(!middlegameStarted(FENS[18], ply: 18))
    // After 10.O-O: Black's only minor at home is Bc8 (the knight on f8 is not on a knight's square).
    #expect(minorsAtHome(FENS[19], .b) == 1)
    #expect(middlegameStarted(FENS[19], ply: 19))
  }

  /// Rule 6.
  @Test func middlegameStartsByMoveFifteenRegardless() {
    // Ply 30 is White's 16th move: move 15 has been played by both sides.
    #expect(!middlegameStarted(START_FEN, ply: 29))
    #expect(middlegameStarted(START_FEN, ply: 30))
  }

  /// Rule 6.
  @Test func aKingThatLostItsCastlingRightsHasMoved() {
    // Kings back on e1 and e8, White with no rights left, Black still with both.
    let fen = "r3k2r/pppppppp/8/8/8/8/PPPPPPPP/R3K2R w kq - 0 1"
    #expect(kingHasMoved(fen, .w))
    #expect(!kingHasMoved(fen, .b))
  }

  /// Rule 4.
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

  /// Rule 4.
  @Test func withNothingInTheBandTheClosestIsPlayed() {
    // Both are outside the band; "b" is closer to it, however often "a" is played.
    let candidates = [HandoffCandidate(san: "a", weight: 9, cp: -260), HandoffCandidate(san: "b", weight: 1, cp: 150)]
    #expect(pickInBand(candidates, center: 0, mulberry32(1)) == "b")
  }

  /// Rule 3.
  @Test func theEngineFillsInWhenTheBookRunsOutBeforeTheMiddlegame() async {
    // The book knows three moves past your line; the engine plays on to 10...c6.
    let t = tools(book: movesAt(13..<16), engine: movesAt(16..<20))
    let handoff = await buildHandoff(YOURS, color: .w, tools: t, seed: 1)
    #expect(handoff?.line == Array(QGD.prefix(20)))
    #expect(handoff?.kinds == Array(repeating: .prep, count: 13) + Array(repeating: .book, count: 3) + Array(repeating: .engine, count: 4))
    #expect(handoff?.prep == 13)
  }

  /// Rule 5.
  @Test func theHandoffWaitsForTheBookToEnd() async {
    // The middlegame starts at 10.O-O, but the book goes on to 11...Bd6: you take over at move 12.
    let handoff = await buildHandoff(YOURS, color: .w, tools: tools(book: movesAt(13..<22), engine: [:]), seed: 1)
    #expect(handoff?.line == QGD)
    #expect(handoff?.kinds.filter { $0 == .book }.count == 9)
    #expect(handoff.map { fenTurn(walkSan($0.line).fens.last!) } == .w)
  }

  /// Rule 4.
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

  /// Rule 4.
  @Test func anEngineMoveInTheBandBeatsABookMoveOutsideIt() async {
    // At move 7 Black's book has only c6, which would take the eval to +4; the engine's Nbd7 keeps it.
    var book = movesAt(14..<22)
    book[positionKey(FENS[13])] = ["c6"]
    let handoff = await buildHandoff(
      YOURS, color: .w, tools: tools(book: book, engine: [positionKey(FENS[13]): ["Nbd7"]], scores: ["c6": 400]), seed: 1)
    #expect(handoff?.line[13] == "Nbd7")
    #expect(handoff?.kinds[13] == .engine)
    #expect(handoff?.line == QGD)
  }

  /// Rule 4.
  @Test func theEnginesMovesAreHeldToTheBandAtTheBandsDepth() async {
    // The level's shallow search scores c6 level with Nbd7 and likes it far more; the band's own search has c6 at +4.
    let base = tools(book: [:], engine: movesAt(14..<20), scores: ["c6": 400])
    let at13 = positionKey(FENS[13])
    let t = HandoffTools(
      book: base.book, evaluate: base.evaluate, score: base.score,
      engineMoves: { fen in
        if positionKey(fen) != at13 { return await base.engineMoves(fen) }
        return [HandoffCandidate(san: "c6", weight: 99, cp: 30), HandoffCandidate(san: "Nbd7", weight: 1, cp: 30)]
      })
    for seed in 0..<10 {
      let handoff = await buildHandoff(YOURS, color: .w, tools: t, seed: Double(seed))
      #expect(handoff?.line[13] == "Nbd7")
    }
  }

  /// Rule 2.
  @Test func aDrawWithNoLineOfYoursPlaysNothingOut() throws {
    // Only a Black Playbook: a White draw in the Italian falls back on the opening's own moves, which aren't yours.
    let tree = openingTree(bookIndex)
    var state = AppState()
    state.seed(tree, STARTER_SETS[0])
    let italian = line("e4 e5 Nf3 Nc6 Bc4")
    let node = try #require(deepestNodeAlong(tree, italian))
    let blackOnly = state.playbookList.filter { $0.color == .b }
    var opts = StartOptions(steer: .lines, tree: tree, reps: blackOnly, node: node, color: .w)
    opts.seed = 1
    let fallback = try #require(startRun(opts))
    #expect(middlegameLine(fallback, blackOnly).sans.isEmpty)
    // With the White Playbook the starter set saved, the draw is its line.
    opts.reps = state.playbookList
    let drawn = try #require(startRun(opts))
    let yours = middlegameLine(drawn, state.playbookList)
    #expect(yours.sans == italian)
    #expect(!yours.gap)
  }

  /// Rule 7.
  @Test func aGapLineIsHandedOverAtTheGap() async {
    // Your line to 7.Bd3, then Black's 7...c6, which your Playbook has no answer for: you take it from there.
    let gapLine = Array(QGD.prefix(13)) + ["c6"]
    let t = tools(book: [positionKey(walkSan(gapLine).fens.last!): ["Qc2"]], engine: movesAt(13..<22))
    let handoff = await buildHandoff(gapLine, color: .w, tools: t, seed: 1, gap: true)
    #expect(handoff?.line == gapLine)
    #expect(handoff?.kinds == Array(repeating: .prep, count: 13) + [.book])
    #expect(handoff?.prep == 13)
  }

  /// Rule 8.
  @Test func aMiddlegameRunAsksNoPrepAndHasNoBookPhase() throws {
    let (session, _) = try handoffRun()
    #expect(session.state.run.played == QGD)
    #expect(prepMoves(session).isEmpty)
    #expect(prepLabel(session) == .middlegame)
    #expect(!bookRanOut(session, bookIndex))
    // The first goal comes from the eval at the handoff.
    let set = missionFrom(session, middlegamePrefs(DEFAULT_RUN), 40)
    #expect(set.state.extras.mission?.kind == missionFor(.w, 40, set.state.run.fen).kind)
    // The end screen's Handoff tab is where your board began.
    #expect(set.prepEnd == QGD)
  }

  /// Rule 9.
  @Test func middlegamePointsAreKeptApartFromRuns() throws {
    let (_, tree) = try handoffRun()
    var state = AppState()
    state.endMiddlegame(tree, YOURS, 120)
    state.endMiddlegame(tree, YOURS, 80)
    #expect(state.middlegame.global.bestPoints == 120)
    #expect(state.middlegame.global.recent == [120, 80])
    #expect(state.runRecord == RunRecord())
    let data = try JSONEncoder().encode(state)
    #expect(try JSONDecoder().decode(AppState.self, from: data) == state)
  }

  /// Rule 1.
  @Test func theModeAlwaysScoresInPoints() {
    var prefs = DEFAULT_RUN
    prefs.steer = .book
    prefs.combo = false
    let played = middlegamePrefs(prefs)
    #expect(played.steer == .lines)
    #expect(played.moments && played.missions && played.combo)
  }

  /// Rule 10.
  @Test func theHandoffsStructureNamesYourPlan() throws {
    // At the QGD handoff White has the Carlsbad's minority attack; Black plays on the kingside.
    let structure = try #require(structureOf(FENS[22]))
    #expect(structure.template.id == "carlsbad")
  }
}
