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
      .prepComplete: 1, .blunderPunished: 3, .moment: 6, .mission: 6, .endgame: 3, .checkmate: 15,
      .streak: 1, .distance: 10, .heldDraw: 7,
      .endgameClear: 250, .endgameMission: 100, .endgameMastery: 500, .endgameTuneUp: 100, .endgameConverted: 100,
    ])
  }

  /// Rule 2: a clean prep pays a pawn for each prep move asked, however fast, out of the pot.
  @Test func prepPays() throws {
    let fast = prepRanOut(try prepPlayed([1, 2, 2.9]), bookIndex)
    #expect(awards(fast.effects) == [PawnAward(.prepComplete, .pot, count: 3)])
    #expect(fast.session.state.extras.pawns == 3)
    let slow = prepRanOut(try prepPlayed([1, 9, 1]), bookIndex)
    #expect(awards(slow.effects).map(\.count) == [3])
    // Prep that asked nothing, or was missed, pays nothing.
    #expect(prepPawns(misses: 0, times: []) == 0)
    #expect(prepPawns(misses: 1, times: [1, 1]) == 0)
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
    #expect(took.session.state.extras.pawns == 3)
    let missed = judgedMove(past, ctx, judged("Bxc6", lost: 51, before: 230, after: 179), 1, 0)
    #expect(!awards(missed.effects).contains { $0.event == .blunderPunished })
    let small = judgedMove(past, ctx, judged("Bxc6", lost: 0, before: 229, after: 229), 1, 0)
    #expect(!awards(small.effects).contains { $0.event == .blunderPunished })
    #expect(punished(.b, lastScored: 0, before: -200, lost: 0))
    #expect(!punished(.w, lastScored: nil, before: 500, lost: 0))
  }

  /// Rule 2: each prepared move found drops a pawn into the pot from its square; a miss drops none.
  @Test func preparedMovesFillThePot() throws {
    var s = try session()
    let e4 = try #require(applySan(s.state.run.fen, "e4"))
    let found = playPrepared(s, ctx, e4, 1, 0)
    #expect(found.effects.contains { if case .potPawn("e4") = $0 { true } else { false } })
    #expect(awards(found.effects).isEmpty, "nothing is paid until the prep completes")
    s = engineMove(found.session, "e5").session
    let wrong = judgedMove(s, ctx, judged("d4"), 1, 0)
    #expect(!wrong.effects.contains { if case .potPawn = $0 { true } else { false } })
    #expect(prepRanOut(wrong.session, bookIndex).effects.isEmpty)
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
    #expect(fast.session.state.extras.pawns == 3)
    var state = AppState()
    state.earn(fast.session.state.extras.pawns)
    #expect(state.pawns == 3)
  }

  /// Rule 7: the record keeps moves survived.
  @Test func bestsAreMovesSurvived() {
    let tree = openingTree(bookIndex)
    let record = recordRun(recordRun(RunRecord(), tree, line("e4 e5"), 12), tree, line("e4 e5"), 8)
    #expect(record.global.best == 12)
  }

  /// Rule 8: before today's game the ring shows the day it will make and what it will pay; after, the day it made.
  @Test func theStreakRingShowsToday() {
    let nine = PawnStreak(day: "d9", days: 9)
    #expect(streakToday(nine, today: "d10", yesterday: "d9") == StreakToday(day: 10, paid: false, pawns: 2))
    #expect(streakToday(nine, today: "d10", yesterday: "d9").weekday == 3)
    #expect(streakToday(nine, today: "d9", yesterday: "d8") == StreakToday(day: 9, paid: true, pawns: 2))
    #expect(streakToday(nine, today: "d12", yesterday: "d11") == StreakToday(day: 1, paid: false, pawns: 1))
    #expect(streakToday(PawnStreak(day: "d7", days: 7), today: "d7", yesterday: "d6").weekday == 7)
  }

  /// Rule 9: markers at 5, 10, 15 and 20 moves past prep pay 10, 15, 20, 20; Middlegame pays 40%.
  @Test func distanceMarkersPay() throws {
    #expect((1...4).map { distancePawns($0) } == [10, 15, 20, 20])
    #expect((1...4).map { distancePawns($0, middlegame: true) } == [4, 6, 8, 8])
    var s = prepRanOut(try session(at: line("e4 e5 Nf3 Nc6 Bb5 a6")), bookIndex).session
    var paid: [Int] = []
    for (mine, theirs) in [("Ba4", "Nf6"), ("O-O", "Be7"), ("Re1", "b5"), ("Bb3", "d6"), ("c3", "O-O"), ("h3", "Nb8")] {
      let step = judgedMove(s, ctx, judged(mine), 1, 0)
      paid += awards(step.effects).filter { $0.event == .distance }.map(\.count)
      s = engineMove(step.session, theirs).session
    }
    #expect(paid == [10])
    #expect(s.pastPrep == 6)
    // A move your prep had doesn't count.
    let prep = try session()
    let e4 = try #require(applySan(prep.state.run.fen, "e4"))
    #expect(playPrepared(prep, ctx, e4, 1, 0).session.pastPrep == 0)
  }

  /// Rule 10: a draw pays when you stood at −1.5 or worse after the prep.
  @Test func heldDrawsPay() throws {
    #expect(heldDraw(.w, afterPrep: -150) && heldDraw(.b, afterPrep: 200))
    #expect(!heldDraw(.w, afterPrep: -149) && !heldDraw(.w, afterPrep: nil))
    // Stalemate: White mates nothing; Black has no move.
    var held = try session()
    held.state.run.played = []
    held.state.run.fen = "7k/8/5Q2/8/8/8/8/K7 w - - 0 1"
    held.evalTrail = [-200, -300]
    held.state.extras.endgame = true
    let stale = engineMove(held, "Qf7")
    #expect(awards(stale.effects) == [PawnAward(.heldDraw, .board)])
    if case .draw = stale.session.ending {} else { Issue.record("not a draw") }
    held.evalTrail = [-100]
    #expect(awards(engineMove(held, "Qf7").effects).isEmpty, "not behind enough after the prep")
  }
}
