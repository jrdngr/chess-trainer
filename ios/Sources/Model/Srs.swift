import Shared

/// Spaced repetition: a small SM-2 variant. `src/model/srs.ts`.

public let MINUTE: Double = 60_000
public let DAY: Double = 86_400_000

public enum CardStage: String, Sendable, Codable {
  case new, learning, review
}

public enum Grade: String, Sendable, Codable, CaseIterable {
  case again, hard, good, easy
}

/// The schedule part of a card: what `review` reads and writes.
public protocol Schedule {
  var stage: CardStage { get set }
  var step: Int { get set }
  var interval: Double { get set }
  var ease: Double { get set }
  var reps: Int { get set }
  var lapses: Int { get set }
  var correct: Int { get set }
  var incorrect: Int { get set }
  var due: Double { get set }
  var lastReviewed: Double? { get set }
  var createdAt: Double { get set }
}

/// Spaced-repetition state for one position you answer.
public struct Card: Schedule, Equatable, Sendable, Codable {
  public var id: String
  public var repertoireId: String
  /// positionKey of the position to answer from.
  public var key: String
  public var fen: String
  public var stage: CardStage
  public var step: Int
  public var interval: Double
  public var ease: Double
  public var reps: Int
  public var lapses: Int
  public var correct: Int
  public var incorrect: Int
  public var due: Double
  public var lastReviewed: Double?
  public var createdAt: Double
  /// The run that last asked this position: `ScoreState.lineRounds` before it.
  public var testedRound: Int?
}

/// Spaced-repetition state for one whole line, keyed by its last move.
public struct LineCard: Schedule, Equatable, Sendable, Codable {
  /// `repertoireId#tipId`.
  public var id: String
  public var repertoireId: String
  public var tipId: String
  public var stage: CardStage
  public var step: Int
  public var interval: Double
  public var ease: Double
  public var reps: Int
  public var lapses: Int
  public var correct: Int
  public var incorrect: Int
  public var due: Double
  public var lastReviewed: Double?
  public var createdAt: Double
}

public struct SrsConfig: Sendable {
  /// Learning steps in minutes, walked before a card graduates.
  public var learningSteps: [Double]
  /// Steps used after a lapse.
  public var relearningSteps: [Double]
  public var graduatingInterval: Double
  public var easyInterval: Double
  public var startingEase: Double
  public var minEase: Double
  public var easeDelta: [Grade: Double]
  public var hardMultiplier: Double
  public var easyBonus: Double
  /// Fraction of the previous interval kept after a lapse.
  public var lapseMultiplier: Double
  public var maxInterval: Double
}

public let DEFAULT_SRS = SrsConfig(
  learningSteps: [1, 10],
  relearningSteps: [10],
  graduatingInterval: 1,
  easyInterval: 4,
  startingEase: 2.5,
  minEase: 1.3,
  easeDelta: [.again: -0.2, .hard: -0.15, .good: 0, .easy: 0.15],
  hardMultiplier: 1.2,
  easyBonus: 1.3,
  lapseMultiplier: 0.5,
  maxInterval: 365
)

public func createCard(_ id: String, _ repertoireId: String, _ key: String, _ fen: String, _ now: Double = Env.now()) -> Card {
  Card(
    id: id, repertoireId: repertoireId, key: key, fen: fen, stage: .new, step: 0, interval: 0,
    ease: DEFAULT_SRS.startingEase, reps: 0, lapses: 0, correct: 0, incorrect: 0, due: now,
    lastReviewed: nil, createdAt: now)
}

public func createLineCard(_ repertoireId: String, _ tipId: String, _ now: Double = Env.now()) -> LineCard {
  LineCard(
    id: lineCardId(repertoireId, tipId), repertoireId: repertoireId, tipId: tipId, stage: .new, step: 0,
    interval: 0, ease: DEFAULT_SRS.startingEase, reps: 0, lapses: 0, correct: 0, incorrect: 0, due: now,
    lastReviewed: nil, createdAt: now)
}

public func lineCardId(_ repertoireId: String, _ tipId: String) -> String {
  "\(repertoireId)#\(tipId)"
}

private func clampEase(_ ease: Double, _ cfg: SrsConfig) -> Double {
  max(cfg.minEase, JS.round(ease * 100) / 100)
}

private func clampInterval(_ days: Double, _ cfg: SrsConfig) -> Double {
  min(cfg.maxInterval, max(1, JS.round(days * 100) / 100))
}

public struct ReviewOutcome<C: Schedule> {
  public var card: C
  /// Milliseconds until the card is next due.
  public var delay: Double
}

/// Apply a grade to a card. Pure: the same card, grade and moment always give the same result.
public func review<C: Schedule>(_ card: C, _ grade: Grade, _ now: Double = Env.now(), _ cfg: SrsConfig = DEFAULT_SRS) -> ReviewOutcome<C> {
  let correct = grade != .again
  var base = card
  base.reps = card.reps + 1
  base.correct = card.correct + (correct ? 1 : 0)
  base.incorrect = card.incorrect + (correct ? 0 : 1)
  base.lastReviewed = now
  base.ease = clampEase(card.ease + cfg.easeDelta[grade]!, cfg)

  var stage = base.stage
  var step = base.step
  var interval = base.interval
  var lapses = base.lapses
  let delay: Double
  let inLearning = card.stage == .new || card.stage == .learning

  if grade == .again {
    if !inLearning {
      lapses += 1
      interval = clampInterval(card.interval * cfg.lapseMultiplier, cfg)
    }
    stage = .learning
    step = 0
    delay = (inLearning ? cfg.learningSteps[0] : cfg.relearningSteps[0]) * MINUTE
  } else if inLearning {
    let steps = cfg.learningSteps
    if grade == .easy {
      stage = .review
      step = 0
      interval = clampInterval(cfg.easyInterval, cfg)
      delay = interval * DAY
    } else if grade == .hard {
      // Stay on the step, but come back a little sooner than "good".
      stage = .learning
      step = card.step
      delay = max(1, steps[min(step, steps.count - 1)]) * MINUTE
    } else {
      let nextStep = card.step + 1
      if nextStep >= steps.count {
        stage = .review
        step = 0
        interval = clampInterval(card.lapses > 0 ? max(cfg.graduatingInterval, card.interval) : cfg.graduatingInterval, cfg)
        delay = interval * DAY
      } else {
        stage = .learning
        step = nextStep
        delay = steps[nextStep] * MINUTE
      }
    }
  } else if now < card.due {
    // Practised ahead of schedule: the card keeps the date it had.
    stage = .review
    step = 0
    delay = card.due - now
  } else {
    let prev = max(card.interval, 1)
    switch grade {
    case .hard: interval = clampInterval(prev * cfg.hardMultiplier, cfg)
    case .good: interval = clampInterval(prev * base.ease, cfg)
    default: interval = clampInterval(prev * base.ease * cfg.easyBonus, cfg)
    }
    stage = .review
    step = 0
    delay = interval * DAY
  }

  var next = base
  next.stage = stage
  next.step = step
  next.interval = interval
  next.lapses = lapses
  next.due = now + delay
  return ReviewOutcome(card: next, delay: delay)
}

/// How a wait is written: "10m", "3h", "2.5d", "1.2mo", "1y".
public func describeDelay(_ ms: Double) -> String {
  let mins = ms / MINUTE
  if mins < 60 { return "\(JS.string(max(1, JS.round(mins))))m" }
  let hours = mins / 60
  if hours < 24 { return "\(JS.string(JS.round(hours)))h" }
  let days = hours / 24
  if days < 30 { return "\(JS.string(days < 10 ? JS.round(days * 10) / 10 : JS.round(days)))d" }
  let months = days / 30.4
  if months < 12 { return "\(JS.string(JS.round(months * 10) / 10))mo" }
  return "\(JS.string(JS.round(days / 365 * 10) / 10))y"
}

public func describeDue(_ due: Double, _ now: Double = Env.now()) -> String {
  due <= now ? "due now" : "in \(describeDelay(due - now))"
}

public func isDue(_ card: some Schedule, _ now: Double = Env.now()) -> Bool {
  card.due <= now
}

/// The grade a correct answer earns by how long it took.
public func gradeForTime(_ seconds: Double) -> Grade {
  if seconds < 3 { return .easy }
  if seconds < 8 { return .good }
  return .hard
}

/// A whole line's grade: Guessed after any miss, otherwise the average time.
public func gradeForLine(_ seconds: [Double], _ misses: Int) -> Grade {
  if misses > 0 { return .again }
  if seconds.isEmpty { return .good }
  return gradeForTime(seconds.reduce(0, +) / Double(seconds.count))
}

/// Runs a review card's interval stands for, per day of it.
public let RUNS_PER_DAY: Double = 3

/// Runs between asks of a position: two while learning, its interval in runs once known.
public func runGap(_ card: Card) -> Double {
  card.stage == .review ? max(2, JS.round(card.interval * RUNS_PER_DAY)) : 2
}

/// How much a position wants asking, in runs: 1 and over is due.
public func runNeed(_ card: Card, _ round: Int, _ now: Double = Env.now()) -> Double {
  guard let tested = card.testedRound else { return isDue(card, now) ? 1 : 0 }
  return Double(round - tested) / runGap(card)
}

extension Grade: CodingKeyRepresentable {}
