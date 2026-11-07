import ChessCore
import Foundation
import Model
import Testing

/// The recommendation engine on the real book.

/// 1.d4 Nf6 is answered by more than half of strong players, so with 1.d4
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

/// Black's first-move replies are breadth; a line that ends on White's
/// move is depth.
@Test func blackGapsKinds() {
  let tree = openingTree(bookIndex)
  let found = gaps([rep(.b, ["e4 e5", "d4 d5"])], bookIndex, tree: tree)
  #expect(found.contains { $0.line == line("Nf3") && $0.kind == .noAnswer })
  #expect(found.contains { $0.line == line("e4 e5 Nf3") && $0.kind == .tooShort })
  #expect(!found.contains { $0.line == line("e4 e5 Nf3 Nc6") })
}

/// Home shows three: the top gap of each kind, then the next most important,
/// with breadth gaps listed first.
@Test func homeShowsEachKind() {
  let tree = openingTree(bookIndex)
  let found = gaps([rep(.w, ["e4 c5 d4 cxd4 c3", "d4 d5 c4"])], bookIndex, tree: tree)
  let top = topGaps(found)
  #expect(top.count == 3)
  #expect(top.contains { $0.kind == .tooShort })
  #expect(top.first?.line == line("d4 Nf6"))
  #expect(top.map(\.kind) == top.map(\.kind).sorted { a, _ in a == .noAnswer })
  // Only depth gaps: all three slots go to them.
  let deep = gaps([rep(.b, ["e4 e5", "d4 d5", "Nf3 d5", "c4 e5"])], bookIndex, tree: tree)
  #expect(topGaps(deep).count == min(3, deep.count))
}

/// The basics come first: with only a White Ruy Lopez, Home's three are
/// Black's answers to 1.e4 and 1.d4, then the top White gap.
@Test func basicsLeadHome() throws {
  let tree = openingTree(bookIndex)
  var state = AppState()
  state.addLine(state.ensureRepertoire(.w), line("e4 e5 Nf3 Nc6 Bb5"), .fixed(.book))
  let top = topGaps(playbookGaps(state, tree))
  #expect(top.map(\.line) == [line("e4"), line("d4"), try #require(gaps(state.repertoireList, bookIndex, tree: tree).first).line])
  #expect(top.prefix(2).allSatisfy { $0.color == .b && $0.basic && $0.repertoireId == "" })
  // Answering 1.e4 leaves 1.d4 as the only basic.
  state.addLine(state.ensureRepertoire(.b), line("e4 e5"), .fixed(.book))
  #expect(playbookGaps(state, tree).filter(\.basic).map(\.line) == [line("d4")])
}

/// With only Black lines, White's first move leads; a reply kept with no answer is still missing.
@Test func whiteFirstMoveIsABasic() {
  let tree = openingTree(bookIndex)
  var state = AppState()
  let black = rep(.b, ["e4 c5", "d4"])
  state.repertoires[black.id] = black
  state.repertoireOrder = [black.id]
  let found = playbookGaps(state, tree)
  #expect(found.filter(\.basic).map(\.line) == [[], line("d4")])
  #expect(found.first?.color == .w)
}

/// Play fills a missing Black basic only when the side can be Black, the
/// selected opening's own first move first.
@Test func basicRunOnlyWhenBlackCanPlay() throws {
  let tree = openingTree(bookIndex)
  var state = AppState()
  state.addLine(state.ensureRepertoire(.w), line("e4 e5 Nf3 Nc6 Bb5"), .fixed(.book))
  #expect(basicRunGap(state, tree, Selection(color: .w, opening: ANY_OPENING)) == nil)
  #expect(basicRunGap(state, tree, Selection(color: .random, opening: ANY_OPENING))?.line == line("e4"))
  let qgd = try #require(tree.byId["d4 d5 c4 e6"])
  #expect(basicRunGap(state, tree, Selection(color: .b, opening: qgd.id))?.line == line("d4"))
  state.addLine(state.ensureRepertoire(.b), line("e4 e5"), .fixed(.book))
  state.addLine(state.ensureRepertoire(.b), line("d4 d5"), .fixed(.book))
  #expect(basicRunGap(state, tree, Selection(color: .b, opening: ANY_OPENING)) == nil)
}

/// Five Play games as White with no Black lines bring the question; turning
/// it down waits for five more, and any Black line ends it.
@Test func asksForBlackAfterFiveWhiteGames() {
  var state = AppState()
  state.addLine(state.ensureRepertoire(.w), line("e4 e5 Nf3"), .fixed(.book))
  func play(_ color: Color, at: Double) {
    state.games.append(GameRecord(
      id: "g\(at)", mode: .autopilot, at: at, color: color, picked: DEFAULT_SELECTION, opening: "", moves: [], opened: 0,
      result: "*", termination: "ended"))
  }
  for t in 1...4 { play(.w, at: Double(t)) }
  play(.b, at: 5)
  #expect(!asksForBlack(state))
  play(.w, at: 6)
  #expect(asksForBlack(state))
  state.settings.blackAskedAt = 6
  #expect(!asksForBlack(state))
  for t in 7...11 { play(.w, at: Double(t)) }
  #expect(asksForBlack(state))
  state.addLine(state.ensureRepertoire(.b), line("e4 c5"), .fixed(.book))
  #expect(!asksForBlack(state))
}

/// More shows ten: five "Too short" when there are five, the rest by importance.
@Test func moreShowsTenWithFiveTooShort() {
  let tree = openingTree(bookIndex)
  var state = AppState()
  for set in STARTER_SETS { state.seed(tree, set) }
  let all = playbookGaps(state, tree)
  let short = all.filter { $0.kind == .tooShort }
  #expect(all.count > 10 && short.count >= 5)
  let more = moreGaps(all)
  #expect(more.count == 10)
  #expect(more.filter { $0.kind == .tooShort }.count >= 5)
  // Every "No answer yet" shown outranks every one left out.
  let shownAnswers = more.filter { $0.kind == .noAnswer }
  let leftAnswers = all.filter { g in g.kind == .noAnswer && !more.contains { $0.id == g.id } }
  #expect(shownAnswers.allSatisfy { a in leftAnswers.allSatisfy { a.importance >= $0.importance } })
  #expect(more.map(\.kind) == more.map(\.kind).sorted { a, _ in a == .noAnswer })
}

/// A fill stops at its size, or where the book stops naming the line.
@Test func fillStopsAtSizeOrNamedEnd() {
  let morra = line("e4 c5 d4 cxd4 c3 dxc3 Nxc3")
  #expect(!fillEnds(bookIndex, morra, added: 1, size: 3))
  #expect(fillEnds(bookIndex, morra, added: 3, size: 3))
  let end = namedEnd(bookIndex, morra)!
  let past = morra + ["Nc6", "Nf3", "d6", "Bc4", "e6", "O-O", "Nf6", "Qe2"]
  #expect(end.ply <= past.count)
  #expect(fillEnds(bookIndex, past, added: 1, size: 5))
}

/// p × m² × g ≥ 1: on the top gap with a fill size of 3, a line known at 0.9
/// gets its move on the 4th run, not the 3rd.
@Test func newMoveDueByPaceAndMastery() {
  #expect(!needsNewMove(pace: pace(runs: 3, size: 3), mastery: 0.9, gap: 1))
  #expect(needsNewMove(pace: pace(runs: 4, size: 3), mastery: 0.9, gap: 1))
  #expect(!needsNewMove(pace: pace(runs: 30, size: 3), mastery: 0.3, gap: 1))
  #expect(needsNewMove(pace: pace(runs: 34, size: 3), mastery: 0.3, gap: 1))
  #expect(!needsNewMove(pace: 100, mastery: 0, gap: 1))
}

/// A line's mastery is the average over your moves on it; a move never asked counts as 0.
@Test func masteryCountsUnaskedAsWeak() {
  var state = AppState()
  let id = state.ensureRepertoire(.w)
  state.addLine(id, line("e4 c5 d4 cxd4 c3"), .fixed(.book))
  let rep = state.repertoires[id]!
  #expect(lineMastery(rep, state.cards, line("e4 c5 d4 cxd4 c3")) == 0)
  #expect(lineMastery(rep, state.cards, []) == 1)
  let fens = walkSan(line("e4 c5 d4 cxd4")).fens
  for _ in 0..<3 {
    state.answered(id, fens[0], "e4", .good)
    state.answered(id, fens[2], "d4", .good)
    state.answered(id, fens[4], "c3", .good)
  }
  let known = lineMastery(state.repertoires[id]!, state.cards, line("e4 c5 d4 cxd4 c3"))
  #expect(known > 0.5)
}

/// Once runs since the last new move pass the pace on a well known line,
/// the next run heads for its gap and follows it to the reply.
@Test func dueRunSteersToTheGap() throws {
  let tree = openingTree(bookIndex)
  var state = AppState()
  let id = state.ensureRepertoire(.w)
  state.addLine(id, line("e4 c5 d4 cxd4 c3"), .fixed(.book))
  let fens = walkSan(line("e4 c5 d4 cxd4")).fens
  for _ in 0..<4 {
    state.answered(id, fens[0], "e4", .easy)
    state.answered(id, fens[2], "d4", .easy)
    state.answered(id, fens[4], "c3", .easy)
  }
  let selection = Selection(color: .w, opening: tree.byId["e4 c5 d4"]!.id)
  let quiet = try #require(nextRound(state, tree, selection, AutoHistory()))
  #expect(quiet.aim == nil)
  let after = lastAddedAt(state.repertoireList) + 1
  for i in 0..<5 {
    state.recordGame(GameRecord(
      id: "g\(i)", mode: .autopilot, at: after + Double(i), color: .w, picked: selection, opening: selection.opening, moves: ["e4"],
      result: "*", termination: "ended"))
  }
  #expect(runsSinceAdded(state.games, state.repertoireList) == 5)
  let due = try #require(nextRound(state, tree, selection, AutoHistory()))
  #expect(due.aim == line("e4 c5 d4 cxd4 c3 dxc3"))
  let begun = try #require(startSurvival(survivalOptions(due, state, tree, selection, seed: 1)))
  #expect(begun.state.run.target == line("e4 c5 d4 cxd4 c3 dxc3"))
  let hole = try #require(growAtHole(state, tree, selection, color: .w, line: line("e4 c5 d4 cxd4 c3 dxc3")))
  #expect(hole.yes)
  #expect(hole.gap.kind == .tooShort)
}
