import Book

/// The save's version. A save from before it is brought up by `migrate`
/// once the book is loaded; a new save starts at it.
public let SAVE_VERSION = 2

/// Runs a day of a card's interval stood for, when intervals were days.
let RUNS_PER_DAY: Double = 3

extension AppState {
  /// Brings a save from an older version up to this one, step by step.
  /// Returns whether anything changed.
  /// 1: the Playbook holds only book moves.
  /// 2: schedules count runs, not days.
  @discardableResult
  public mutating func migrate(_ index: ReferenceIndex) -> Bool {
    if version >= SAVE_VERSION { return false }
    if version < 1 { removeNonBookMoves(index) }
    if version < 2 { scheduleByRuns() }
    version = SAVE_VERSION
    return true
  }

  /// Card intervals in days become runs. Endgame positions count from the first
  /// Endgame round on: one failed last is due, others wait their interval.
  mutating func scheduleByRuns() {
    for id in cards.keys { cards[id]!.interval *= RUNS_PER_DAY }
    for id in endgames.cards.keys {
      var card = endgames.cards[id]!
      card.interval *= RUNS_PER_DAY
      card.dueRound = endgames.rounds + Int(card.interval.rounded())
      endgames.cards[id] = card
    }
  }
}
