import ChessCore
import Foundation
import Model
import Testing

private func whiteState() -> (AppState, String) {
  var state = AppState()
  let id = state.ensureRepertoire(.w)
  state.addLine(id, line("e4 e5 Nf3 Nc6 Bb5"), .fixed(.book))
  state.addLine(id, line("d4 d5 c4 e6 Nc3"), .fixed(.book))
  return (state, id)
}

private func source(_ state: AppState, _ tree: OpeningTree, _ node: OpeningNode, _ color: Color, due: [[String]] = []) -> LineSource {
  let rep = state.repertoireList.first { $0.color == color }
  return freeformSource(tree, node, rep, color, weakness: nil, seen: NOTHING_SEEN, due: due)
}

/// The opponent follows you into whichever of your lines you play.
@Test func freeformOpponentFollowsYourLine() throws {
  let tree = openingTree(bookIndex)
  let (state, _) = whiteState()
  let src = source(state, tree, tree.root, .w)
  let afterE4 = try #require(applySan(START_FEN, "e4")).after
  let afterD4 = try #require(applySan(START_FEN, "d4")).after
  #expect(src.weightsAt(afterE4, ["e4"]).map(\.san) == ["e5"])
  #expect(src.weightsAt(afterD4, ["d4"]).map(\.san) == ["d5"])
}

/// As Black, the opening picked on Home decides the opponent's first move, already played when the run begins.
@Test func freeformBlackPickSteersFirstMove() throws {
  let tree = openingTree(bookIndex)
  var state = AppState()
  let id = state.ensureRepertoire(.b)
  state.addLine(id, line("e4 c5 Nf3 d6"), .fixed(.book))
  state.addLine(id, line("d4 Nf6 c4 e6"), .fixed(.book))
  let sicilian = deepestNodeWithin(tree, tree.root, line("e4 c5"))
  for seed in [1.0, 2, 3, 4, 5] {
    var opts = BeginOptions(tree: tree, reps: state.repertoireList, node: sicilian, color: .b)
    opts.free = true
    opts.seed = seed
    let begun = try #require(beginRun(opts))
    #expect(begun.run.played == ["e4"])
    #expect(begun.run.target.isEmpty)
  }
}

/// A gap due a new move puts its reply among the opponent's choices and weighs the way toward it more.
@Test func freeformLeansTowardDueGap() throws {
  let tree = openingTree(bookIndex)
  let (state, _) = whiteState()
  let afterE4 = try #require(applySan(START_FEN, "e4")).after
  let plain = source(state, tree, tree.root, .w)
  let leaning = source(state, tree, tree.root, .w, due: [line("e4 c5")])
  #expect(!plain.weightsAt(afterE4, ["e4"]).contains { $0.san == "c5" })
  #expect(leaning.weightsAt(afterE4, ["e4"]).contains { $0.san == "c5" })
  // At move one the opponent has no turn, but a deeper gap boosts the reply on its way.
  var blackState = AppState()
  let id = blackState.ensureRepertoire(.b)
  blackState.addLine(id, line("e4 c5 Nf3 d6"), .fixed(.book))
  blackState.addLine(id, line("d4 Nf6 c4 e6"), .fixed(.book))
  let share = { (src: LineSource) -> Double in
    let w = src.weightsAt(START_FEN, [])
    let total = w.reduce(0) { $0 + $1.weight }
    return (w.first { $0.san == "d4" }?.weight ?? 0) / total
  }
  let base = share(source(blackState, tree, tree.root, .b))
  let boosted = share(source(blackState, tree, tree.root, .b, due: [line("d4 Nf6 c4 g6")]))
  #expect(boosted > base)
}

/// Once a Freeform run is off prep nothing is graded, even back in your lines; Drill still grades.
@Test func freeformOffPrepIsFinal() throws {
  let tree = openingTree(bookIndex)
  let (state, _) = whiteState()
  var free = StartOptions(steer: .lines, tree: tree, reps: state.repertoireList, node: tree.root, color: .w)
  free.free = true
  var session = beginSession(try #require(startSurvival(free)))
  #expect(prepMoves(session) == ["e4", "d4"] || prepMoves(session) == ["d4", "e4"])
  session.prepStatus = .off
  #expect(prepMoves(session).isEmpty)
  var drill = beginSession(try #require(startSurvival(StartOptions(steer: .lines, tree: tree, reps: state.repertoireList, node: tree.root, color: .w))))
  drill.state.run.fen = START_FEN
  let before = prepMoves(drill)
  drill.prepStatus = .off
  #expect(!before.isEmpty)
  #expect(prepMoves(drill) == before)
}
