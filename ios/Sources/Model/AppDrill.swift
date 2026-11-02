/// Drill's changes to the saved state: `useStore`'s `ensureCard`, `grade`,
/// `regrade`, `gradeLine` and `clearMistake` (`logMistake` is in
/// `PlayPrefs.swift`), and Drill's own options.

/// Drill's defaults.
public let DEFAULT_DRILL = DrillPrefs(
  form: .positions, draw: .due, newPerSession: 8, followLine: true, weakFirst: false, explain: true,
  batchSimilar: true, clock: .off)

public let DRILL_FORM_LABELS: [DrillForm: String] = [.positions: "Positions", .lines: "Lines"]
public let DRILL_DRAW_LABELS: [DrillDraw: String] = [.due: "Scheduled", .new: "New only", .cram: "Everything"]

extension DrillDraw {
  /// The session mode a draw asks for.
  public var mode: SessionMode {
    switch self {
    case .due: return .due
    case .new: return .new
    case .cram: return .cram
    }
  }
}

/// Drill's options as saved: any missing takes its default.
struct SavedDrillPrefs: Decodable {
  var form: DrillForm?
  var draw: DrillDraw?
  var newPerSession: Int?
  var followLine: Bool?
  var weakFirst: Bool?
  var explain: Bool?
  var batchSimilar: Bool?
  var clock: ClockMode?

  var prefs: DrillPrefs {
    let d = DEFAULT_DRILL
    return DrillPrefs(
      form: form ?? d.form, draw: draw ?? d.draw, newPerSession: newPerSession ?? d.newPerSession,
      followLine: followLine ?? d.followLine, weakFirst: weakFirst ?? d.weakFirst, explain: explain ?? d.explain,
      batchSimilar: batchSimilar ?? d.batchSimilar, clock: clock ?? d.clock)
  }
}

extension AppState {
  /// A position's card, made when it is first asked.
  @discardableResult
  public mutating func ensureCard(_ item: TrainingItem, now: Double = Env.now()) -> Card {
    if let existing = cards[item.cardId] { return existing }
    let card = createCard(item.cardId, item.repertoireId, item.key, item.fen, now)
    cards[item.cardId] = card
    return card
  }

  /// A Drill answer graded. A right one retires the mistake logged at the position.
  public mutating func grade(_ item: TrainingItem, _ grade: Grade, _ playedSan: String?, _ correct: Bool, now: Double = Env.now()) {
    let card = cards[item.cardId] ?? createCard(item.cardId, item.repertoireId, item.key, item.fen, now)
    reviewed(card, grade, correct: correct, playedSan: playedSan, expectedSan: expectedSan(item) ?? "", now: now)
    if correct { mistakes.removeAll { $0.id == "\(item.repertoireId)#\(item.key)" } }
  }

  /// Change the grade just given: the card goes back to `before`, the last log entry for it goes, and it is reviewed again.
  public mutating func regrade(_ item: TrainingItem, _ before: Card, _ grade: Grade, _ playedSan: String?, now: Double = Env.now()) {
    if let last = log.lastIndex(where: { $0.cardId == item.cardId }) { log.remove(at: last) }
    reviewed(before, grade, correct: true, playedSan: playedSan, expectedSan: expectedSan(item) ?? "", now: now)
  }

  /// A line's grade, applied to its card — or to `before`, changing a grade
  /// rather than giving it twice. Returns the card the grade was applied to.
  @discardableResult
  public mutating func gradeLine(_ repertoireId: String, _ tipId: String, _ grade: Grade, _ before: LineCard? = nil, now: Double = Env.now()) -> LineCard {
    let id = lineCardId(repertoireId, tipId)
    let from = before ?? lineCards[id] ?? createLineCard(repertoireId, tipId, now)
    lineCards[id] = review(from, grade, now).card
    return from
  }

  public mutating func clearMistake(_ id: String) {
    mistakes.removeAll { $0.id == id }
  }

  /// `reviewed` in the store: the card reviewed, and the review logged (the last 500 kept).
  private mutating func reviewed(_ card: Card, _ grade: Grade, correct: Bool, playedSan: String?, expectedSan: String, now: Double) {
    let next = review(card, grade, now).card
    cards[card.id] = next
    log = Array(log.suffix(499)) + [ReviewLogEntry(
      cardId: card.id, at: now, grade: grade, correct: correct, playedSan: playedSan, expectedSan: expectedSan,
      intervalBefore: card.interval, intervalAfter: next.interval)]
  }
}
