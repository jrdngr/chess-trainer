import Book
import ChessCore

/// A Growth run as a pure controller, the same shape as SurvivalController:
/// `src/model/growthController.ts`.

public enum GrowthPhase: String, Sendable {
  case walking, hole, answered, done, lost
}

/// The batch being added: where it began in `added`, and how many it may add.
public struct Batch: Equatable, Sendable {
  public var base: Int
  public var allowance: Int
}

public struct GrowthSession: Equatable, Sendable {
  public var run: GrowthRun
  public var phase: GrowthPhase
  /// The move that left your prep while walking.
  public var wrong: String?
  /// Which plies of the line you added.
  public var added: [Int] = []
  public var batch: Batch?
  /// The answer just chosen, until they reply to it.
  public var answer: LegalMove?
  /// Every answer added this sitting, with the run and batch it answered: what Undo steps back to.
  public var history: [(run: GrowthRun, batch: Batch?, san: String)] = []
  /// The run stopped at the edge of the book.
  public var edge = false

  public static func == (a: GrowthSession, b: GrowthSession) -> Bool {
    a.run == b.run && a.phase == b.phase && a.wrong == b.wrong && a.added == b.added && a.batch == b.batch && a.answer == b.answer
      && a.edge == b.edge && a.history.count == b.history.count
  }
}

public enum GrowthEffect: Sendable {
  case addLine([String])
  case removeLine(nodeId: String)
  /// What the event log keeps: the line, the move, and what was offered.
  case log(kind: String, color: Color, line: String, picked: String, offered: [String], all: Bool)
  case buzz(Int)
  case toast(String)
  /// "End of the book", flashed over the board.
  case edgeFlash
}

public typealias GrowthStep = (session: GrowthSession, effects: [GrowthEffect])

/// A run begins at the hole it was handed, or the one the row most wants answered,
/// or at a line's tip for the book to reply; otherwise it walks from move one.
public func beginGrowth(_ tree: Repertoire, _ row: GrowthRow, _ hole: Hole? = nil) -> GrowthSession {
  let start = hole ?? firstHole(row)
  let end = start == nil ? firstEnd(row) : nil
  let run = start.map { startGrowthAt(tree, row, $0) } ?? end.map { startGrowthAtEnd(tree, row, $0) } ?? startGrowth(tree, row)
  return GrowthSession(run: run, phase: start != nil ? .hole : end != nil ? .answered : .walking)
}

public func opponentToMove(_ session: GrowthSession, _ tree: Repertoire) -> Bool {
  session.phase == .walking && !isUsersTurn(session.run) && !atHole(tree, session.run)
}

/// The opponent's move on the walk, steered toward the hole most worth answering.
public func opponentWalks(_ session: GrowthSession, _ tree: Repertoire, _ index: ReferenceIndex, _ find: GrowthOptions) -> GrowthSession {
  if !opponentToMove(session, tree) { return session }
  var next = session
  guard let reply = steer(tree, index, session.run, find) else {
    next.phase = .hole
    return next
  }
  if let hole = reply.hole {
    next.run = enterHole(session.run, hole)
    next.phase = .hole
    return next
  }
  if let walked = advance(tree, session.run, reply.san) { next.run = walked } else { next.phase = .hole }
  return next
}

/// A line that ends on the opponent's move leaves you to move with nothing: a hole.
public func nothingPrepared(_ session: GrowthSession, _ prepared: Int) -> GrowthSession {
  if session.phase != .walking || !isUsersTurn(session.run) || prepared > 0 { return session }
  var next = session
  next.phase = .hole
  return next
}

/// Your move on the walk: your prep is the only thing that counts here.
public func walk(_ session: GrowthSession, _ tree: Repertoire, _ san: String) -> GrowthStep {
  if session.phase != .walking || !isUsersTurn(session.run) { return (session, []) }
  var next = session
  guard let walked = advance(tree, session.run, san) else {
    next.wrong = san
    next.phase = .lost
    return (next, [.buzz(18)])
  }
  next.run = walked
  return (next, [.buzz(10)])
}

/// A batch is measured from the first hole it is offered at.
public func measureBatch(_ session: GrowthSession, _ maxPly: Int) -> GrowthSession {
  if session.phase != .hole || session.batch != nil { return session }
  var next = session
  next.batch = Batch(base: session.added.count, allowance: addsToFit(session.run.path.count, maxPly))
  return next
}

public func allowanceOf(_ session: GrowthSession, _ maxPly: Int) -> Int {
  session.batch?.allowance ?? addsToFit(session.run.path.count, maxPly)
}

/// How many answers this batch has added so far.
public func inBatch(_ session: GrowthSession) -> Int {
  session.added.count - (session.batch?.base ?? session.added.count)
}

/// Take an answer at a hole: it is saved and played, and their reply to it is next.
public func choose(_ session: GrowthSession, _ san: String, _ allowance: Int, _ offered: [String]) -> GrowthStep {
  let run = session.run
  guard session.phase == .hole, let move = applySan(run.fen, san), let answered = answerHole(run, san) else { return (session, []) }
  var next = session
  next.history.append((run, session.batch, san))
  next.added.append(run.path.count)
  next.answer = move
  next.run = answered
  next.phase = inBatch(session) + 1 >= allowance ? .done : .answered
  return (next, [
    .addLine(lineFor(run, san)),
    .log(kind: "growth-pick", color: run.color, line: run.path.joined(separator: " "), picked: san, offered: offered, all: false),
    .buzz(10),
    .toast("\(san) added"),
  ])
}

/// Their reply to the move you just added: nil (no move at all) ends the batch.
public func theyReply(_ session: GrowthSession, _ hole: Hole?) -> GrowthSession {
  if session.phase != .answered { return session }
  var next = session
  guard let hole else {
    next.phase = .done
    return next
  }
  next.answer = nil
  next.run = enterHole(session.run, hole)
  next.phase = .hole
  return next
}

/// Take back answers added this sitting: the last one, or all of them.
public func undo(_ session: GrowthSession, _ live: Repertoire?, all: Bool = false) -> GrowthStep {
  guard !session.history.isEmpty else { return (session, []) }
  let to = all ? 0 : session.history.count - 1
  let step = session.history[to]
  let line = step.run.hole != nil && !step.run.hole!.kept ? step.run.path : lineFor(step.run, step.san)
  var effects: [GrowthEffect] = []
  if let node = live.flatMap({ nodeAtLine($0, line) }) { effects.append(.removeLine(nodeId: node.id)) }
  effects += [
    .log(kind: "growth-undo", color: session.run.color, line: lineFor(step.run, step.san).joined(separator: " "), picked: step.san, offered: [], all: all),
    .buzz(10),
    .toast(all ? "Line undone" : "\(step.san) undone"),
  ]
  var next = session
  next.history = Array(session.history.prefix(to))
  next.added = Array(session.added.prefix(to))
  next.answer = nil
  next.batch = step.batch
  next.run = step.run
  next.phase = .hole
  return (next, effects)
}

/// Another batch, from where `resumeAdding` says it starts.
public func anotherBatch(_ session: GrowthSession, _ tree: Repertoire, _ more: GrowthRun) -> GrowthStep {
  var next = session
  next.answer = nil
  next.batch = nil
  next.run = more
  next.phase = atHole(tree, more) ? .hole : .answered
  return (next, [.buzz(10)])
}

/// Growth stops where the book does.
public func reachedEdge(_ session: GrowthSession) -> GrowthStep {
  if session.phase != .hole && session.phase != .answered { return (session, []) }
  var next = session
  next.answer = nil
  next.edge = true
  next.phase = .done
  return (next, [.edgeFlash])
}

/// Done ends the batch by hand.
public func stop(_ session: GrowthSession) -> GrowthSession {
  if session.phase == .done { return session }
  var next = session
  next.phase = .done
  return next
}

/// One sitting is one round, logged on the way out. Nil while the run goes on.
public func growthRound(_ session: GrowthSession, _ catalogue: OpeningTree, _ within: OpeningNode, _ allowance: Int, at: Double) -> RoundRecord? {
  if session.phase != .done && session.phase != .lost { return nil }
  return RoundRecord(
    mode: .growth, openingId: deepestNodeWithin(catalogue, within, session.run.path).id, color: session.run.color,
    answered: 0, correct: 0, perfect: inBatch(session) >= allowance, at: at)
}
