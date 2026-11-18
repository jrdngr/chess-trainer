import ChessCore
import Game
import Model
import Testing

/// Home with the Classical starter set, White, Drill.
@MainActor private func drillAsWhite(_ app: HeadlessApp) async throws {
  onboard(app)
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

/// A round leaves a trail in the event log: its start, each move with its judgement, the
/// pawns it paid and its end.
@MainActor @Test func aRoundIsLogged() async throws {
  try await headless { app in
    try await drillAsWhite(app)
    let id = try #require(app.run).run.id
    try await playPrep(app)
    await app.endRound()
    let mine = app.state.events.filter { $0.game == id }
    let kinds = mine.map(\.kind)
    for kind in ["game-start", "prep-answer", "end-round", "game-end"] {
      #expect(kinds.contains(kind), "\(kind) is logged")
    }
    #expect(kinds.first == "game-start")
    let answer = try #require(mine.first { $0.kind == "prep-answer" })
    #expect(answer.san != nil && answer.fen != nil)
    let paid = app.state.events.filter { $0.kind == "pawns" }
    #expect(paid.contains { $0.source == "prepComplete" && ($0.count ?? 0) >= 1 })
  }
}

/// A clean prep pays pawns onto the balance as it runs out, and the day's first finished game pays the streak,
/// which waits to pop out of the streak ring on Home.
@MainActor @Test func aCleanPrepPaysPawns() async throws {
  try await headless { app in
    try await drillAsWhite(app)
    let before = app.state.pawns
    _ = app.takeSignals()
    try await playPrep(app)
    let paid = app.signals.compactMap { if case .pawns(let award) = $0 { return award } else { return nil } }
    let asked = try #require(app.run).session.prepTimes.count
    let prep = paid.filter { $0.event == .prepComplete }
    #expect(prep.reduce(0) { $0 + $1.count } == asked, "a pawn for each prep move asked")
    let last = try #require(prep.first)
    if case .square = last.source {} else { Issue.record("the last prep move's pawn goes straight to the counter, not \(last.source)") }
    #expect(last.count == 1)
    if asked > 1 { #expect(prep.dropFirst().first == PawnAward(.prepComplete, .pot, count: asked - 1), "the pot pays the rest") }
    let earned = try #require(app.run).session.state.extras.pawns
    #expect(earned == paid.reduce(0) { $0 + $1.count } && earned >= 1)
    #expect(app.state.pawns == before + earned)

    await app.endRound()
    #expect(app.state.pawns == before + earned + 10, "the day's first game pays the streak")
    #expect(app.state.pawnStreak.days == 1)
    #expect(app.store.streakWaiting == 10 && app.store.shownPawns == app.state.pawns - 10 - app.store.pawnDrops.reduce(0) { $0 + $1.flying },
            "the streak pawn waits for Home before the counter shows it")

    app.store.showStreakPawns()
    #expect(app.store.streakWaiting == 0)
    #expect(app.store.pawnDrops.last?.award == PawnAward(.streak, .streak, count: 10), "it pops out of the streak ring")
  }
}

/// Under the counter, the first pawn of each award to land says why it was paid; pawns going into the pot say nothing.
@MainActor @Test func landingPawnsSayWhyTheyWerePaid() async throws {
  try await headless { app in
    try await drillAsWhite(app)
    app.store.dropInPot("e4")
    let toPot = try #require(app.store.pawnDrops.last)
    app.store.landed(toPot.id)
    #expect(app.store.pawnReason == nil, "a pawn into the pot isn't paid yet")
    app.store.pay(PawnAward(.blunderPunished, .square("d5"), count: 3))
    let drop = try #require(app.store.pawnDrops.last)
    app.store.landed(drop.id)
    #expect(app.store.pawnReason == PawnReason(text: "Blunder punished", id: drop.id))
    app.store.pay(PawnAward(.checkmate, .board, count: 15))
    let mate = try #require(app.store.pawnDrops.last)
    app.store.landed(drop.id)
    #expect(app.store.pawnReason?.text == "Blunder punished", "only the first pawn of an award names it")
    app.store.landed(mate.id)
    #expect(app.store.pawnReason?.text == "Checkmate")
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
    #expect(app.run?.tip == .missedMove,
            "the miss says to remember the move")
  }
}

/// Past the prep, a move that hangs the queen ends the run on the blunder, with the threat to show,
/// and Continue goes on to the end screen. The game's history ends on the move that lost.
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
    guard case .blunder(let played, _, let lost, _, _) = run.session.ending else {
      Issue.record("the run didn't end on a blunder")
      return
    }
    #expect(lost >= 80)
    #expect(run.blunder?.threat != nil)
    app.continueToEnd()
    #expect(app.run?.phase == .over)
    let game = try #require(app.state.games.last)
    #expect(game.moves == run.run.played + [played], "the history keeps the move that lost")
  }
}

/// With 500 pawns, a blunder holds the board: Continue takes it back for them, once, and the run
/// goes on; the record counts only the moves before it.
@MainActor @Test func continueTakesABlunderBack() async throws {
  try await headless { app in
    try await drillAsWhite(app)
    app.store.update { $0.pawns = 1_000 }
    try await playPrep(app)
    for _ in 0..<20 {
      guard let run = app.run, run.live else { break }
      let hang = try #require(hangingQueenMove(run.run.fen) ?? quietMove(run.run.fen))
      try await app.move(hang)
    }
    let run = try #require(app.run)
    #expect(run.phase == .blunder && run.canContinue)
    #expect(run.finish == nil, "the run isn't over while Continue can take it back")
    let fen = run.run.fen
    let threat = try #require(run.blunder?.threat)
    let pawns = app.state.pawns
    try await app.buyContinue()
    #expect(app.state.pawns == pawns - CONTINUE_PRICE)
    #expect(run.live && run.run.fen == fen, "the blunder is taken back")
    #expect(run.takenBack?.threat?.to == threat.to, "its threat stays drawn")
    #expect(!run.canContinue)
    let counted = run.session.state.moves
    for _ in 0..<20 {
      guard let run = app.run, run.live else { break }
      let hang = try #require(hangingQueenMove(run.run.fen) ?? quietMove(run.run.fen))
      try await app.move(hang)
    }
    #expect(run.phase == .blunder && run.finish != nil, "a second blunder ends the run")
    #expect(app.state.runRecord.global.best == counted)
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
    onboard(app)
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
    onboard(app, recommended: false)
    await app.openPlay()
    let run = try #require(app.run)
    #expect(run.firstGame && run.fill != nil)
    #expect(run.tip == .growth, "growth's tip shows as the fill opens")
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

/// A Drill run heading for a gap with none of your moves on its line past White's first starts at
/// the gap, the moves to it played for you, and opens growth there at once. Never at move one.
@MainActor @Test func aGapRunWithNothingOnItsLineStartsAtTheGap() async throws {
  try await headless { app in
    onboard(app, recommended: false)
    app.store.update { state in
      let id = state.ensurePlaybook(.w)
      state.addLine(id, ["c4", "e5", "g3"], .fixed(.book))
      for _ in 0..<4 { state.answered(id, START_FEN, "c4", .easy) }
      if let english = deepestNodeAlong(app.tree, ["c4", "e5", "g3"]) {
        state.form.openings[english.id] = Array(repeating: 1, count: FORM_MIN_ANSWERS)
      }
      let selection = Selection(color: .w, opening: ANY_OPENING)
      let after = lastAddedAt(state.playbookList) + 1
      for i in 0..<CURVE_LEVEL_GAMES[1]! {
        state.recordGame(GameRecord(
          id: "g\(i)", mode: .play, at: after + Double(i), color: .w, picked: selection, opening: selection.opening, moves: ["c4"],
          result: "*", termination: "ended"))
      }
    }
    try app.select(side: .w, start: .drill)
    let gap = try #require(steerGap(app.state, app.tree, app.state.settings.selection))
    #expect(gap.path == ["c4"])
    await app.openPlay()
    let run = try #require(app.run)
    #expect(run.run.played == gap.line, "it opens at the reply you have no answer to")
    #expect(run.fill != nil, "growth is open")
  }
}

/// A Drill run on the Ruy Lopez, e4 e5 Nf3 Nc6 Bb5, with every move known well and no answer
/// past it: growth is due at the end of the prep.
@MainActor private func ruyLopezWithGrowthDue(_ app: HeadlessApp) async throws {
  onboard(app, recommended: false)
  let moves = ["e4", "e5", "Nf3", "Nc6", "Bb5"]
  app.store.update { state in
    state.unlocked.insert(ShopFeature.openingPicker.rawValue)
    let id = state.ensurePlaybook(.w)
    state.addLine(id, moves, .fixed(.book))
    let fens = walkSan(moves).fens
    for _ in 0..<4 { for i in stride(from: 0, to: moves.count, by: 2) { state.answered(id, fens[i], moves[i], .easy) } }
    let selection = Selection(color: .w, opening: ANY_OPENING)
    let after = lastAddedAt(state.playbookList) + 1
    for i in 0..<5 {
      state.recordGame(GameRecord(
        id: "g\(i)", mode: .play, at: after + Double(i), color: .w, picked: selection, opening: selection.opening,
        moves: moves, result: "*", termination: "ended"))
    }
  }
  try app.select(side: .w, start: .drill, opening: "e4 e5 Nf3 Nc6 Bb5")
  #expect(steerGap(app.state, app.tree, app.state.settings.selection)?.path == moves)
  await app.openPlay()
}

/// When growth is due, the prep's pot waits for a move added: one pays it out of the pot.
@MainActor @Test func dueGrowthHoldsThePrepPawnUntilAMoveIsAdded() async throws {
  try await headless { app in
    try await ruyLopezWithGrowthDue(app)
    let before = app.state.pawns
    try await playPrep(app)
    let run = try #require(app.run)
    #expect(app.callouts.contains("Prep complete"))
    #expect(run.fill != nil, "growth opens where the prep ran out")
    #expect(run.heldPrepPawn?.event == .prepComplete)
    let held = try #require(run.heldPrepPawn).count
    #expect(held == run.session.prepTimes.count && run.pot == held, "the pot holds a pawn for each prep move")
    #expect(run.tip == .growth || run.tip == .growthPawn)
    #expect(app.state.pawns == before, "nothing paid yet")

    let pick = try #require(app.choices.first)
    _ = app.takeSignals()
    try await app.move(pick)
    let paid = app.signals.compactMap { if case .pawns(let award) = $0 { return award } else { return nil } }
    #expect(paid.first?.source == .pot, "they fly out of the pot")
    #expect(app.run?.heldPrepPawn == nil && app.run?.pot == 0)
    #expect(app.state.pawns == before + held)
  }
}

/// Done with nothing added drains the pot.
@MainActor @Test func doneWithNothingAddedLosesThePrepPawn() async throws {
  try await headless { app in
    try await ruyLopezWithGrowthDue(app)
    let before = app.state.pawns
    try await playPrep(app)
    #expect(app.run?.heldPrepPawn != nil)
    let held = try #require(app.run?.pot)
    await app.doneAdding()
    #expect(app.run?.heldPrepPawn == nil)
    #expect(app.run?.pot == 0 && app.run?.potDrain?.count == held)
    #expect(app.state.pawns == before)
    #expect(app.run?.session.state.extras.pawns == 0, "the run's score leaves it out")
  }
}

/// A Drill run is named by the opening it tests, not the position it starts in.
@MainActor @Test func aDrillRunIsNamedByTheOpeningItTests() async throws {
  try await headless { app in
    onboard(app, recommended: false)
    app.store.update { state in
      let id = state.ensurePlaybook(.w)
      state.addLine(id, ["e4", "e5", "Nf3", "Nc6", "Bb5"], .fixed(.book))
    }
    try app.select(side: .w, start: .drill)
    await app.openPlay()
    let run = try #require(app.run)
    #expect(run.run.played == ["e4", "e5"], "it starts at 2.Nf3, your first move past move one")
    #expect(run.headerName == "Ruy Lopez")
  }
}

/// A run is named by its opening's family, or by the book's name with the family over it when Settings asks.
@MainActor @Test func aRunIsNamedByFamilyUnlessBookNamesAreOn() async throws {
  try await headless { app in
    onboard(app, recommended: false)
    app.store.update { state in
      let id = state.ensurePlaybook(.w)
      state.addLine(id, ["e4", "c5", "Nf3", "d6", "d4", "cxd4", "Nxd4", "Nf6", "Nc3", "a6", "Be3"], .fixed(.book))
    }
    try app.select(side: .w, start: .drill)
    await app.openPlay()
    let run = try #require(app.run)
    #expect(run.headerName == "Sicilian Defence")
    #expect(run.headerFamily == nil, "the family is the name, so nothing over it")
    app.settings { $0.openingNames = .book }
    #expect(run.headerName != "Sicilian Defence", "the book names the variation")
    #expect(run.headerFamily == "Sicilian Defence")
  }
}
