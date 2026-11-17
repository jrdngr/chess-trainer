import Game
import Model
import Testing

/// Measuring earnings: each run's counted events, at their values, are exactly the pawns the
/// run put on the balance, the streak aside.
@MainActor @Test func measuredRunsAccountForEveryPawn() async throws {
  try await headless(everything: false) { app in
    let before = app.state.pawns
    let runs = try await app.measure(MeasureOptions(strategy: .full, rating: 1200, runs: 3, maxMoves: 30), seed: 1)
    #expect(runs.count == 3)
    for run in runs {
      let valued = run.events.reduce(0) { $0 + pawnsFor(PawnEvent(rawValue: $1.key)!) * $1.value }
      #expect(valued == run.pawns)
      #expect(run.prepMoves + run.growthMoves + run.otherMoves > 0)
      #expect(run.ending != "none")
    }
    let streak = app.state.events.filter { $0.kind == "pawns" && $0.source == PawnEvent.streak.rawValue }.reduce(0) { $0 + ($1.count ?? 0) }
    #expect(app.state.pawns - before == runs.reduce(0) { $0 + $1.pawns } + streak)
  }
}

/// Prep only: the bot plays its prep, grows when growth opens, and ends the run with the X.
@MainActor @Test func prepOnlyRunsStopWhenThePrepDoes() async throws {
  try await headless(everything: false) { app in
    let runs = try await app.measure(MeasureOptions(strategy: .prepOnly, rating: 1200, runs: 3), seed: 1)
    for run in runs {
      #expect(run.ending == "ended")
      #expect(run.otherMoves == 0 && run.prepMoves > 0)
    }
  }
}
