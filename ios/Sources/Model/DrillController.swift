import ChessCore

/// Drill positions as a pure controller: `state + event → state + effects`.
/// `src/model/drillController.ts`. The screen owns the clock, the flash's
/// timer and the store.

/// How many positions to line up at a time, and when to line up more.
public let DRILL_BATCH = 20
public let REFILL_AT = 6
/// How far back round a position comes when it is sent back.
public let REQUEUE_AFTER = 4

/// Asking; a correct move, shown for a beat; or a wrong one, explained.
public enum DrillPhase: String, Sendable { case ask, flash, wrong }

/// The last correct answer, graded off the clock; the grade buttons can change it.
public struct LastAnswer: Equatable, Sendable {
  public var item: TrainingItem
  public var before: Card
  public var grade: Grade
  public var played: String
}

public struct DrillStats: Equatable, Sendable {
  public var answered = 0
  public var correct = 0
}

public struct DrillState: Equatable, Sendable {
  public var queue: [TrainingItem]
  /// The position being asked: `queue[index]`.
  public var index = 0
  public var phase = DrillPhase.ask
  public var played: LegalMove?
  public var stats = DrillStats()
  public var last: LastAnswer?
  public init(queue: [TrainingItem]) { self.queue = queue }
}

public struct DrillOptions: Equatable, Sendable {
  public var mode: SessionMode
  /// How many new positions a batch may bring in.
  public var maxNew: Int
  /// Ask what you keep getting wrong before what is merely due.
  public var weakFirst: Bool
  public init(mode: SessionMode, maxNew: Int, weakFirst: Bool) {
    self.mode = mode
    self.maxNew = maxNew
    self.weakFirst = weakFirst
  }
}

/// Something for the screen to do, in order.
public enum DrillEffect: Equatable, Sendable {
  /// Record the answer: Drill is recorded, never rated.
  case record(line: [String], color: Color, correct: Bool)
  case buzz([Int])
  case grade(item: TrainingItem, grade: Grade, played: String, correct: Bool)
  case regrade(item: TrainingItem, before: Card, grade: Grade, played: String)
  case mistake(Mistake)
  /// Show the correct move for a beat, then go on — to `next`, when following the line.
  case flash(next: TrainingItem?)
}

public typealias DrillStep = (state: DrillState, effects: [DrillEffect])

private func order(_ batch: [TrainingItem], _ cards: [String: Card], _ weakFirst: Bool) -> [TrainingItem] {
  weakFirst ? weakestFirst(batch, cards) : batch
}

/// A sitting, lined up: scheduled work first, led by a position with a way in.
public func beginDrill(_ items: [TrainingItem], _ cards: [String: Card], _ opts: DrillOptions, _ now: Double) -> DrillState {
  let session = buildSession(
    items, cards, SessionOptions(mode: opts.mode, now: now, maxItems: DRILL_BATCH, maxNew: opts.maxNew, seed: (now / 60000).rounded(.down)))
  return DrillState(queue: leadWithAWayIn(order(session, cards, opts.weakFirst)))
}

/// Keep the queue stocked: scheduled work first, then the stalest positions.
public func refill(
  _ state: DrillState, _ items: [TrainingItem], _ cards: [String: Card], _ opts: DrillOptions, _ rand: () -> Double, _ now: Double
) -> DrillState {
  if items.isEmpty || state.queue.count - state.index > REFILL_AT { return state }
  let ahead = Set(state.queue[min(state.index, state.queue.count)...].map(\.cardId))
  let scheduled = buildSession(items, cards, SessionOptions(mode: opts.mode, now: now, maxItems: DRILL_BATCH, maxNew: opts.maxNew, seed: now))
    .filter { !ahead.contains($0.cardId) }
  let taken = Set(scheduled.map(\.cardId))
  let filler = scheduled.count >= DRILL_BATCH
    ? [] : extraPractice(items, cards, DRILL_BATCH - scheduled.count, rand) { ahead.contains($0) || taken.contains($0) }
  let batch = order(scheduled + filler, cards, opts.weakFirst)
  if batch.isEmpty { return state }
  var next = state
  next.queue += batch
  return next
}

/// The position being asked, if any.
public func current(_ state: DrillState) -> TrainingItem? {
  state.index < state.queue.count ? state.queue[state.index] : nil
}

/// The move the position wants: the preferred answer, or the first.
public func expectedSan(_ item: TrainingItem) -> String? {
  item.expected.first(where: \.preferred)?.san ?? item.expected.first?.san
}

/// The next decision point down this line: your answer, their reply, and the position after.
public func followUpFor(_ item: TrainingItem, _ items: [TrainingItem], _ rep: Repertoire?) -> TrainingItem? {
  guard rep != nil, item.continuation.count >= 2 else { return nil }
  guard let afterMine = applySan(item.fen, item.continuation[0]),
        let afterReply = applySan(afterMine.after, item.continuation[1]) else { return nil }
  return items.first { $0.fen == afterReply.after && $0.cardId != item.cardId }
}

/// You played `move`, `took` seconds after the position was asked.
public func answer(_ state: DrillState, _ move: LegalMove, _ took: Double, _ card: Card?, _ followUp: TrainingItem?) -> DrillStep {
  guard let item = current(state), state.phase == .ask else { return (state, []) }
  let result = checkAnswer(item, move.san)
  var effects: [DrillEffect] = [
    .record(line: result.correct ? item.pathSans + [move.san] : item.pathSans, color: item.orientation, correct: result.correct),
    .buzz(result.correct ? [12] : [18, 50, 18]),
  ]
  var next = state
  next.played = move
  next.stats.answered += 1
  if result.correct {
    next.stats.correct += 1
    let auto = gradeForTime(took)
    let before = card ?? createCard(item.cardId, item.repertoireId, item.key, item.fen)
    effects += [.grade(item: item, grade: auto, played: move.san, correct: true), .flash(next: followUp)]
    next.phase = .flash
    next.last = LastAnswer(item: item, before: before, grade: auto, played: move.san)
    return (next, effects)
  }
  effects += [
    .grade(item: item, grade: .again, played: move.san, correct: false),
    .mistake(Mistake(
      source: .drill, repertoireId: item.repertoireId, key: item.key, fen: item.fen, path: item.pathSans,
      played: move.san, expected: expectedSan(item) ?? "")),
  ]
  next.phase = .wrong
  return (next, effects)
}

/// On to the next position. Following the line, `extra` is put next.
public func advance(_ state: DrillState, _ extra: TrainingItem? = nil) -> DrillState {
  var next = state
  if let extra {
    var queue = state.queue.enumerated().filter { $0.offset <= state.index || $0.element.cardId != extra.cardId }.map(\.element)
    queue.insert(extra, at: min(state.index + 1, queue.count))
    next.queue = queue
  }
  next.index = state.index + 1
  next.phase = .ask
  next.played = nil
  return next
}

private func sendBack(_ state: DrillState, _ item: TrainingItem) -> DrillState {
  var next = state
  next.queue.insert(item, at: min(state.queue.count, state.index + REQUEUE_AFTER))
  return next
}

/// After a wrong answer, Continue: the position comes back round, and on to the next.
public func continueAfterWrong(_ state: DrillState) -> DrillState {
  advance(current(state).map { sendBack(state, $0) } ?? state)
}

/// Change the grade of the last correct answer. Guessed also brings it back soon.
public func regradeLast(_ state: DrillState, _ value: Grade) -> DrillStep {
  guard let last = state.last, value != last.grade else { return (state, []) }
  var next = value == .again ? sendBack(state, last.item) : state
  next.last?.grade = value
  return (next, [.regrade(item: last.item, before: last.before, grade: value, played: last.played)])
}

/// The sitting as one round; nil with nothing answered.
public func drillRound(_ state: DrillState, _ openingId: String, at: Double = Env.now()) -> RoundRecord? {
  let s = state.stats
  if s.answered == 0 { return nil }
  return RoundRecord(
    mode: .drill, openingId: openingId, color: current(state)?.orientation == .b ? .b : .w,
    answered: s.answered, correct: s.correct, perfect: s.correct == s.answered && s.answered >= 5, at: at)
}
