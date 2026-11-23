import Book
import ChessCore
import Shared

/// A run (Play's too) as a pure controller: `state + event →
/// state + effects`. The screen owns
/// timing, the engine and the store; it feeds each thing that happens in and
/// carries out the effects in order.

/// How a run ended.
public enum Ending: Equatable, Sendable {
  /// `played` is the move that lost, not on the board; `line` the engine's moves after it that show why, as UCI,
  /// the threat first. In an endgame, `slip` is the result it gave away.
  case blunder(played: String, best: String?, lost: Double, line: [String], slip: ResultSlip?)
  case won, lost, draw
  /// You ended it yourself.
  case ended
}

/// An endgame result a move gave away: from a win to a draw, say.
public struct ResultSlip: Equatable, Sendable {
  public var from: EndResult
  public var to: EndResult
  public init(from: EndResult, to: EndResult) {
    self.from = from
    self.to = to
  }
}

/// Where you stand against your prep. Latched once complete or off.
public enum PrepStatus: String, Sendable {
  case on, complete, off
}

/// A move's popup over the square it landed on.
public struct Pop: Equatable, Sendable {
  public var square: String
  public var text: String
  public var tone: ScoreTone
  /// A prepared move found: the tick goes in front of its time.
  public var found = false
  /// A book move past your prep.
  public var book = false
}

/// A miss being shown: the prepared move, drawn as a green arrow.
public struct MissFlash: Equatable, Sendable {
  public var expected: String
  public var from: String
  public var to: String
}

public struct Note: Equatable, Sendable {
  public var text: String
  /// "good", "bad", "missed" (a chance you missed) or "accent".
  public var tone: String
  public init(text: String, tone: String) {
    self.text = text
    self.tone = tone
  }
}

/// The engine's verdict on a move your prep did not have.
public struct Judgement: Equatable, Sendable {
  public var san: String
  public var ok: Bool
  public var lost: Double
  public var best: String?
  public var before: Double
  public var after: Double
  public var moment: Bool
  public var found: Bool
  public var reply: String?
  /// The engine's moves after yours that show why it is a blunder, as UCI, starting with `reply`.
  public var line: [String]
  /// An endgame where the engine had a mate and your move doesn't keep it.
  public var missedMate: Bool
  /// The exact results before and after your move, where the tablebase knows them.
  public var exact: ResultSlip?
  /// The engine's lines the verdict came from, as UCI: after your move, and after its own best; and how deep it looked.
  public var yours: [String] = []
  public var top: [String] = []
  public var depth = 0
  public init(
    san: String, ok: Bool, lost: Double, best: String?, before: Double, after: Double, moment: Bool, found: Bool, reply: String?,
    missedMate: Bool = false, exact: ResultSlip? = nil, line: [String]? = nil
  ) {
    self.line = line ?? reply.map { [$0] } ?? []
    self.san = san
    self.ok = ok
    self.lost = lost
    self.best = best
    self.before = before
    self.after = after
    self.moment = moment
    self.found = found
    self.reply = reply
    self.missedMate = missedMate
    self.exact = exact
  }
}

/// What the run is played under, fixed for its length.
public struct RunContext {
  public var index: ReferenceIndex
  public var prefs: RunPrefs
  /// Opened by Play: prepared and book moves pop with their time.
  public var play: Bool
  public init(index: ReferenceIndex, prefs: RunPrefs, play: Bool) {
    self.index = index
    self.prefs = prefs
    self.play = play
  }
}

public struct RunSession {
  public var source: LineSource
  public var state: RunTally
  public var redraw: (Run) -> Run
  public var prepStatus: PrepStatus = .on
  /// Whether your prep has answered anything yet.
  public var prepSeen = false
  /// The book phase: the ply it has reached (nil before it begins), and whether it is over.
  public var bookTo: Int?
  public var bookOver = false
  public var bookMoves = 0
  /// The line as it stood when your prep ran out without a miss.
  public var prepEnd: [String]?
  /// This run's prep answers.
  public var answers: [MoveResult] = []
  /// How long each prepared move you found took, in seconds.
  public var prepTimes: [Double] = []
  /// The engine's score after your last scored move, White's side.
  public var lastScored: Double?
  /// The engine's last word on the game, White's side.
  public var evalCp: Double?
  /// The engine's score before your first judged move and after each one, White's side: the Eval lens's chart.
  public var evalTrail: [Double] = []
  /// Your last judged move, for the Eval lens.
  public var lastJudged: JudgedMark?
  public var ending: Ending?
  /// Middlegame mode's run: handed over past your prep and the book, so neither is asked.
  public var middlegame = false
  /// Your moves past your prep counted toward distance markers.
  public var pastPrep = 0
  /// Your moves played once the game reached endgame rules, which a mate's pawns shrink by.
  public var endgameMoves = 0
  /// Your worst score once the game reached endgame rules, from your side, for a held draw.
  public var endgameLow: Double?
}

/// One of your judged moves: where it went, and the eval swing it closed on from your side (nil across a mate).
public struct JudgedMark: Equatable, Sendable {
  /// The move's index in the line played.
  public var ply: Int
  public var san: String
  public var from: String
  public var to: String
  public var swing: Double?
  public init(ply: Int, san: String, from: String, to: String, swing: Double?) {
    self.ply = ply
    self.san = san
    self.from = from
    self.to = to
    self.swing = swing
  }
}

/// The Eval lens's mark on the board: your last judged move's squares, tinted by the swing it
/// closed on (green gained, amber gave a little back, red gave back more), while it is still
/// your latest move. `played` is how many moves the line has.
public func evalLensTints(_ last: JudgedMark?, played: Int) -> [Tint] {
  guard let last, last.ply >= played - 2, let swing = last.swing, let score = moveScore(swing) else { return [] }
  let color: TintColor = score.tone == .up ? .green : score.tone == .slight ? .amber : .red
  return [last.from, last.to].map { Tint(square: $0, color: color, strength: 3) }
}

/// What the run asks the store to keep when it ends.
public struct Finish {
  public var how: Ending
  public var ended: RunTally
  /// Your prep played to its end without a miss: where growing it would start.
  public var clean: [String]?
  /// Prep that asked nothing.
  public var stub: Bool
  public var answers: [MoveResult]
}

/// Something for the screen to do, in order.
public enum Effect {
  /// One prepared position answered: activity for its openings, and their form.
  case answer(MoveResult)
  /// A prepared position answered: review its card.
  case answered(playbookId: String, fen: String, san: String, grade: Grade)
  /// A prepared position missed: log it for review.
  case missed(playbookId: String, fen: String, played: String, expected: String)
  case buzz(Int)
  case pop(Pop)
  case note(Note?)
  case miss(MissFlash)
  /// A moment settled by your move: the board's edge pulses green for found, red for missed.
  case moment(found: Bool)
  /// The moment's move you missed, its squares red until your next move.
  case missedBest((from: String, to: String)?)
  /// Pawns earned: onto the balance, popping out where they were earned.
  case pawns(PawnAward)
  /// A prepared move found: a pawn pops out of its square into the prep's pot, not yet paid.
  case potPawn(square: String)
  case finish(Finish)
}

public typealias Step = (session: RunSession, effects: [Effect])

/// A run, just begun.
public func beginSession(_ begun: RunBegun) -> RunSession {
  RunSession(source: begun.source, state: begun.state, redraw: begun.redraw)
}

private func unchanged(_ session: RunSession) -> Step { (session, []) }

/// One prepared position answered, credited to the position asked.
private func tally(_ session: RunSession, _ line: [String], _ correct: Bool, _ at: Double, seconds: Double? = nil) -> Step {
  let result = MoveResult(mode: .run, line: line, color: session.state.run.color, correct: correct, rated: true, at: at, seconds: seconds)
  var next = session
  next.answers.append(result)
  return (next, [.answer(result)])
}

/// The run is over: say how, once.
private func finish(_ session: RunSession, _ ended: RunTally, _ how: Ending) -> Step {
  if session.ending != nil { return unchanged(session) }
  let clean = ended.misses.isEmpty ? session.prepEnd : nil
  var next = session
  next.ending = how
  return (next, [.finish(Finish(how: how, ended: ended, clean: clean, stub: clean != nil && session.answers.isEmpty, answers: session.answers))])
}

/// After any move: reaching endgame rules pays once, a checkmate you gave pays, and a finished game ends the run.
private func afterMove(_ session: RunSession, _ state: RunTally) -> Step {
  var state = state
  var effects: [Effect] = []
  let fen = state.run.fen
  if !state.extras.endgame && isEndgame(fen) {
    state.extras.endgame = true
    effects.append(earn(&state, PawnAward(.endgame, .board)))
  }
  let status = positionStatus(fen)
  let won = status.checkmate && fenTurn(fen) != state.run.color
  if won {
    let at = kingSquare(fen, fenTurn(fen)).map(PawnSource.square) ?? .board
    effects.append(earn(&state, PawnAward(.checkmate, at, count: winPawns(endgameMoves: session.endgameMoves))))
  }
  var next = session
  next.state = state
  let ended: Step
  if !status.gameOver {
    ended = unchanged(next)
  } else if status.checkmate {
    ended = finish(next, state, won ? .won : .lost)
  } else {
    // A draw held from a lost ending pays.
    if heldDraw(low: session.endgameLow) {
      effects.append(earn(&state, PawnAward(.heldDraw, .board)))
      next.state = state
    }
    ended = finish(next, state, .draw)
  }
  return (ended.session, effects + ended.effects)
}

/// Pawns earned: counted on the run, and an effect to pay them out.
private func earn(_ state: inout RunTally, _ award: PawnAward) -> Effect {
  state.extras.pawns += award.count
  return .pawns(award)
}

private func then(_ step: Step, _ more: (RunSession) -> Step) -> Step {
  let after = more(step.session)
  return (after.session, step.effects + after.effects)
}

/// What your prep has here. Off prep in Freeform it has nothing, so nothing more is graded.
public func prepMoves(_ session: RunSession) -> [String] {
  if session.source.offPrepFinal && session.prepStatus == .off { return [] }
  return prepHere(session.source, session.state)
}

/// You played one of your prepared moves, `seconds` after your turn came.
public func playPrepared(_ session: RunSession, _ ctx: RunContext, _ move: LegalMove, _ seconds: Double, _ now: Double) -> Step {
  if session.ending != nil { return unchanged(session) }
  let run = session.state.run
  var effects: [Effect] = [.buzz(10)]
  if let rid = run.playbookId { effects.append(.answered(playbookId: rid, fen: run.fen, san: move.san, grade: gradeForTime(seconds))) }
  if ctx.play {
    effects.append(.pop(Pop(square: move.to, text: secondsText(seconds), tone: speedTone(seconds), found: true)))
  }
  if session.prepStatus == .on { effects.append(.potPawn(square: move.to)) }
  var start = session
  start.prepTimes.append(seconds)
  var step: Step = (start, effects)
  step = then(step) { tally($0, run.played, true, now, seconds: seconds) }
  step = then(step) { s in
    var seen = s
    seen.prepSeen = true
    return afterMove(seen, playYours(s.state, move.san))
  }
  return step
}

/// The engine judged a move your prep did not have. Where your prep had an
/// answer it is a miss; a blunder ends the run; otherwise the move stands.
public func judgedMove(_ session: RunSession, _ ctx: RunContext, _ judged: Judgement, _ seconds: Double, _ now: Double) -> Step {
  if session.ending != nil { return unchanged(session) }
  let run = session.state.run
  let prefs = ctx.prefs, index = ctx.index
  let expected = prepMoves(session)
  var step = unchanged(session)
  if let first = expected.first {
    step = tally(session, run.played, false, now)
    step.session.prepStatus = .off
    step.session.prepEnd = nil
    if let rid = run.playbookId { step.effects.append(.missed(playbookId: rid, fen: run.fen, played: judged.san, expected: first)) }
  }
  if !judged.ok {
    let slip =
      judged.exact
      ?? (endgameReached(run.played) ? ResultSlip(from: resultOf(run.color, judged.before), to: resultOf(run.color, judged.after)) : nil)
    return then(step) {
      finish($0, $0.state, .blunder(played: judged.san, best: judged.best, lost: judged.lost, line: judged.line, slip: slip))
    }
  }
  return then(step) { current in
    var effects: [Effect] = []
    var s = current
    // Past a clean prep, still in the book: a move strong players play is a good opening move.
    let bookPhase = expected.isEmpty && s.prepStatus == .complete && !s.bookOver
    let book = bookPhase && isBookMove(index, run.fen, judged.san, judged.lost)
    if bookPhase && !book { s.bookOver = true }
    if book {
      s.bookTo = run.played.count + 1
      s.bookMoves += 1
    }
    effects.append(.buzz(expected.isEmpty ? 10 : 14))
    let lastScored = s.lastScored
    let swing = evalSwing(run.color, s.lastScored ?? judged.before, judged.after)
    s.evalCp = judged.after
    if s.evalTrail.isEmpty { s.evalTrail.append(s.lastScored ?? judged.before) }
    s.evalTrail.append(judged.after)
    s.lastScored = judged.after
    let score = prefs.moveScores && swing != nil ? moveScore(swing!) : nil
    let landed = applySan(run.fen, judged.san)
    if let landed { s.lastJudged = JudgedMark(ply: run.played.count, san: judged.san, from: landed.from, to: landed.to, swing: swing) }
    // Moments are a thing past your prep; a book move gives nothing away.
    var scored = judgedExtras(s.state.extras, ExtrasPrefs(prefs), run.color, JudgedMove(
      lost: book ? 0 : judged.lost, after: judged.after, moment: judged.moment && expected.isEmpty, found: judged.found, fen: landed?.after))
    if book && ctx.play, let landed {
      effects.append(.pop(Pop(square: landed.to, text: secondsText(seconds), tone: speedTone(seconds), found: true, book: true)))
    } else if let score, let landed {
      effects.append(.pop(Pop(square: landed.to, text: score.cp > 0 ? "+\(JSNum(score.cp))" : "\u{2212}\(JSNum(-score.cp))", tone: score.tone)))
    }
    if let first = expected.first, let right = applySan(run.fen, first) {
      effects.append(.miss(MissFlash(expected: first, from: right.from, to: right.to)))
    }
    // A mate missed in a won ending: the run goes on, marked like a missed moment.
    let mateMissed = judged.missedMate && scored.earned.moment == nil
    effects.append(.note(mateMissed ? Note(text: "Missed mate", tone: "missed") : noteFor(scored.earned, best: judged.best)))
    if let moment = scored.earned.moment { effects.append(.moment(found: moment.found)) }
    if mateMissed { effects.append(.moment(found: false)) }
    let shown = scored.earned.moment.map { !$0.found } == true || mateMissed ? judged.best.flatMap { applySan(run.fen, $0) } : nil
    effects.append(.missedBest(shown.map { ($0.from, $0.to) }))
    // What the move paid, from its square; a mission's from the goal card.
    let at = landed.map { PawnSource.square($0.to) } ?? .board
    if expected.isEmpty && punished(run.color, lastScored: lastScored, before: judged.before, lost: judged.lost) {
      scored.extras.pawns += pawnsFor(.blunderPunished)
      effects.append(.pawns(PawnAward(.blunderPunished, at)))
    }
    if let moment = scored.earned.moment, moment.found { effects.append(.pawns(PawnAward(.moment, at))) }
    if let mission = scored.earned.mission, mission.result == .done { effects.append(.pawns(PawnAward(.mission, .goal))) }
    // Under endgame rules your worst score is kept for a held draw.
    let inEndgame = s.state.extras.endgame
    if inEndgame {
      let mine = [judged.before, judged.after].map { run.color == .w ? $0 : -$0 }
      s.endgameLow = ([s.endgameLow].compactMap { $0 } + mine).min()
    }
    // Every 5 of your moves past prep is a distance marker, until the endgame or the last marker.
    if expected.isEmpty && countsTowardMarker(pastPrep: s.pastPrep, endgame: inEndgame) {
      s.pastPrep += 1
      if s.pastPrep % DISTANCE_EVERY == 0 {
        let award = PawnAward(.distance, .marker, count: distancePawns(s.pastPrep / DISTANCE_EVERY, middlegame: s.middlegame))
        scored.extras.pawns += award.count
        effects.append(.pawns(award))
      }
    }
    var moved = afterMove(s, playYours(s.state, judged.san, expected.first, scored.extras))
    if inEndgame { moved.session.endgameMoves += 1 }
    return (moved.session, effects + moved.effects)
  }
}

/// A move added to your Playbook mid-run, played as yours: never graded,
/// and counted in the book's color.
public func playAdded(_ session: RunSession, _ san: String) -> Step {
  if session.ending != nil { return unchanged(session) }
  var next = session
  next.bookTo = session.state.run.played.count + 1
  return afterMove(next, playYours(session.state, san))
}

/// The opponent's reply while moves are being added: the book's most played.
public func playFillReply(_ session: RunSession, _ san: String) -> Step {
  if session.ending != nil { return unchanged(session) }
  return theirMove(session, playTheirs(session.state, san))
}

/// The opponent's turn from the book while it has a move. Nil where the book has nothing.
public func bookTurn(_ session: RunSession, _ index: ReferenceIndex, _ rng: () -> Double) -> Step? {
  if session.ending != nil { return unchanged(session) }
  let run = session.state.run
  let offLine = run.target.count <= run.played.count
  var steered = session.state
  if offLine { steered.run = session.redraw(run) }
  guard let san = bookReply(session.source, index, steered, rng) else { return nil }
  return theirMove(session, playTheirs(steered, san))
}

/// The engine's move for the opponent, where the book had none.
public func engineMove(_ session: RunSession, _ san: String) -> Step {
  if session.ending != nil { return unchanged(session) }
  return theirMove(session, playTheirs(session.state, san))
}

/// The opponent's move landed: a Convert it mission may settle on it, then the game may be over.
private func theirMove(_ session: RunSession, _ state: RunTally) -> Step {
  var state = state
  var effects: [Effect] = []
  if let cp = session.lastScored {
    let settled = theirExtras(state.extras, state.run.color, cp, state.run.fen)
    if let earned = settled.earned {
      state.extras = settled.extras
      effects.append(.note(noteFor(earned)))
      if earned.mission?.result == .done { effects.append(.pawns(PawnAward(.mission, .goal))) }
    }
  }
  let moved = afterMove(session, state)
  return (moved.session, effects + moved.effects)
}

/// Your turn with nothing prepared, having followed your prep so far: the line is done.
/// Prep that asked something and was never missed pays its pot: a pawn for each prep move asked.
public func prepRanOut(_ session: RunSession, _ index: ReferenceIndex) -> Step {
  if session.prepStatus != .on { return unchanged(session) }
  var next = session
  next.prepStatus = .complete
  if inTheBook(index, session.state.run.fen) { next.bookTo = session.state.run.played.count } else { next.bookOver = true }
  // Where growing would start, even when the prep asked you nothing.
  if session.state.misses.isEmpty { next.prepEnd = session.state.run.played }
  let pot = prepPawns(misses: session.state.misses.count, times: session.prepTimes)
  let effects = pot > 0 ? [earn(&next.state, PawnAward(.prepComplete, .pot, count: pot))] : []
  return (next, effects)
}

/// Whether the book phase has reached a position the book has nothing for.
public func bookRanOut(_ session: RunSession, _ index: ReferenceIndex) -> Bool {
  session.prepStatus == .complete && session.bookTo != nil && !session.bookOver && !inTheBook(index, session.state.run.fen)
}

/// Your turn where the book has run out: the book phase is over.
public func closeBook(_ session: RunSession, _ index: ReferenceIndex) -> RunSession {
  guard bookRanOut(session, index) else { return session }
  var next = session
  next.bookOver = true
  return next
}

/// Where the prep runs out, the first mission is set from the eval in front of you.
public func missionFrom(_ session: RunSession, _ prefs: RunPrefs, _ cp: Double) -> RunSession {
  if !prepMoves(session).isEmpty { return session }
  let run = session.state.run
  let extras = firstMission(session.state.extras, missions: prefs.missions, run.color, cp, run.fen)
  if extras == session.state.extras { return session }
  var next = session
  next.state.extras = extras
  return next
}

/// The run as one round for the score, against the deepest opening its line reached.
public func runRound(_ finish: Finish, _ tree: OpeningTree, at: Double) -> RoundRecord {
  let line = finish.ended.run.played
  var blunder = false
  if case .blunder = finish.how { blunder = true }
  return RoundRecord(
    mode: .run, openingId: deepestNodeWithin(tree, nodeById(tree, finish.ended.run.openingId), line).id,
    color: finish.ended.run.color, answered: finish.ended.moves + (blunder ? 1 : 0), correct: finish.ended.moves,
    perfect: finish.clean != nil && !finish.stub, at: at,
    prep: RoundRecord.Prep(asked: finish.answers.count, found: finish.answers.filter(\.correct).count),
    line: finish.clean ?? finish.ended.run.target)
}

/// You ended the run yourself.
public func endRun(_ session: RunSession) -> Step {
  finish(session, session.state, .ended)
}

public enum PrepLabel: String, Sendable {
  case on, complete, off, book, out, middlegame
}

/// What the prompt says of your prep.
public func prepLabel(_ session: RunSession) -> PrepLabel? {
  if session.middlegame { return .middlegame }
  if session.prepStatus == .complete && session.bookTo != nil && !session.bookOver { return .book }
  if session.prepStatus == .complete && session.bookOver { return .out }
  if session.prepSeen || session.prepStatus == .off || (session.prepStatus == .on && !prepMoves(session).isEmpty) {
    return PrepLabel(rawValue: session.prepStatus.rawValue)
  }
  return nil
}

/// What a judged move earned, said over the board, one thing at a time: a missed moment first
/// (its move is shown on the board), then the mission. A found moment says
/// nothing here: the board pulses, its bonus pops and the status line says Found it.
public func noteFor(_ earned: Earned, best: String? = nil) -> Note? {
  if let moment = earned.moment, !moment.found { return Note(text: best.map { "Missed \($0)" } ?? "Missed it", tone: "missed") }
  if let mission = earned.mission {
    let done = mission.result == .done
    return Note(text: "\(missionTitle(mission.kind)) \(done ? "complete" : "failed")", tone: done ? "good" : "bad")
  }
  return nil
}

/// Whether it is the player's turn in the run.
public func playersTurn(_ session: RunSession) -> Bool {
  fenTurn(session.state.run.fen) == session.state.run.color
}

/// The engine's score for the position in front of you, White's side: it steers the glow.
public func sawEval(_ session: RunSession, _ cp: Double) -> RunSession {
  if session.evalCp == cp { return session }
  var next = session
  next.evalCp = cp
  return next
}

/// A centipawn count as JS prints it.
private func JSNum(_ x: Double) -> String { JS.string(x) }
