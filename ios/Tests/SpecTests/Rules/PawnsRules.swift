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

private func judged(_ san: String, lost: Double = 0, before: Double = 0, after: Double = 0) -> Judgement {
  Judgement(san: san, ok: true, lost: lost, best: san, before: before, after: after, moment: false, found: false, reply: nil)
}

private func awards(_ effects: [Effect]) -> [PawnAward] {
  effects.compactMap { if case .pawns(let award) = $0 { award } else { nil } }
}

/// The Ruy Lopez prep played through, with these times for White's three moves.
private func prepPlayed(_ times: [Double]) throws -> RunSession {
  var s = try session()
  let line = line("e4 e5 Nf3 Nc6 Bb5 a6")
  for (i, san) in line.enumerated() {
    let move = try #require(applySan(s.state.run.fen, san))
    if i % 2 == 0 {
      s = playPrepared(s, ctx, move, times[i / 2], 0).session
    } else {
      s = engineMove(s, san).session
    }
  }
  return s
}

@Suite("docs/rules/pawns.md") struct PawnsRules {
  /// Rule 1.
  @Test func whatEachEventPays() {
    let paid = Dictionary(uniqueKeysWithValues: PawnEvent.allCases.map { ($0, pawnsFor($0)) })
    #expect(paid == [
      .prepComplete: 1, .fastPrep: 1, .blunderPunished: 1, .moment: 2, .mission: 2, .endgame: 1, .checkmate: 3,
      .endgameGoal: 1, .streak: 1,
    ])
  }

  /// Rule 2: a clean prep pays, and one more when every answer was fast.
  @Test func prepPays() throws {
    let fast = prepRanOut(try prepPlayed([1, 2, 2.9]), bookIndex)
    #expect(awards(fast.effects).map(\.event) == [.prepComplete, .fastPrep])
    #expect(awards(fast.effects).allSatisfy { $0.source == .prep })
    #expect(fast.session.state.extras.pawns == 2)
    let slow = prepRanOut(try prepPlayed([1, 3, 1]), bookIndex)
    #expect(awards(slow.effects).map(\.event) == [.prepComplete])
    // Prep that asked nothing, or was missed, pays nothing.
    #expect(prepPawns(misses: 0, times: []).isEmpty)
    #expect(prepPawns(misses: 1, times: [1]).isEmpty)
    var missed = try session(at: line("e4 e5 Nf3 Nc6 Bb5 a6"))
    missed.prepStatus = .off
    #expect(prepRanOut(missed, bookIndex).effects.isEmpty)
  }

  /// Rule 3: their move threw away 200 or more and your reply kept it.
  @Test func blundersPunishedPay() throws {
    var past = prepRanOut(try session(at: line("e4 e5 Nf3 Nc6 Bb5 a6")), bookIndex).session
    past.lastScored = 30
    let took = judgedMove(past, ctx, judged("Bxc6", lost: 50, before: 230, after: 220), 1, 0)
    #expect(awards(took.effects).contains { $0.event == .blunderPunished && $0.source == .square("c6") })
    #expect(took.session.state.extras.pawns == 1)
    let missed = judgedMove(past, ctx, judged("Bxc6", lost: 51, before: 230, after: 179), 1, 0)
    #expect(!awards(missed.effects).contains { $0.event == .blunderPunished })
    let small = judgedMove(past, ctx, judged("Bxc6", lost: 0, before: 229, after: 229), 1, 0)
    #expect(!awards(small.effects).contains { $0.event == .blunderPunished })
    #expect(punished(.b, lastScored: 0, before: -200, lost: 0))
    #expect(!punished(.w, lastScored: nil, before: 500, lost: 0))
  }

  /// Rule 4: the endgame pays once; checkmate pays the side that gives it, from the mated king.
  @Test func endgameAndMatePay() throws {
    // Fool's mate, played as Black: the mate is yours.
    var black = try session()
    black.state.run.color = .b
    for san in line("f3 e5 g4") { black = engineMove(black, san).session }
    let mate = judgedMove(black, ctx, judged("Qh4#"), 1, 0)
    #expect(awards(mate.effects).contains { $0.event == .checkmate && $0.source == .square("e1") })
    if case .won = mate.session.ending {} else { Issue.record("not won") }
    // Taken by White: nothing.
    var white = try session()
    for san in line("f3 e5 g4") { white = engineMove(white, san).session }
    let taken = engineMove(white, "Qh4#")
    #expect(awards(taken.effects).isEmpty)

    // Rooks off into a king and rook ending: paid on the move that gets there, and not again.
    var rooks = try session()
    rooks.state.run.played = []
    rooks.state.run.fen = "r3k3/8/8/8/8/8/8/R3K2R w - - 0 1"
    let reached = engineMove(rooks, "Kf1")
    #expect(awards(reached.effects).map(\.event) == [.endgame])
    #expect(reached.session.state.extras.endgame)
    #expect(awards(engineMove(reached.session, "Kd8").effects).isEmpty)
  }

  /// Rule 5: a week at a time, up to 5 a day; a missed day starts again.
  @Test func theStreakPaysByTheWeek() {
    #expect([1, 7, 8, 14, 15, 22, 28, 29, 100].map(streakPawns) == [1, 1, 2, 2, 3, 4, 4, 5, 5])
    var streak = PawnStreak()
    var paid: [Int] = []
    for day in 1...9 {
      let d = streakDay(streak, today: "d\(day)", yesterday: "d\(day - 1)")
      streak = d.streak
      paid.append(d.pawns)
    }
    #expect(paid == [1, 1, 1, 1, 1, 1, 1, 2, 2])
    #expect(streakDay(streak, today: "d9", yesterday: "d8").pawns == 0)
    let missed = streakDay(streak, today: "d11", yesterday: "d10")
    #expect(missed.streak.days == 1 && missed.pawns == 1)
  }

  /// Rule 5: the first finished game of a day pays onto the balance.
  @Test func finishingAGamePaysTheDay() {
    var state = AppState()
    let noon = 1_790_000_000_000.0
    #expect(state.finishedGame(now: noon) == 1)
    #expect(state.finishedGame(now: noon + 1000) == 0)
    #expect(state.finishedGame(now: noon + DAY) == 1)
    #expect(state.pawns == 2 && state.pawnStreak.days == 2)
    #expect(state.finishedGame(now: noon + 3 * DAY) == 1)
    #expect(state.pawnStreak.days == 1)
  }

  /// Rule 6: the run's score is what its events paid.
  @Test func theRunsScoreIsItsPawns() throws {
    let fast = prepRanOut(try prepPlayed([1, 1, 1]), bookIndex)
    #expect(fast.session.state.extras.pawns == 2)
    var state = AppState()
    state.earn(fast.session.state.extras.pawns)
    #expect(state.pawns == 2)
  }

  /// Rule 7: the record keeps moves survived.
  @Test func bestsAreMovesSurvived() {
    let tree = openingTree(bookIndex)
    let record = recordRun(recordRun(RunRecord(), tree, line("e4 e5"), 12), tree, line("e4 e5"), 8)
    #expect(record.global.best == 12)
  }
}
