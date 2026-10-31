import ChessCore
import Shared

/// Autopilot: one Survival run after another, each decided for you,
/// including where it starts. `src/model/autopilot.ts`.

/// Runs the way in goes unplayed before a cold start wants it.
public let COLD_GAP: Double = 6
/// A cold start every this many runs at the latest.
public let COLD_EVERY = 3

/// Your positions on the way into an opening, and the ones inside it.
public func splitItems(_ items: [TrainingItem], _ openingPlies: Int) -> (wayIn: [TrainingItem], inside: [TrainingItem]) {
  (items.filter { $0.pathSans.count < openingPlies }, items.filter { $0.pathSans.count > openingPlies })
}

/// How much the way in wants playing: runs since its stalest move, over the cold gap.
public func coldNeed(_ wayIn: [TrainingItem], _ cards: [String: Card], _ round: Int) -> Double {
  if wayIn.isEmpty { return 0 }
  let since = wayIn.map { item -> Double in
    guard let tested = cards[item.cardId]?.testedRound else { return .infinity }
    return Double(round - tested)
  }
  return since.max()! / COLD_GAP
}

/// Where an inside start would begin, and how much it wants it.
public func insideStart(_ inside: [TrainingItem], _ cards: [String: Card], accuracy: Double?, round: Int, now: Double? = nil) -> (item: TrainingItem, need: Double)? {
  let now = now ?? Env.now()
  let due = inside
    .filter { cards[$0.cardId] != nil }
    .map { (item: $0, need: runNeed(cards[$0.cardId]!, round, now)) }
    .filter { $0.need >= 1 }
    .jsSorted { $1.need - $0.need }
  if let first = due.first { return first }
  if missingPrep(accuracy) == 0 { return nil }
  return weakestFirst(inside.filter { cards[$0.cardId] != nil }, cards).first.map { ($0, 1) }
}

/// Where the next run starts: see `docs/autopilot.md`.
public func chooseStart(recent: [StartKind], cold: Double, inside: Double?, firstTime: Bool = false) -> StartKind {
  if firstTime { return .position }
  let last = recent.last
  let tail = recent.suffix(COLD_EVERY - 1)
  if tail.count == COLD_EVERY - 1 && !tail.contains(.cold) { return .cold }
  let c = last != .cold && cold >= 1 ? cold : 0
  let i = last != .inside && inside != nil && inside! >= 1 ? inside! : 0
  if c == 0 && i == 0 { return .position }
  return c >= i ? .cold : .inside
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

/// Where a run stands in your prep, for Autopilot's segments.
public struct PrepSpan: Equatable, Sendable {
  public var played: Int
  public var total: Int
  /// Plies played in the book past the prep.
  public var book: Int?
  /// The ply the prep leaves the book at.
  public var ext: Int?
  public init(played: Int, total: Int, book: Int? = nil, ext: Int? = nil) {
    self.played = played
    self.total = total
    self.book = book
    self.ext = ext
  }
}

/// Where the next run would start in your prep, for its button.
public func roundSpan(_ rep: Repertoire?, _ pick: Recommendation, _ at: [String]?, _ limit: Int = 60) -> PrepSpan {
  guard let rep else { return PrepSpan(played: 0, total: 0) }
  let index = prepIndex(rep)
  let prepAt = { (fen: String) in index[positionKey(fen)] ?? [] }
  let way = at ?? (pick.start == .inside ? pick.opening.sans : [])
  var line = at ?? pick.opening.sans
  let fens = walkSan(line).fens
  line = Array(line.prefix(fens.count - 1))
  var fen = fens.last!
  while line.count < limit {
    guard let san = prepAt(fen).first, let move = applySan(fen, san) else { break }
    line.append(san)
    fen = move.after
  }
  let total = prepDepth(line, pick.color, prepAt, way.count)
  return PrepSpan(played: min(way.count, total), total: total)
}

/// How badly a position has gone: lapses count double. `session.ts`.
public func weakness(_ item: TrainingItem, _ cards: [String: Card]) -> Int {
  guard let card = cards[item.cardId] else { return 0 }
  return card.lapses * 2 + card.incorrect - card.correct
}

/// A queue with the positions you get wrong first.
public func weakestFirst(_ items: [TrainingItem], _ cards: [String: Card]) -> [TrainingItem] {
  items.jsSorted { cmp(weakness($1, cards), weakness($0, cards)) }
}
