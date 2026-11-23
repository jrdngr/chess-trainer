import ChessCore
import Foundation
import Model
import Testing

/// A White Smith-Morra you know well, stopping at 3.c3.
private func morra() -> (AppState, String) {
  var state = AppState()
  let id = state.ensurePlaybook(.w)
  state.addLine(id, line("e4 c5 d4 cxd4 c3"), .fixed(.book))
  let fens = walkSan(line("e4 c5 d4 cxd4")).fens
  for _ in 0..<4 {
    state.answered(id, fens[0], "e4", .easy)
    state.answered(id, fens[2], "d4", .easy)
    state.answered(id, fens[4], "c3", .easy)
  }
  return (state, id)
}

@Suite("docs/rules/growth.md") struct GrowthRules {
  /// Rule 2: only prep followed without a miss marks where growing would start.
  @Test func cleanPrepMarksTheHole() throws {
    let tree = openingTree(bookIndex)
    let (state, _) = morra()
    let begun = try #require(startRun(StartOptions(steer: .lines, tree: tree, reps: state.playbookList, node: tree.root, color: .w)))
    let clean = beginSession(begun)
    #expect(prepRanOut(clean, bookIndex).session.prepEnd == clean.state.run.played)
    var missed = clean
    missed.state = playYours(clean.state, "d4", "e4")
    #expect(prepRanOut(missed, bookIndex).session.prepEnd == nil)
  }

  /// Rule 4: the hole's answer turns yes once the pace reaches 1, at the curve's next hole.
  @Test func holeAnswersYesOncePaceIsDue() throws {
    let tree = openingTree(bookIndex)
    var (state, _) = morra()
    let selection = Selection(color: .w, opening: try #require(tree.byId["e4 c5 d4"]).id)
    let hole = line("e4 c5 d4 cxd4 c3 dxc3")
    #expect(growAtHole(state, tree, selection, color: .w, line: hole)?.yes == false)
    let after = lastAddedAt(state.playbookList) + 1
    for i in 0..<3 {
      state.recordGame(GameRecord(
        id: "g\(i)", mode: .play, at: after + Double(i), color: .w, picked: selection, opening: "", moves: ["e4"],
        result: "*", termination: "ended"))
    }
    state.recordGame(GameRecord(
      id: "m", mode: .middlegame, at: after + 9, color: .w, picked: selection, opening: "", moves: ["e4"],
      result: "*", termination: "ended"))
    #expect(runsSinceAdded(state.games, state.playbookList) == 3)
    #expect(pace(runs: 3, size: 3) == 1)
    let found = try #require(growAtHole(state, tree, selection, color: .w, line: hole))
    #expect(found.yes && found.gap.line == hole)
  }

  /// Rule 1: a reply answered under one move order is answered at that position under every order, whichever comes first.
  @Test func aReplyAnsweredInAnotherOrderIsNoHole() {
    let a = findHoles(rep(.b, ["c4 e6 d4 d5", "d4 d5 c4 e6 Nc3 Nf6 Bg5 Be7"]), bookIndex)
    let b = findHoles(rep(.b, ["d4 d5 c4 e6 Nc3 Nf6 Bg5 Be7", "c4 e6 d4 d5"]), bookIndex)
    #expect(!a.contains { $0.san == "Nc3" && walkSan($0.path).fens.last.map(positionKey) == walkSan(line("d4 d5 c4 e6")).fens.last.map(positionKey) })
    #expect(Set(a.map { positionKey($0.after) }) == Set(b.map { positionKey($0.after) }), "the order the lines were added in doesn't matter")
  }

  /// Rule 1: a hole grows when at least 1% of your games meet it, most met first.
  @Test func holesMetInOnePercent() throws {
    let tree = openingTree(bookIndex)
    let found = curveHoles([rep(.w, ["e4 e5 Nf3 Nc6 Bb5 a6", "d4 d5 c4"])], bookIndex, tree: tree)
    #expect(!found.isEmpty)
    #expect(found.allSatisfy { $0.importance >= CURVE_MIN_REACH })
    #expect(zip(found, found.dropFirst()).allSatisfy { $0.importance >= $1.importance })
    #expect(found.allSatisfy { $0.importance == $0.hole.reach * $0.hole.share / 100 })
  }

  /// Rule 3: a hole's level is the opponent's move number at it when that is 1 or 2, else 0.
  @Test func levelsByTheOpponentsMove() throws {
    let tree = openingTree(bookIndex)
    let found = curveHoles([rep(.w, ["c4 e5 Nc3 Nf6 Nf3 Nc6"])], bookIndex, tree: tree)
    let first = try #require(found.first { $0.path == line("c4") })
    let second = try #require(found.first { $0.path == line("c4 e5 Nc3") })
    let deep = try #require(found.first { $0.path.count >= 4 })
    #expect(curveLevel(first) == 1)
    #expect(curveLevel(second) == 2)
    #expect(curveLevel(deep) == 0)
    let black = curveHoles([rep(.b, ["e4 e6 d4 d5"])], bookIndex, tree: tree)
    #expect(black.filter { $0.path.isEmpty }.allSatisfy { curveLevel($0) == 1 })
    #expect(black.filter { $0.path.count == 2 }.allSatisfy { curveLevel($0) == 2 })
  }

  /// Rule 3: level 2 opens once no depth hole is left, at 20 games with every opening green;
  /// level 1 the same after level 2, at 40 games.
  @Test func levelsOpenInTurn() throws {
    let tree = openingTree(bookIndex)
    let found = curveHoles([rep(.w, ["c4 e5 Nc3 Nf6 Nf3 Nc6"])], bookIndex, tree: tree)
    let shallow = found.filter { curveLevel($0) != 0 }
    let onlyFirst = found.filter { curveLevel($0) == 1 }
    let green = CurveGate(games: 40, green: 3, openings: 3)
    #expect(openLevels(found, green) == [0], "depth first")
    #expect(openLevels(shallow, green) == [0, 2])
    #expect(openLevels(onlyFirst, green) == [0, 2, 1])
    #expect(openLevels(onlyFirst, CurveGate(games: 39, green: 3, openings: 3)) == [0, 2])
    #expect(openLevels(onlyFirst, CurveGate(games: 19, green: 3, openings: 3)) == [0])
    #expect(openLevels(onlyFirst, CurveGate(games: 40, green: 2, openings: 3)) == [0])
    #expect(openLevels(found, CurveGate(games: 0, green: 0, openings: 3), opened: [2]) == [0, 2], "an opened level stays open")
  }

  /// Rule 3: the games are every Play game played, not only those the history keeps, and a level opened stays open.
  @Test func levelsCountEveryGameAndNeverClose() throws {
    let tree = openingTree(bookIndex)
    var state = AppState()
    let id = state.ensurePlaybook(.w)
    state.addLine(id, line("c4 e5 Nc3 Nf6 Nf3 Nc6"), .fixed(.book))
    for n in 0..<45 {
      state.recordGame(GameRecord(id: "p\(n)", mode: .play, at: 0, color: .w, picked: state.settings.selection, opening: "", moves: ["c4"], result: "*", termination: "ended"))
    }
    for n in 0..<80 {
      state.recordGame(GameRecord(id: "m\(n)", mode: .middlegame, at: 0, color: .w, picked: state.settings.selection, opening: "", moves: ["c4"], result: "*", termination: "ended"))
    }
    #expect(playGames(state) == 45, "Middlegame games pushing Play games out of the history don't take them back")
    let saved = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(state))
    #expect(playGames(saved) == 45)
    state.levelsOpened = [2]
    #expect(curvePlaybookGaps(state, tree).contains { curveLevel($0) == 2 }, "level 2 stays open though no opening is green")
  }

  /// Rule 5: green is a form of at least 0.8 over enough answers.
  @Test func greenNeedsEnoughGoodAnswers() {
    var form = FormRecord()
    form.openings["x"] = Array(repeating: 1, count: FORM_MIN_ANSWERS - 1)
    #expect(!isGreen(form, "x", .w))
    form.openings["x"] = Array(repeating: 0.8, count: FORM_MIN_ANSWERS)
    #expect(isGreen(form, "x", .w))
    form.openings["x"] = Array(repeating: 0.7, count: FORM_MIN_ANSWERS)
    #expect(!isGreen(form, "x", .w))
  }

  /// Rule 11: as Black a new reply is answered with the calmest of the three most played; as White the order stays.
  @Test func blackGetsTheCalmestAnswer() {
    let tree = openingTree(bookIndex)
    let answers = popularReplies(bookIndex, walkSan(line("e4")).fens[1], 0).prefix(4).map(\.san)
    let calm = calmFirst(tree, line("e4"), color: .b, answers, san: { $0 })
    let sharp = { (san: String) in sharpnessOf(tree, line("e4") + [san]) }
    #expect(answers.prefix(3).allSatisfy { sharp(calm[0]) <= sharp($0) })
    #expect(Array(calm.dropFirst()) == answers.filter { $0 != calm[0] })
    #expect(calmFirst(tree, line("e4"), color: .w, answers, san: { $0 }) == answers)
  }

  /// Rule 12: growth stays inside your families: a reply into one you don't have is no hole.
  @Test func growthStaysInsideYourFamilies() throws {
    let tree = openingTree(bookIndex)
    var state = AppState()
    let id = state.ensurePlaybook(.b)
    state.addLine(id, line("e4 e5 Nf3 Nc6"), .fixed(.book))
    let holes = curveHoles(state.playbookList, bookIndex, tree: tree)
    #expect(!holes.isEmpty)
    let e5 = try #require(curatedOpening("openGame"))
    #expect(holes.allSatisfy { e5.holds($0.line) && $0.line.count > 2 }, "1.d4 and 1.e4 c5 are openings to buy")
  }

  /// Rule 8: a move added mid-run isn't graded and counts in the book's color.
  @Test func addedMovesAreNotGraded() throws {
    let tree = openingTree(bookIndex)
    let (state, _) = morra()
    let begun = try #require(startRun(StartOptions(steer: .lines, tree: tree, reps: state.playbookList, node: tree.root, color: .w)))
    var session = beginSession(begun)
    session.state.run.fen = START_FEN
    session.state.run.played = []
    let step = playAdded(session, "e4")
    #expect(step.session.answers.isEmpty && step.session.state.misses.isEmpty)
    #expect(step.session.bookTo == 1)
  }

  /// Rule 1: 1.d4 Nf6 is answered by more than half of strong players, so with 1.d4
  /// d5 2.c4 and the Smith-Morra kept, it leads the list. A line that stops
  /// (the Morra after 3.c3) is one gap, at its most played reply.
  @Test func gapsRankByReachAndShare() throws {
    let tree = openingTree(bookIndex)
    let found = gaps([rep(.w, ["e4 c5 d4 cxd4 c3", "d4 d5 c4"])], bookIndex, tree: tree)
    let first = try #require(found.first)
    #expect(first.line == line("d4 Nf6"))
    #expect(first.kind == .noAnswer)
    let morra = found.filter { $0.path == line("e4 c5 d4 cxd4 c3") }
    #expect(morra.count == 1)
    #expect(morra.first?.hole.san == "dxc3")
    #expect(morra.first?.kind == .tooShort)
    #expect(morra.first.map { $0.missing >= 1 } == true)
    // Every gap is common enough at its position.
    #expect(found.allSatisfy { $0.share >= GAP_SHARE })
    // And met often enough to be worth recommending.
    #expect(found.allSatisfy { $0.importance >= GAP_MIN_IMPORTANCE })
    #expect(zip(found, found.dropFirst()).allSatisfy { $0.importance >= $1.importance })
  }

  /// Rule 1: Black's first-move replies are breadth; a line that ends on White's
  /// move is depth.
  @Test func blackGapsKinds() {
    let tree = openingTree(bookIndex)
    let found = gaps([rep(.b, ["e4 e5", "d4 d5"])], bookIndex, tree: tree)
    #expect(found.contains { $0.line == line("Nf3") && $0.kind == .noAnswer })
    #expect(found.contains { $0.line == line("e4 e5 Nf3") && $0.kind == .tooShort })
    #expect(!found.contains { $0.line == line("e4 e5 Nf3 Nc6") })
  }

  /// Rule 9: where a line stops, every common reply can be grown at, not only the gap's.
  @Test func growHereAtEveryCommonReplyWhereALineStops() throws {
    let tree = openingTree(bookIndex)
    var state = AppState()
    let id = state.ensurePlaybook(.w)
    state.addLine(id, line("d4 d5 c4"), .fixed(.book))
    let selection = Selection(color: .w, opening: ANY_OPENING)
    let stops = gaps(state.playbookList, bookIndex, tree: tree).filter { $0.hole.path == line("d4 d5 c4") }
    #expect(stops.map(\.hole.san) == ["e6"], "a line that just stops is one gap, at its most played reply")
    let found = try #require(growAtHole(state, tree, selection, color: .w, line: line("d4 d5 c4 dxc4")))
    #expect(found.yes == false, "only the gap is asked about")
    #expect(found.gap.line == line("d4 d5 c4 dxc4"))
  }

  /// Rule 7: a fill stops at its size, or where the book stops naming the line.
  @Test func fillStopsAtSizeOrNamedEnd() {
    let morra = line("e4 c5 d4 cxd4 c3 dxc3 Nxc3")
    #expect(!fillEnds(bookIndex, morra, added: 1, size: 3))
    #expect(fillEnds(bookIndex, morra, added: 3, size: 3))
    let end = namedEnd(bookIndex, morra)!
    let past = morra + ["Nc6", "Nf3", "d6", "Bc4", "e6", "O-O", "Nf6", "Qe2"]
    #expect(end.ply <= past.count)
    #expect(fillEnds(bookIndex, past, added: 1, size: 5))
  }

  /// Rule 13: green and yellow only on answers the engine has weighed and finds sound.
  @Test func greenIsNeverAWeakMove() {
    let moves = [
      NudgedMove(san: "d3", from: "d2", to: "d3", tone: .toward, reason: "You play d3 in 4 Italian lines", pill: "Your habit"),
      NudgedMove(san: "d4", from: "d2", to: "d4", tone: .toward, pill: "Transposes"),
      NudgedMove(san: "c3", from: "c2", to: "c3", tone: .towardFar, pill: "Your pawns"),
      NudgedMove(san: "Ng5", from: "f3", to: "g5", tone: .away, pill: "Breaks a habit"),
    ]
    let deltas: [String: Double] = ["d3": -CLEARLY_WORSE_CP, "d4": -CLEARLY_WORSE_CP - 1, "Ng5": -200]
    let toned = soundTones(moves) { deltas[$0] }
    #expect(toned[0] == moves[0], "within the line, green stays")
    #expect(toned[1].tone == nil && toned[1].pill == nil, "clearly worse: drawn plain")
    #expect(toned[2].tone == nil, "not weighed yet: no color")
    #expect(toned[3] == moves[3], "red is never taken away")
  }

}
