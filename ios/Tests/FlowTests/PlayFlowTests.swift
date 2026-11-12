import ChessCore
import Game
import Model
import Testing

/// Home with the Classical starter set, White, Drill.
@MainActor private func drillAsWhite(_ app: HeadlessApp) async throws {
  try app.skipTutorial(starter: "classical")
  try app.select(side: .w, start: .drill)
  await app.openPlay()
}

/// Play every prepared move until the prep runs out.
@MainActor private func playPrep(_ app: HeadlessApp) async throws {
  while let run = app.run, run.live, let next = run.prepNow.first { try await app.move(next) }
}

/// A Drill round: it starts on a move of yours past move one, scores each prepared move,
/// says when the prep is done, and an ended round goes into the history and counts for the next.
@MainActor @Test func drillRoundScoresPrepAndIsRecorded() async throws {
  try await headless { app in
    try await drillAsWhite(app)
    let run = try #require(app.run)
    #expect(run.run.played.isEmpty == false, "a Drill run never starts from White's move one")
    #expect(run.myTurn && !run.prepNow.isEmpty, "it starts on one of your prepared moves")
    #expect(run.label == .on)

    _ = app.takeSignals()
    try await playPrep(app)
    let pops = app.signals.compactMap { if case .pop(let pop) = $0 { return pop } else { return nil } }
    #expect(!pops.isEmpty && pops.allSatisfy(\.found), "every prepared move is ticked")
    #expect(app.callouts.contains("Prep complete"))
    #expect(app.run?.label != .on)

    await app.endRound()
    let finish = try #require(app.run?.finish)
    #expect(finish.how == .ended)
    let game = try #require(app.state.games.last)
    #expect(game.mode == .play && game.moves == app.moves)

    let before = app.store.autoHistory.focuses.count
    try await app.next()
    #expect(app.store.autoHistory.focuses.count == before + 1, "the finished round counts toward the next one's start")
    #expect(app.run?.finish == nil && app.run?.live == true)
  }
}

/// A wrong move on your prep shows the prepared one, fails its card and logs the mistake.
@MainActor @Test func missingAPreparedMoveShowsItAndLogsIt() async throws {
  try await headless { app in
    try await drillAsWhite(app)
    let run = try #require(app.run)
    let fen = run.run.fen
    let expected = try #require(run.prepNow.first)
    let wrong = try #require(legalMoves(fen).first { !run.prepNow.contains($0.san) })
    _ = app.takeSignals()
    try await app.move(wrong.san)

    let miss = app.signals.compactMap { if case .miss(let m) = $0 { return m } else { return nil } }.first
    #expect(miss?.expected == expected)
    #expect(app.state.mistakes.contains { $0.fen == fen && $0.played == wrong.san && $0.expected == expected })
    #expect(app.run?.label == .off)
  }
}

/// Past the prep, a move that hangs the queen ends the run on the blunder, with the threat to show,
/// and Continue goes on to the end screen.
@MainActor @Test func aBlunderEndsTheRun() async throws {
  try await headless { app in
    try await drillAsWhite(app)
    try await playPrep(app)
    for _ in 0..<20 {
      guard let run = app.run, run.live else { break }
      let hang = try #require(hangingQueenMove(run.run.fen) ?? quietMove(run.run.fen))
      try await app.move(hang)
    }
    let run = try #require(app.run)
    #expect(run.phase == .blunder)
    guard case .blunder(_, _, let lost, _, _) = run.session.ending else {
      Issue.record("the run didn't end on a blunder")
      return
    }
    #expect(lost >= 80)
    #expect(run.blunder?.threat != nil)
    app.continueToEnd()
    #expect(app.run?.phase == .over)
  }
}

/// A queen move to a square an enemy piece takes for free, if there is one.
private func hangingQueenMove(_ fen: String) -> String? {
  legalMoves(fen).first { move in
    move.piece == .q && move.captured == nil
      && legalMoves(move.after).contains { $0.to == move.to }
      && !legalMoves(move.after).contains { $0.to == move.to && $0.piece == .q }
  }?.san
}

/// A quiet move that keeps the queen at home, to bring it out next.
private func quietMove(_ fen: String) -> String? {
  legalMoves(fen).first { $0.piece == .p && $0.captured == nil }?.san ?? legalMoves(fen).first?.san
}

/// Freeform starts from move one: nothing is played for you.
@MainActor @Test func freeformStartsFromMoveOne() async throws {
  try await headless { app in
    try app.skipTutorial(starter: "classical")
    try app.select(side: .w, start: .freeform)
    await app.openPlay()
    let run = try #require(app.run)
    #expect(run.run.played.isEmpty)
    #expect(run.round?.free == true)
  }
}

/// With an empty Playbook, Play's first game adds moves from move one: each pick goes into the
/// Playbook and is played, Undo takes the last one out, and the game goes on once the fill is done.
@MainActor @Test func firstGameGrowsThePlaybookFromMoveOne() async throws {
  try await headless { app in
    try app.skipTutorial()
    await app.openPlay()
    let run = try #require(app.run)
    #expect(run.firstGame && run.fill != nil)
    #expect(app.choices.contains("e4"))

    try await app.move("e4")
    let white = { app.state.playbookList.first { $0.color == .w } }
    #expect(white().flatMap { nodeAtLine($0, ["e4"]) } != nil)
    #expect(app.moves.count == 2, "the opponent replies to the added move")

    let second = try #require(app.choices.first)
    try await app.move(second)
    #expect(white().flatMap { nodeAtLine($0, Array(app.moves.prefix(3))) } != nil)
    await app.undo()
    #expect(app.moves.count == 2)
    #expect(white().flatMap { nodeAtLine($0, ["e4", app.moves[1], second]) } == nil, "Undo takes the move out of the Playbook")
  }
}
