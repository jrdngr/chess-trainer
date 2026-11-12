import Shared

/// Spaced repetition: a small SM-2 variant counted in runs. A card's interval
/// is the number of runs it waits once known; dates are kept only to show.

public let MINUTE: Double = 60_000
public let DAY: Double = 86_400_000

public enum CardStage: String, Sendable, Codable {
  case new, learning, review
}

public enum Grade: String, Sendable, Codable, CaseIterable {
  case again, hard, good, easy
}

/// Spaced-repetition state for one position you answer.
public struct Card: Equatable, Sendable, Codable {
  public var id: String
  public var playbookId: String
  /// positionKey of the position to answer from.
  public var key: String
  public var fen: String
  public var stage: CardStage
  public var step: Int
  /// Runs between asks once known.
  public var interval: Double
  public var ease: Double
  public var reps: Int
  public var lapses: Int
  public var correct: Int
  public var incorrect: Int
  public var lastReviewed: Double?
  public var createdAt: Double
  /// The run that last asked this position: `ScoreState.lineRounds` before it.
  public var testedRound: Int?
}

public struct SrsConfig: Sendable {
  /// Right answers a new card takes before it graduates.
  public var learningSteps: Int
  /// Right answers a lapsed card takes to graduate again.
  public var relearningSteps: Int
  /// Runs, on graduating with Good.
  public var graduatingInterval: Double
  /// Runs, on graduating with Easy.
  public var easyInterval: Double
  public var startingEase: Double
  public var minEase: Double
  public var easeDelta: [Grade: Double]
  public var hardMultiplier: Double
  public var easyBonus: Double
  /// Fraction of the previous interval kept after a lapse.
  public var lapseMultiplier: Double
  public var minInterval: Double
  public var maxInterval: Double
}

public let DEFAULT_SRS = SrsConfig(
  learningSteps: 2,
  relearningSteps: 1,
  graduatingInterval: 3,
  easyInterval: 12,
  startingEase: 2.5,
  minEase: 1.3,
  easeDelta: [.again: -0.2, .hard: -0.15, .good: 0, .easy: 0.15],
  hardMultiplier: 1.2,
  easyBonus: 1.3,
  lapseMultiplier: 0.5,
  minInterval: 3,
  maxInterval: 1095
)

public func createCard(_ id: String, _ playbookId: String, _ key: String, _ fen: String, _ now: Double = Env.now()) -> Card {
  Card(
    id: id, playbookId: playbookId, key: key, fen: fen, stage: .new, step: 0, interval: 0,
    ease: DEFAULT_SRS.startingEase, reps: 0, lapses: 0, correct: 0, incorrect: 0,
    lastReviewed: nil, createdAt: now)
}

private func clampEase(_ ease: Double, _ cfg: SrsConfig) -> Double {
  max(cfg.minEase, JS.round(ease * 100) / 100)
}

private func clampInterval(_ runs: Double, _ cfg: SrsConfig) -> Double {
  min(cfg.maxInterval, max(cfg.minInterval, JS.round(runs * 100) / 100))
}

/// Apply a grade to a card asked in run `round`. A known card asked before its
/// interval is up keeps its interval. `now` is only recorded, for showing.
public func review(_ card: Card, _ grade: Grade, round: Int, now: Double = Env.now(), _ cfg: SrsConfig = DEFAULT_SRS) -> Card {
  let correct = grade != .again
  var next = card
  next.reps = card.reps + 1
  next.correct = card.correct + (correct ? 1 : 0)
  next.incorrect = card.incorrect + (correct ? 0 : 1)
  next.lastReviewed = now
  next.ease = clampEase(card.ease + cfg.easeDelta[grade]!, cfg)
  let inLearning = card.stage == .new || card.stage == .learning

  if grade == .again {
    if !inLearning {
      next.lapses += 1
      next.interval = clampInterval(card.interval * cfg.lapseMultiplier, cfg)
    }
    next.stage = .learning
    next.step = 0
  } else if inLearning {
    // Lapses only count from review, so a learning card with one is relearning.
    let steps = card.stage == .learning && card.lapses > 0 ? cfg.relearningSteps : cfg.learningSteps
    let graduated = { (runs: Double) in
      next.stage = .review
      next.step = 0
      next.interval = clampInterval(card.lapses > 0 ? max(runs, card.interval) : runs, cfg)
    }
    if grade == .easy {
      graduated(cfg.easyInterval)
    } else if grade == .hard {
      next.stage = .learning
    } else if card.step + 1 >= steps {
      graduated(cfg.graduatingInterval)
    } else {
      next.stage = .learning
      next.step = card.step + 1
    }
  } else if runNeed(card, round) < 1 {
    next.stage = .review
    next.step = 0
  } else {
    let prev = max(card.interval, cfg.minInterval)
    switch grade {
    case .hard: next.interval = clampInterval(prev * cfg.hardMultiplier, cfg)
    case .good: next.interval = clampInterval(prev * next.ease, cfg)
    default: next.interval = clampInterval(prev * next.ease * cfg.easyBonus, cfg)
    }
    next.stage = .review
    next.step = 0
  }
  next.testedRound = round
  return next
}

/// The grade a correct answer earns by how long it took.
public func gradeForTime(_ seconds: Double) -> Grade {
  if seconds < 3 { return .easy }
  if seconds < 8 { return .good }
  return .hard
}

/// Runs between asks of a position: two while learning, its interval once known.
public func runGap(_ card: Card) -> Double {
  card.stage == .review ? max(2, JS.round(card.interval)) : 2
}

/// How much a position wants asking, in runs: 1 and over is due. A card no run has asked is due.
public func runNeed(_ card: Card, _ round: Int) -> Double {
  guard let tested = card.testedRound else { return 1 }
  return Double(round - tested) / runGap(card)
}

extension Grade: CodingKeyRepresentable {}

/// One review, as the log keeps it.
public struct ReviewLogEntry: Equatable, Sendable, Codable {
  public var cardId: String
  public var at: Double
  public var grade: Grade
  public var correct: Bool
  public var playedSan: String?
  public var expectedSan: String
  public var intervalBefore: Double
  public var intervalAfter: Double
  public init(
    cardId: String, at: Double, grade: Grade, correct: Bool, playedSan: String?, expectedSan: String,
    intervalBefore: Double, intervalAfter: Double
  ) {
    self.cardId = cardId
    self.at = at
    self.grade = grade
    self.correct = correct
    self.playedSan = playedSan
    self.expectedSan = expectedSan
    self.intervalBefore = intervalBefore
    self.intervalAfter = intervalAfter
  }
}

