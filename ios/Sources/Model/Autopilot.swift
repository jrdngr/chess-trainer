import ChessCore
import Shared

/// Autopilot: one Survival run after another, each decided for you,
/// including where it starts.

/// Where a Drill run starts: the position of your move most due, the moves to it played for
/// you; see `docs/gameplay.md`. A move never asked is the most due. With none due, your weakest
/// while your prep keeps missing, else the one closest to due. Never your first move as White,
/// so a Drill run never starts from move one. Nil with no moves of yours to start at.
public func drillStart(_ items: [TrainingItem], _ cards: [String: Card], accuracy: Double?, round: Int, now: Double? = nil) -> (item: TrainingItem, need: Double)? {
  let now = now ?? Env.now()
  let candidates = items.filter { !$0.pathSans.isEmpty }
  let ranked = candidates
    .map { item in (item: item, need: cards[item.cardId].map { runNeed($0, round, now) } ?? .infinity) }
    .jsSorted { cmp($1.need, $0.need) }
  if let first = ranked.first, first.need >= 1 { return first }
  if missingPrep(accuracy) > 0, let weakest = weakestFirst(candidates.filter { cards[$0.cardId] != nil }, cards).first {
    return (weakest, ranked.first { $0.item.cardId == weakest.cardId }?.need ?? 0)
  }
  return ranked.first
}

/// The kind of start a round was given.
public func startKind(start: Start, at: [String]?) -> StartKind {
  at != nil ? .inside : start == .first ? .cold : .position
}

/// What each focus asks of a run.
public let LEAN_FOR: [Focus: Steer] = [.test: .popular, .review: .weak]

/// How many plies into `line` your prep reaches. The first `from` count whatever they were.
public func prepDepth(_ line: [String], _ color: Color, _ prepAt: (String) -> [String], _ from: Int = 0) -> Int {
  var fen = START_FEN
  var depth = 0
  for (i, san) in line.enumerated() {
    if i < from {
      depth = i + 1
    } else if fenTurn(fen) == color {
      if !prepAt(fen).contains(san) { break }
      depth = i + 1
    }
    guard let move = applySan(fen, san) else { break }
    fen = move.after
  }
  return depth
}

/// How many of the first `plies` plies of a game are `color`'s moves.
public func movesBy(_ color: Color, in plies: Int) -> Int {
  color == .w ? (plies + 1) / 2 : plies / 2
}

/// Where a run stands in your prep, for Autopilot's segments.
public struct PrepSpan: Equatable, Sendable {
  public var played: Int
  public var total: Int
  /// Plies played in the book past the prep.
  public var book: Int?
  public init(played: Int, total: Int, book: Int? = nil) {
    self.played = played
    self.total = total
    self.book = book
  }

  /// The same span counted in `color`'s own moves rather than plies, so moves played for you don't take up segments.
  public func ownMoves(_ color: Color) -> PrepSpan {
    let book = book.map { movesBy(color, in: total + $0) - movesBy(color, in: total) }
    return PrepSpan(
      played: movesBy(color, in: played), total: movesBy(color, in: total),
      book: book == 0 ? nil : book)
  }
}

/// How badly a position has gone: lapses count double.
public func weakness(_ item: TrainingItem, _ cards: [String: Card]) -> Int {
  guard let card = cards[item.cardId] else { return 0 }
  return card.lapses * 2 + card.incorrect - card.correct
}

/// A queue with the positions you get wrong first.
public func weakestFirst(_ items: [TrainingItem], _ cards: [String: Card]) -> [TrainingItem] {
  items.jsSorted { cmp(weakness($1, cards), weakness($0, cards)) }
}
