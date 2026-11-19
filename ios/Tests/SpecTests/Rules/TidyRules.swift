import ChessCore
import Foundation
import Model
import Testing

/// A White Playbook with a Catalan and a Queen's Gambit, a Four Knights and a Petrov.
private let WHITE = [
  "d4 Nf6 c4 e6 g3 d5 Bg2 Be7 Nf3 O-O O-O",
  "d4 d5 c4 e6 Nc3 Nf6 Bg5 Be7 e3 O-O Nf3",
  "e4 e5 Nf3 Nc6 Nc3 Nf6 Bb5 Bb4 O-O O-O d3",
  "e4 e5 Nf3 Nf6 Nxe5 d6 Nf3 Nxe4 d4 d5 Bd3",
]

private let OPTS = TidyOptions(minShare: AUTO_GROWTH.minShare)
private func noLoss(_ fen: String, _ san: String) -> Double? { 0 }

private func choices(_ r: Playbook) -> [TidyChoice] {
  tidyPositions([r]).compactMap { choiceAt(r, bookIndex, $0.node, OPTS) }
}

private func choice(_ r: Playbook, _ path: String) throws -> TidyChoice {
  try #require(choices(r).first { $0.path == line(path) })
}

private func find(_ r: Playbook, _ c: TidyChoice, _ loss: MoveLoss = noLoss) throws -> TidyFind {
  guard case .find(let f) = decide(r, bookIndex, c, loss) else {
    Issue.record("no find at \(c.path)")
    throw CancellationError()
  }
  return f
}

@Suite("docs/rules/tidy.md") struct TidyRules {
  /// Rule 1: every move of yours, in every playbook, a position once; never your first move.
  @Test func looksAtEveryMoveOfYoursOnce() {
    let white = rep(.w, WHITE)
    let black = rep(.b, ["d4 d5 c4 e6 Nc3 Nf6", "c4 e6 Nc3 d5 d4 Nf6"])
    let looked = tidyPositions([white, black])
    #expect(looked.contains { $0.rep.color == .w } && looked.contains { $0.rep.color == .b })
    #expect(looked.allSatisfy { fenTurn($0.node.fenBefore) == $0.rep.color }, "only your moves")
    // The two Black move orders meet after 4...Nf6: that decision is one position.
    let nf6 = looked.filter { $0.rep.color == .b && $0.node.san == "Nf6" }
    #expect(Set(nf6.map(\.node.key)).count == nf6.count)
    #expect(choices(white).allSatisfy { $0.path.count >= 2 }, "two first moves are two openings")
  }

  /// Rule 2: a move counts when it transposes or heads toward your lines better than yours; a habit never does.
  @Test func findsTranspositionsNotHabits() throws {
    let white = rep(.w, WHITE)
    let qgd = try choice(white, "d4 d5 c4 e6")
    #expect(qgd.mine == "Nc3")
    #expect(qgd.options.map(\.san) == ["g3"])
    #expect(qgd.options[0].kind == .transposes)
    #expect(qgd.options[0].into == line("d4 Nf6 c4 e6 g3 d5"), "into the Catalan you have")
    #expect(qgd.removes == 7)
    #expect(try choice(white, "e4 e5 Nf3 Nf6").options.map(\.san) == ["Nc3"])
    // g3 after 1.c4 e5 is only a habit here: you play it in the Catalan, but it reaches no position you have.
    let habits = rep(.w, ["d4 Nf6 c4 e6 g3 d5 Bg2", "c4 c5 Nf3 Nc6 g3 g6 Bg2", "c4 e5 Nc3 Nf6 Nf3"])
    #expect(!choices(habits).contains { $0.path == line("c4 e5") })
    #expect(choices(white).flatMap(\.options).allSatisfy { $0.kind == .transposes || $0.kind == .heads })
  }

  /// Rule 3: the least loss is offered, never one clearly worse than yours; a position waits for every loss.
  @Test func evalPicksAndNeverWorse() throws {
    let white = rep(.w, WHITE)
    var c = try choice(white, "d4 d5 c4 e6")
    #expect(decide(white, bookIndex, c) { _, san in san == "g3" ? nil : 0 } == .waiting)
    #expect(decide(white, bookIndex, c) { _, san in san == "g3" ? CLEARLY_WORSE_CP + 1 : 0 } == .none)
    #expect(try find(white, c) { _, san in san == "g3" ? CLEARLY_WORSE_CP : 0 }.suggestion == "g3")
    // Two moves that would tidy it: the one giving up less wins, whatever its kind.
    c.options.append(TidyOption(san: "Nf3", kind: .heads, strength: 0.5, into: line("d4 d5 c4 e6 Nc3 Nf6")))
    #expect(try find(white, c) { _, san in san == "g3" ? 30 : 10 }.suggestion == "Nf3")
    #expect(try find(white, c) { _, san in san == "g3" ? 10 : 10 }.suggestion == "g3", "ties go to the better kind")
    #expect(movesToJudge(c) == ["Nc3", "g3", "Nf3"])
  }

  /// Rule 4: the target reaches your position and plays 3 of your moves on; the current line matches its length.
  @Test func cardLinesFromTheSplit() throws {
    let white = rep(.w, WHITE)
    let f = try find(white, try choice(white, "d4 d5 c4 e6"))
    #expect(f.target == line("g3 Nf6 Bg2 Be7 Nf3"))
    #expect(f.joins == 2, "g3 and the reply ...Nf6 reach your Catalan")
    #expect(f.target.count == f.joins + TIDY_KNOWN_STEPS)
    #expect(f.current == line("Nc3 Nf6 Bg5 Be7 e3"))
    // The stepper: both boards start at the split; the target turns known once it reaches you.
    #expect(tidyFrame(f, 0).currentFen == f.fen && tidyFrame(f, 0).targetFen == f.fen && !tidyFrame(f, 0).known)
    #expect(tidyFrame(f, 1).targetMove?.san == "g3" && tidyFrame(f, 1).currentMove?.san == "Nc3" && !tidyFrame(f, 1).known)
    #expect(tidyFrame(f, 2).known)
    // Fewer known moves: only what you have. A current line that ends first stops there.
    let short = rep(.w, ["d4 Nf6 c4 e6 g3 d5 Bg2", "d4 d5 c4 e6 Nc3"])
    let s = try find(short, try choice(short, "d4 d5 c4 e6"))
    #expect(s.target == line("g3 Nf6 Bg2"))
    #expect(s.current == ["Nc3"])
    #expect(tidyFrame(s, 3).currentMove == nil, "an ended current line stops, showing no move")
    #expect(tidyFrame(s, 3).currentFen == applySan(s.fen, "Nc3")?.after)
  }

  /// Rule 5: most moves removed first, then the earliest.
  @Test func biggestSavingsFirst() throws {
    let white = rep(.w, WHITE + ["d4 d5 c4 e6 Nc3 Nf6 cxd5 exd5 Bg5 c6 e3 Bf5 Qf3"])
    let finds = sortFinds(try choices(white).map { try find(white, $0) })
    #expect(finds.map(\.removes) == finds.map(\.removes).sorted(by: >))
    #expect(finds.first?.path == line("d4 d5 c4 e6"))
  }

  /// Rule 6: the switch replaces your move and its subtree, resets the card and misses there, and undoes.
  @Test func switchReplacesAndUndoes() throws {
    var state = AppState()
    let id = state.ensurePlaybook(.w)
    for l in WHITE { state.addLine(id, line(l), .fixed(.book)) }
    let rep0 = try #require(state.playbooks[id])
    let node = try #require(nodeAtLine(rep0, line("d4 d5 c4 e6 Nc3")))
    state.cards[cardId(id, node.key)] = createCard(cardId(id, node.key), id, node.key, node.fenBefore)
    state.mistakes = [Mistake(source: .play, playbookId: id, key: node.key, fen: node.fenBefore, played: "Nf3", expected: "Nc3")]
    let before = state
    let switched = state.tidySwitch(id, node.id, "g3")
    let undo = try #require(switched)
    let after = try #require(state.playbooks[id])
    #expect(nodeAtLine(after, line("d4 d5 c4 e6 Nc3")) == nil)
    #expect(nodeAtLine(after, line("d4 d5 c4 e6 g3"))?.preferred == true)
    #expect(after.nodes.count == rep0.nodes.count - 7 + 1)
    #expect(state.cards[cardId(id, node.key)] == nil)
    #expect(state.mistakes.isEmpty)
    state.undo(undo)
    #expect(state.playbooks == before.playbooks && state.cards == before.cards && state.mistakes == before.mistakes)
    #expect(state.tidySwitch(id, node.id, "Ke2") == nil, "an illegal move switches nothing")
  }
}
