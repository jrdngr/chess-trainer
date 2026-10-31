import Book
import ChessCore
import Shared

/// A Survival run (Autopilot's too) as a pure controller: `state + event →
/// state + effects`. `src/model/survivalController.ts`. The screen owns
/// timing, the engine and the store; it feeds each thing that happens in and
/// carries out the effects in order.

/// How a run ended.
public enum Ending: Equatable, Sendable {
  /// `played` is the move that lost, not on the board; `reply` the threat, as UCI.
  case blunder(played: String, best: String?, lost: Double, reply: String?)
  case won, lost, draw
  /// You ended it yourself.
  case ended
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
  /// A prepared move that is an extension.
  public var ext = false
}

/// A miss being shown: the prepared move, drawn as a green arrow.
public struct MissFlash: Equatable, Sendable {
  public var expected: String
  public var from: String
  public var to: String
}

public struct Note: Equatable, Sendable {
  public var text: String
  /// "good", "bad" or "accent".
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
  public init(san: String, ok: Bool, lost: Double, best: String?, before: Double, after: Double, moment: Bool, found: Bool, reply: String?) {
    self.san = san
    self.ok = ok
    self.lost = lost
    self.best = best
    self.before = before
    self.after = after
    self.moment = moment
    self.found = found
    self.reply = reply
  }
}

/// What the run is played under, fixed for its length.
public struct RunContext {
  public var index: ReferenceIndex
  public var prefs: SurvivalPrefs
  /// Opened by Autopilot: prepared and book moves pop with their time.
  public var autopilot: Bool
  /// What your move `san` is where `line` stands.
  public var kindOf: (_ line: [String], _ san: String) -> MoveKind
  /// What the engine said a saved move gives away, by `positionKey(fen) san`.
  public var lossOf: (_ key: String) -> Double?
  public init(index: ReferenceIndex, prefs: SurvivalPrefs, autopilot: Bool, kindOf: @escaping ([String], String) -> MoveKind, lossOf: @escaping (String) -> Double?) {
    self.index = index
    self.prefs = prefs
    self.autopilot = autopilot
    self.kindOf = kindOf
    self.lossOf = lossOf
  }
}

public struct RunSession {
  public var source: LineSource
  public var state: SurvivalRun
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
  /// This run's rated answers.
  public var answers: [MoveResult] = []
  /// How long each prepared move you found took, in seconds.
  public var prepTimes: [Double] = []
  /// The engine's score after your last scored move, White's side.
  public var lastScored: Double?
  /// The engine's last word on the game, White's side, for the glow.
  public var evalCp: Double?
  public var ending: Ending?
}

/// What the run asks the store to keep when it ends.
public struct Finish {
  public var how: Ending
  public var ended: SurvivalRun
  /// Your prep played to its end without a miss: where growing it would start.
  public var clean: [String]?
  /// Prep that asked nothing.
  public var stub: Bool
  public var answers: [MoveResult]
}

/// Something for the screen to do, in order.
public enum Effect {
  /// Rate one answered prepared position; `earlier` is the run's answers before it.
  case rate(result: MoveResult, earlier: [MoveResult])
  /// A prepared position answered: review its card.
  case answered(repertoireId: String, fen: String, san: String, grade: Grade)
  /// A prepared position missed: log it for review.
  case missed(repertoireId: String, fen: String, played: String, expected: String)
  case buzz(Int)
  case pop(Pop)
  case note(Note?)
  case miss(MissFlash)
  /// The moment's move you missed, drawn green while its note shows.
  case missedBest((from: String, to: String)?)
  case finish(Finish)
}

public typealias Step = (session: RunSession, effects: [Effect])

/// A run, just begun.
public func beginSession(_ begun: SurvivalStart) -> RunSession {
  RunSession(source: begun.source, state: begun.state, redraw: begun.redraw)
}

private func unchanged(_ session: RunSession) -> Step { (session, []) }

/// One prepared position answered: a rated result, credited to the position asked.
private func tally(_ session: RunSession, _ line: [String], _ correct: Bool, _ kind: MoveKind, _ at: Double) -> Step {
  let result = MoveResult(mode: .survival, line: line, color: session.state.run.color, correct: correct, rated: kind != .mistake, ext: kind != .book, at: at)
  var next = session
  next.answers.append(result)
  return (next, [.rate(result: result, earlier: session.answers)])
}

/// The run is over: say how, once.
private func finish(_ session: RunSession, _ ended: SurvivalRun, _ how: Ending) -> Step {
  if session.ending != nil { return unchanged(session) }
  let clean = ended.misses.isEmpty ? session.prepEnd : nil
  var next = session
  next.ending = how
  return (next, [.finish(Finish(how: how, ended: ended, clean: clean, stub: clean != nil && session.answers.isEmpty, answers: session.answers))])
}

/// After any move: a finished game ends the run.
private func afterMove(_ session: RunSession, _ state: SurvivalRun) -> Step {
  var next = session
  next.state = state
  let status = positionStatus(state.run.fen)
  if !status.gameOver { return unchanged(next) }
  if status.checkmate { return finish(next, state, fenTurn(state.run.fen) == state.run.color ? .lost : .won) }
  return finish(next, state, .draw)
}

private func then(_ step: Step, _ more: (RunSession) -> Step) -> Step {
  let after = more(step.session)
  return (after.session, step.effects + after.effects)
}

/// What your prep has here.
public func prepMoves(_ session: RunSession) -> [String] {
  prepHere(session.source, session.state)
}

/// You played one of your prepared moves, `seconds` after your turn came.
public func playPrepared(_ session: RunSession, _ ctx: RunContext, _ move: LegalMove, _ seconds: Double, _ now: Double) -> Step {
  if session.ending != nil { return unchanged(session) }
  let run = session.state.run
  var effects: [Effect] = [.buzz(10)]
  if let rid = run.repertoireId { effects.append(.answered(repertoireId: rid, fen: run.fen, san: move.san, grade: gradeForTime(seconds))) }
  let kind = ctx.kindOf(run.played, move.san)
  let lost = ctx.lossOf("\(positionKey(run.fen)) \(move.san)")
  let cost = kind == .mistake && lost != nil ? moveScore(-lost!) : nil
  if let cost {
    // A saved mistake is still yours to play, and the board says what it gives away.
    effects.append(.pop(Pop(square: move.to, text: "\u{2212}\(JSNum(-cost.cp))", tone: cost.tone)))
  } else if ctx.autopilot {
    effects.append(.pop(Pop(square: move.to, text: secondsText(seconds), tone: speedTone(seconds), found: true, ext: kind != .book)))
  }
  var start = session
  start.prepTimes.append(seconds)
  var step: Step = (start, effects)
  step = then(step) { tally($0, run.played, true, kind, now) }
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
    step = tally(session, run.played, false, ctx.kindOf(run.played, first), now)
    step.session.prepStatus = .off
    step.session.prepEnd = nil
    if let rid = run.repertoireId { step.effects.append(.missed(repertoireId: rid, fen: run.fen, played: judged.san, expected: first)) }
  }
  if !judged.ok {
    return then(step) { finish($0, $0.state, .blunder(played: judged.san, best: judged.best, lost: judged.lost, reply: judged.reply)) }
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
    let swing = evalSwing(run.color, s.lastScored ?? judged.before, judged.after)
    s.evalCp = judged.after
    s.lastScored = judged.after
    let score = prefs.moveScores && swing != nil ? moveScore(swing!) : nil
    let landed = applySan(run.fen, judged.san)
    if book && ctx.autopilot, let landed {
      effects.append(.pop(Pop(square: landed.to, text: secondsText(seconds), tone: speedTone(seconds), found: true, book: true)))
    } else if let score, let landed {
      effects.append(.pop(Pop(square: landed.to, text: score.cp > 0 ? "+\(JSNum(score.cp))" : "\u{2212}\(JSNum(-score.cp))", tone: score.tone)))
    }
    if let first = expected.first, let right = applySan(run.fen, first) {
      effects.append(.miss(MissFlash(expected: first, from: right.from, to: right.to)))
    }
    // Moments are a thing past your prep; a book move keeps the combo going.
    let scored = judgedExtras(s.state.extras, ExtrasPrefs(prefs), run.color, JudgedMove(
      lost: book ? 0 : judged.lost, after: judged.after, moment: judged.moment && expected.isEmpty, found: judged.found, fen: landed?.after))
    effects.append(.note(noteFor(scored.earned, judged.best)))
    let shown = scored.earned.moment.map { !$0.found } == true ? judged.best.flatMap { applySan(run.fen, $0) } : nil
    effects.append(.missedBest(shown.map { ($0.from, $0.to) }))
    let moved = afterMove(s, playYours(s.state, judged.san, expected.first, scored.extras))
    return (moved.session, effects + moved.effects)
  }
}

/// The opponent's turn from the book while it has a move. Nil where the book has nothing.
public func bookTurn(_ session: RunSession, _ index: ReferenceIndex, _ rng: () -> Double) -> Step? {
  if session.ending != nil { return unchanged(session) }
  let run = session.state.run
  let offLine = run.target.count <= run.played.count
  var steered = session.state
  if offLine { steered.run = session.redraw(run) }
  guard let san = bookReply(session.source, index, steered, rng) else { return nil }
  return afterMove(session, playTheirs(steered, san))
}

/// The engine's move for the opponent, where the book had none.
public func engineMove(_ session: RunSession, _ san: String) -> Step {
  if session.ending != nil { return unchanged(session) }
  return afterMove(session, playTheirs(session.state, san))
}

/// Your turn with nothing prepared, having followed your prep so far: the line is done.
public func prepRanOut(_ session: RunSession, _ index: ReferenceIndex) -> RunSession {
  if session.prepStatus != .on { return session }
  var next = session
  next.prepStatus = .complete
  if inTheBook(index, session.state.run.fen) { next.bookTo = session.state.run.played.count } else { next.bookOver = true }
  // Where growing would start, even when the prep asked you nothing.
  if session.state.misses.isEmpty { next.prepEnd = session.state.run.played }
  return next
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
public func missionFrom(_ session: RunSession, _ prefs: SurvivalPrefs, _ cp: Double) -> RunSession {
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
    mode: .survival, openingId: deepestNodeWithin(tree, nodeById(tree, finish.ended.run.openingId), line).id,
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
  case on, complete, off, book, out
}

/// What the prompt says of your prep.
public func prepLabel(_ session: RunSession) -> PrepLabel? {
  if session.prepStatus == .complete && session.bookTo != nil && !session.bookOver { return .book }
  if session.prepStatus == .complete && session.bookOver { return .out }
  if session.prepSeen || session.prepStatus == .off || (session.prepStatus == .on && !prepMoves(session).isEmpty) {
    return PrepLabel(rawValue: session.prepStatus.rawValue)
  }
  return nil
}

/// What a judged move earned, said over the board.
public func noteFor(_ earned: Earned, _ best: String?) -> Note? {
  var parts: [(text: String, good: Bool)] = []
  let dot = " \u{00b7} "
  if let moment = earned.moment {
    parts.append(moment.found ? ("Found it\(dot)+\(moment.bonus)", true) : (best.map { "Missed it\(dot)\($0) was there" } ?? "Missed it", false))
  }
  if let mission = earned.mission {
    parts.append(mission.result == .done
      ? ("\(missionTitle(mission.kind)) complete\(dot)+\(mission.bonus)", true)
      : ("\(missionTitle(mission.kind)) failed", false))
  }
  if earned.moment == nil && earned.combo == "broke" { parts.append(("Combo broken", false)) }
  if parts.isEmpty { return nil }
  return Note(text: parts.map(\.text).joined(separator: dot), tone: parts.allSatisfy(\.good) ? "good" : "bad")
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
