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
  // Both are outside the band; "b" is closer to it, however often "a" is played.
  let candidates = [HandoffCandidate(san: "a", weight: 9, cp: -260), HandoffCandidate(san: "b", weight: 1, cp: 150)]
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

/// A run started at the QGD handoff, White to play move 12.
private func handoffRun() throws -> (session: RunSession, tree: OpeningTree) {
  let tree = openingTree(bookIndex)
  var state = AppState()
  state.seed(tree, STARTER_SETS[0])
  var opts = StartOptions(steer: .lines, tree: tree, reps: state.repertoireList, node: nodeById(tree, ""), color: .w)
  opts.at = QGD
  opts.seed = 1
  let begun = try #require(startSurvival(opts))
  return (beginMiddlegame(begun), tree)
}

@Test func aMiddlegameRunAsksNoPrepAndHasNoBookPhase() throws {
  let (session, _) = try handoffRun()
  #expect(session.state.run.played == QGD)
  #expect(prepMoves(session).isEmpty)
  #expect(prepLabel(session) == .middlegame)
  #expect(!bookRanOut(session, bookIndex))
  // The first goal comes from the eval at the handoff.
  let set = missionFrom(session, middlegamePrefs(DEFAULT_SURVIVAL), 40)
  #expect(set.state.extras.mission?.kind == missionFor(.w, 40, set.state.run.fen).kind)
  // The end screen's Handoff tab is where your board began.
  #expect(set.prepEnd == QGD)
}

@Test func middlegamePointsAreKeptApartFromSurvival() throws {
  let (_, tree) = try handoffRun()
  var state = AppState()
  state.endMiddlegame(tree, YOURS, 120)
  state.endMiddlegame(tree, YOURS, 80)
  #expect(state.middlegame.global.bestPoints == 120)
  #expect(state.middlegame.global.recent == [120, 80])
  #expect(state.survival == SurvivalRecord())
  let data = try JSONEncoder().encode(state)
  #expect(try JSONDecoder().decode(AppState.self, from: data) == state)
}

@Test func theModeAlwaysScoresInPoints() {
  var prefs = DEFAULT_SURVIVAL
  prefs.steer = .book
  prefs.combo = false
  let played = middlegamePrefs(prefs)
  #expect(played.steer == .lines)
  #expect(played.moments && played.missions && played.combo)
}

@Test func everyStructureHasAHeadlineForEachSide() {
  for template in STRUCTURE_TEMPLATES {
    let headlines = PLAN_HEADLINES[template.id]
    #expect(headlines != nil, "\(template.id)")
    #expect(headlines?.a.isEmpty == false && headlines?.b.isEmpty == false, "\(template.id)")
  }
  #expect(PLAN_HEADLINES.count == STRUCTURE_TEMPLATES.count)
}

@Test func theHandoffsStructureNamesYourPlan() throws {
  // At the QGD handoff White has the Carlsbad's minority attack; Black plays on the kingside.
  let structure = try #require(structureOf(FENS[22]))
  #expect(structure.template.id == "carlsbad")
  #expect(planHeadline(structure, .w) == "Minority attack")
  #expect(planHeadline(structure, .b) == "Kingside play")
}

@Test func aPlansBoldMovesReadAsItsSteps() {
  // Every step, for each side and either color as side a, joins back to planFor's words.
  var marked = 0
  for template in STRUCTURE_TEMPLATES {
    for a in [Color.w, .b] {
      let structure = Structure(template: template, a: a)
      for me in [Color.w, .b] {
        let runs = planRuns(structure, me)
        #expect(runs.map { $0.map(\.text).joined() } == planFor(structure, me).map(\.text), "\(template.id)")
        marked += runs.joined().filter(\.move).count
      }
    }
  }
  #expect(marked > 0)
}

@Test func aHeadlinesSquaresArePlacedForTheBoard() throws {
  let stonewall = try #require(STRUCTURE_TEMPLATES.first { $0.id == "stonewall" })
  #expect(planHeadline(Structure(template: stonewall, a: .w), .w) == "Knight to e5")
  #expect(planHeadline(Structure(template: stonewall, a: .b), .b) == "Knight to e4")
  #expect(planHeadline(Structure(template: stonewall, a: .b), .w) == "The e5 outpost")
}
