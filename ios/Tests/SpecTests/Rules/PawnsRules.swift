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
      .prepComplete: 1, .blunderPunished: 3, .moment: 6, .mission: 6, .endgame: 3, .checkmate: 100,
      .streak: 1, .distance: 20, .heldDraw: 20,
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

  /// Rule 4: a mate pays 100, less 2 for each of your moves under endgame rules before it, down to 25.
  @Test func aQuickMatePaysMore() throws {
    #expect([0, 1, 10, 25, 37, 38, 100].map { winPawns(endgameMoves: $0) } == [100, 98, 80, 50, 26, 25, 25])
    // King and queen against king: one quiet move, then mate.
    var s = try session()
    s.state.run.played = []
    s.state.run.fen = "7k/8/6K1/8/8/8/8/5Q2 w - - 0 1"
    s.state.extras.endgame = true
    s = judgedMove(s, ctx, judged("Qe2"), 1, 0).session
    #expect(s.endgameMoves == 1)
    s = engineMove(s, "Kg8").session
    let mate = judgedMove(s, ctx, judged("Qe8#"), 1, 0)
    #expect(awards(mate.effects).filter { $0.event == .checkmate }.map(\.count) == [98])
  }

  /// Rule 5: 10 more each day, up to 90; a missed day starts again.
  @Test func theStreakClimbsDaily() {
    #expect([1, 2, 5, 8, 9, 10, 100].map(streakPawns) == [10, 20, 50, 80, 90, 90, 90])
    var streak = PawnStreak()
    var paid: [Int] = []
    for day in 1...10 {
      let d = streakDay(streak, today: "d\(day)", yesterday: "d\(day - 1)")
      streak = d.streak
      paid.append(d.pawns)
    }
    #expect(paid == [10, 20, 30, 40, 50, 60, 70, 80, 90, 90])
    #expect(streakDay(streak, today: "d10", yesterday: "d9").pawns == 0)
    let missed = streakDay(streak, today: "d12", yesterday: "d11")
    #expect(missed.streak.days == 1 && missed.pawns == 10)
  }

  /// Rule 5: the first finished game of a day pays onto the balance.
  @Test func finishingAGamePaysTheDay() {
    var state = AppState()
    let noon = 1_790_000_000_000.0
    #expect(state.finishedGame(now: noon) == 10)
    #expect(state.finishedGame(now: noon + 1000) == 0)
    #expect(state.finishedGame(now: noon + DAY) == 20)
    #expect(state.pawns == 30 && state.pawnStreak.days == 2)
    #expect(state.finishedGame(now: noon + 4 * DAY) == 10)
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
    #expect(streakToday(nine, today: "d10", yesterday: "d9") == StreakToday(day: 10, paid: false, pawns: 90))
    #expect(streakToday(nine, today: "d10", yesterday: "d9").weekday == 3)
    #expect(streakToday(nine, today: "d9", yesterday: "d8") == StreakToday(day: 9, paid: true, pawns: 90))
    #expect(streakToday(nine, today: "d12", yesterday: "d11") == StreakToday(day: 1, paid: false, pawns: 10))
    #expect(streakToday(PawnStreak(day: "d7", days: 7), today: "d7", yesterday: "d6").weekday == 7)
    // A frozen day shows icy in its week.
    let kept = PawnStreak(day: "d9", days: 9, frozen: [3, 9])
    #expect(streakToday(kept, today: "d10", yesterday: "d9").frozen == [2])
  }

  /// Rule 9: markers at 5, 10, 15 and 20 moves past prep pay 20 each; Middlegame pays 40%.
  /// They stop under endgame rules and after the run's 10th.
  @Test func distanceMarkersPay() throws {
    #expect((1...4).map { distancePawns($0) } == [20, 20, 20, 20])
    #expect((1...4).map { distancePawns($0, middlegame: true) } == [8, 8, 8, 8])
    var s = prepRanOut(try session(at: line("e4 e5 Nf3 Nc6 Bb5 a6")), bookIndex).session
    var paid: [Int] = []
    var from: [PawnSource] = []
    for (mine, theirs) in [("Ba4", "Nf6"), ("O-O", "Be7"), ("Re1", "b5"), ("Bb3", "d6"), ("c3", "O-O"), ("h3", "Nb8")] {
      let step = judgedMove(s, ctx, judged(mine), 1, 0)
      paid += awards(step.effects).filter { $0.event == .distance }.map(\.count)
      from += awards(step.effects).filter { $0.event == .distance }.map(\.source)
      s = engineMove(step.session, theirs).session
    }
    #expect(paid == [20])
    #expect(from == [.marker])
    #expect(s.pastPrep == 6)
    // The header's bar counts toward the next marker: one move past the first, the second pays 20 too.
    #expect(nextMarker(s.pastPrep) == (1, 20))
    #expect(nextMarker(4) == (4, 20) && nextMarker(14, middlegame: true) == (4, 8))
    // A move your prep had doesn't count.
    let prep = try session()
    let e4 = try #require(applySan(prep.state.run.fen, "e4"))
    #expect(playPrepared(prep, ctx, e4, 1, 0).session.pastPrep == 0)
    // The 10th marker is the last.
    var last = s
    last.pastPrep = 49
    let tenth = judgedMove(last, ctx, judged("d4"), 1, 0)
    #expect(awards(tenth.effects).filter { $0.event == .distance }.map(\.count) == [20])
    #expect(tenth.session.pastPrep == 50)
    let after = judgedMove(engineMove(tenth.session, "Nd7").session, ctx, judged("d5"), 1, 0)
    #expect(after.session.pastPrep == 50 && awards(after.effects).isEmpty)
    // Under endgame rules no move counts.
    var ending = s
    ending.state.extras.endgame = true
    #expect(judgedMove(ending, ctx, judged("d4"), 1, 0).session.pastPrep == 6)
  }

  /// Rule 10: a draw pays 20 when, under endgame rules, you stood at −3 or worse.
  @Test func heldDrawsPay() throws {
    #expect(heldDraw(low: -300) && !heldDraw(low: -299) && !heldDraw(low: nil))
    // Your worst score under endgame rules is kept from your side, before and after your moves.
    var black = try session(at: line("e4 e5 Nf3 Nc6 Bb5"))
    black.state.run.color = .b
    black.state.extras.endgame = true
    let low = judgedMove(black, ctx, judged("a6", before: 320, after: 250), 1, 0).session
    #expect(low.endgameLow == -320)
    // Stalemate: White mates nothing; Black has no move.
    var held = try session()
    held.state.run.played = []
    held.state.run.fen = "7k/8/5Q2/8/8/8/8/K7 w - - 0 1"
    held.state.extras.endgame = true
    held.endgameLow = -300
    let stale = engineMove(held, "Qf7")
    #expect(awards(stale.effects) == [PawnAward(.heldDraw, .board, count: 20)])
    if case .draw = stale.session.ending {} else { Issue.record("not a draw") }
    held.endgameLow = -150
    #expect(awards(engineMove(held, "Qf7").effects).isEmpty, "never lost enough under endgame rules")
  }

  /// Rule 11: freezes cover missed days on their own, oldest first, and count toward the length.
  @Test func freezesKeepTheStreak() {
    let past = ["d9", "d8", "d7", "d6"]
    let held = PawnStreak(day: "d7", days: 7, freezes: 2)
    // Missed d8 and d9: both frozen, today is day 10.
    let played = streakDay(held, today: "d10", past: past)
    #expect(played.streak.days == 10 && played.streak.freezes == 0 && played.pawns == 90)
    #expect(played.streak.frozen == [8, 9])
    // One freeze for two missed days: d8 frozen, d9 still missed, so a repair is offered.
    let one = PawnStreak(day: "d7", days: 7, freezes: 1)
    #expect(repairOffered(one, today: "d10", past: past))
    #expect(streakToday(one, today: "d10", past: past).repairable)
    #expect(streakDay(one, today: "d10", past: past).streak.days == 1, "playing without the repair starts again")
    // Three missed days with no freeze: gone.
    #expect(!repairOffered(PawnStreak(day: "d6", days: 6), today: "d10", past: past))
  }

  /// Rule 11: freezes cost 1,000, hold 2; a repair costs 2,000 and pays nothing for the missed day.
  @Test func freezesAndRepairsCostPawns() {
    var state = AppState()
    state.pawns = 2_500
    let first = state.buyFreeze(), second = state.buyFreeze(), third = state.buyFreeze()
    #expect(first && second)
    #expect(!third, "2 at most")
    #expect(state.pawns == 500 && state.pawnStreak.freezes == 2)

    var missed = AppState()
    let noon = 1_790_000_000_000.0
    _ = missed.finishedGame(now: noon)
    _ = missed.finishedGame(now: noon + DAY)
    missed.pawns = 2_000
    let early = missed.repairStreak(now: noon + 2 * DAY)
    #expect(!early, "nothing missed yet")
    let repaired = missed.repairStreak(now: noon + 3 * DAY)
    #expect(repaired)
    #expect(missed.pawns == 0 && missed.pawnStreak.days == 3 && missed.pawnStreak.frozen == [3])
    let today = missed.finishedGame(now: noon + 3 * DAY)
    #expect(today == 40, "today is day 4")
  }
}
