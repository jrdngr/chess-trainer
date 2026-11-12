import ChessCore
import Foundation
import Model
import Testing

private func whiteState() -> (AppState, String) {
  var state = AppState()
  let id = state.ensurePlaybook(.w)
  state.addLine(id, line("e4 e5 Nf3 Nc6 Bb5"), .fixed(.book))
  state.addLine(id, line("d4 d5 c4 e6 Nc3"), .fixed(.book))
  return (state, id)
}

private func source(_ state: AppState, _ tree: OpeningTree, _ node: OpeningNode, _ color: Color, due: [[String]] = []) -> LineSource {
  let rep = state.playbookList.first { $0.color == color }
  return freeformSource(tree, node, rep, color, weakness: nil, seen: NOTHING_SEEN, due: due)
}

@Suite("docs/rules/freeform.md") struct FreeformRules {
  /// Rule 1: Freeform starts from move one even when all your prep sits deep inside one opening.
  @Test func freeformStartsFromMoveOne() throws {
    let tree = openingTree(bookIndex)
    var state = AppState()
    state.settings.start = .freeform
    let id = state.ensurePlaybook(.b)
    state.addLine(id, line("e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Be3 e5"), .fixed(.book))
    state.addLine(id, line("d4 d5"), .fixed(.book))
    // Recent Tests brake the Playbook-wide Test, so a Review narrowed into the Najdorf wins.
    var history = AutoHistory()
    history.focuses = [.test, .test, .test]
    let round = try #require(nextRound(state, tree, Selection(color: .b, opening: ANY_OPENING), history))
    #expect(round.free)
    #expect(round.pick.opening.id == ANY_OPENING)
    #expect(round.at == nil)
    #expect(round.aim == nil)
  }

  /// Rule 2: Freeform plays the picked side even with nothing to recommend there; only Either takes the recommendation's side.
  @Test func freeformPlaysThePickedSide() throws {
    let tree = openingTree(bookIndex)
    var state = AppState()
    state.settings.start = .freeform
    state.addLine(state.ensurePlaybook(.b), line("e4 c5 d4 cxd4"), .fixed(.book))
    state.addLine(state.ensurePlaybook(.b), line("d4 d5"), .fixed(.book))
    let white = try #require(nextRound(state, tree, Selection(color: .w, opening: ANY_OPENING), AutoHistory()))
    #expect(white.free && white.pick.color == .w)
    let either = try #require(nextRound(state, tree, Selection(color: .either, opening: ANY_OPENING), AutoHistory()))
    #expect(either.pick.color == .b)
  }


  /// Rule 3: the opponent follows you into whichever of your lines you play.
  @Test func freeformOpponentFollowsYourLine() throws {
    let tree = openingTree(bookIndex)
    let (state, _) = whiteState()
    let src = source(state, tree, tree.root, .w)
    let afterE4 = try #require(applySan(START_FEN, "e4")).after
    let afterD4 = try #require(applySan(START_FEN, "d4")).after
    #expect(src.weightsAt(afterE4, ["e4"]).map(\.san) == ["e5"])
    #expect(src.weightsAt(afterD4, ["d4"]).map(\.san) == ["d5"])
  }

  /// Rules 1 and 6: as Black, the opening picked on Home decides the opponent's first move, already played when the run begins.
  @Test func freeformBlackPickSteersFirstMove() throws {
    let tree = openingTree(bookIndex)
    var state = AppState()
    let id = state.ensurePlaybook(.b)
    state.addLine(id, line("e4 c5 Nf3 d6"), .fixed(.book))
    state.addLine(id, line("d4 Nf6 c4 e6"), .fixed(.book))
    let sicilian = deepestNodeWithin(tree, tree.root, line("e4 c5"))
    for seed in [1.0, 2, 3, 4, 5] {
      var opts = BeginOptions(tree: tree, reps: state.playbookList, node: sicilian, color: .b)
      opts.free = true
      opts.seed = seed
      let begun = try #require(beginRun(opts))
      #expect(begun.run.played == ["e4"])
      #expect(begun.run.target.isEmpty)
    }
  }

  /// Rule 5: a gap due a new move puts its reply among the opponent's choices and weighs the way toward it more.
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
    let id = blackState.ensurePlaybook(.b)
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

  /// Rule 7: once a Freeform run is off prep nothing is graded, even back in your lines; Drill still grades.
  @Test func freeformOffPrepIsFinal() throws {
    let tree = openingTree(bookIndex)
    let (state, _) = whiteState()
    var free = StartOptions(steer: .lines, tree: tree, reps: state.playbookList, node: tree.root, color: .w)
    free.free = true
    var session = beginSession(try #require(startRun(free)))
    #expect(prepMoves(session) == ["e4", "d4"] || prepMoves(session) == ["d4", "e4"])
    session.prepStatus = .off
    #expect(prepMoves(session).isEmpty)
    var drill = beginSession(try #require(startRun(StartOptions(steer: .lines, tree: tree, reps: state.playbookList, node: tree.root, color: .w))))
    drill.state.run.fen = START_FEN
    let before = prepMoves(drill)
    drill.prepStatus = .off
    #expect(!before.isEmpty)
    #expect(prepMoves(drill) == before)
  }

  /// Rule 4: a reply weighs more as the lines past it need practice more.
  @Test func needierLinesWeighMore() throws {
    let tree = openingTree(bookIndex)
    var state = AppState()
    let id = state.ensurePlaybook(.w)
    state.addLine(id, line("e4 e5 Nf3"), .fixed(.book))
    state.addLine(id, line("e4 c5 Nf3"), .fixed(.book))
    let rep = try #require(state.playbooks[id])
    let afterE4 = try #require(applySan(START_FEN, "e4")).after
    let sicilian = positionKey(walkSan(line("e4 c5")).fens[2])
    func share(_ weakness: Weakness?) -> Double {
      let weights = freeformSource(tree, tree.root, rep, .w, weakness: weakness, seen: NOTHING_SEEN, due: []).weightsAt(afterE4, ["e4"])
      return weights.first { $0.san == "c5" }!.weight / weights.reduce(0) { $0 + $1.weight }
    }
    #expect(share { _, key in key == sicilian ? 5 : 1 } > share(nil))
  }

  /// Rule 8: past your lines the opponent plays a book move.
  @Test func pastYourLinesTheBookTakesOver() throws {
    let tree = openingTree(bookIndex)
    let (state, _) = whiteState()
    var opts = StartOptions(steer: .lines, tree: tree, reps: state.playbookList, node: tree.root, color: .w)
    opts.free = true
    let begun = try #require(startRun(opts))
    var tally = begun.state
    let past = line("e4 e5 Nf3 Nc6 Bb5")
    tally.run.played = past
    tally.run.fen = walkSan(past).fens[past.count]
    #expect(begun.source.weightsAt(tally.run.fen, past).isEmpty)
    let reply = try #require(bookReply(begun.source, bookIndex, tally, mulberry32(seed: 1)))
    #expect(bookMoves(bookIndex, tally.run.fen).contains(reply))
  }
}
