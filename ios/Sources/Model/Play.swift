import ChessCore
import Foundation
import Shared

/* Play: a game against the engine, with the opening kept.
 *
 * Strength is made here rather than in the engine, to play like a person of
 * a given rating: a lower rating searches shallower, so long tactics and
 * quiet threats go unseen, and picks among the good moves it sees. A move it
 * sees losing more than its level's window is never played on purpose. */

/// A playing strength, named by the rating it plays like, on one engine.
public struct Level: Equatable, Sendable {
  public var id: String
  public var name: String
  public var rating: Int
  /// The engine it plays with: its anchors made this level, and it picks the move.
  public var engine: EngineKind
  /// How far it looks.
  public var depth: Int
  /// How many candidate moves it weighs.
  public var multiPv: Int
  /// How readily it gives up centipawns inside the window: a move that
  /// costs this much is e (about 2.7) times less likely than the best.
  public var temperature: Double
  /// The most a move it plays may cost against its best, in centipawns.
  public var window: Double
}

/// The engines the app can play and judge with. One is chosen in Settings.
public enum EngineKind: String, Sendable, Codable, CaseIterable {
  case basic, caissa

  public var name: String {
    switch self {
    case .basic: return "Basic"
    case .caissa: return "Caissa"
    }
  }

  /// How it plays at each rating.
  public var style: EngineStyle {
    switch self {
    case .basic: return BasicStyle()
    case .caissa: return CaissaStyle()
    }
  }
}

/// A point the levels are drawn between: at this rating, how far the engine
/// looks, how many candidates it weighs, how readily it gives up centipawns
/// and the most it gives up.
public struct LevelAnchor: Sendable {
  public var rating: Int
  public var depth: Int
  public var temperature: Double
  public var multiPv: Int
  public var window: Double
  public init(_ rating: Int, depth: Int, temperature: Double, multiPv: Int, window: Double) {
    self.rating = rating
    self.depth = depth
    self.temperature = temperature
    self.multiPv = multiPv
    self.window = window
  }
}

/// A candidate line a level may play, with its score (White's) and its weight.
public typealias LevelMove = (line: EngineLine, cp: Double, weight: Double)

/// How an engine plays at each rating. Engines differ in what their top
/// lines are worth, so each sets its own anchors and may pick its own way.
public protocol EngineStyle: Sendable {
  /// Rising by rating, from `MIN_RATING` to `MAX_RATING`.
  var anchors: [LevelAnchor] { get }
  /// The lines a level may play, best first, each with its weight.
  func levelMoves(_ lines: [EngineLine], _ level: Level) -> [LevelMove]
}

extension EngineStyle {
  public func levelMoves(_ lines: [EngineLine], _ level: Level) -> [LevelMove] { windowMoves(lines, level) }
}

/// The app's own engine, in `Engine/Basic`.
public struct BasicStyle: EngineStyle {
  public init() {}
  public let anchors = [
    LevelAnchor(600, depth: 1, temperature: 700, multiPv: 20, window: 150),
    LevelAnchor(800, depth: 2, temperature: 500, multiPv: 16, window: 100),
    LevelAnchor(1200, depth: 3, temperature: 280, multiPv: 12, window: 60),
    LevelAnchor(1600, depth: 5, temperature: 150, multiPv: 8, window: 40),
    LevelAnchor(2000, depth: 7, temperature: 75, multiPv: 6, window: 25),
    LevelAnchor(2200, depth: 8, temperature: 55, multiPv: 5, window: 20),
  ]
}

/// Caissa: it sees far more at the same depth, so its levels look less far.
public struct CaissaStyle: EngineStyle {
  public init() {}
  public let anchors = [
    LevelAnchor(600, depth: 1, temperature: 700, multiPv: 20, window: 150),
    LevelAnchor(800, depth: 1, temperature: 500, multiPv: 16, window: 100),
    LevelAnchor(1200, depth: 2, temperature: 280, multiPv: 12, window: 60),
    LevelAnchor(1600, depth: 4, temperature: 220, multiPv: 10, window: 55),
    LevelAnchor(2000, depth: 6, temperature: 110, multiPv: 8, window: 40),
    LevelAnchor(2200, depth: 8, temperature: 100, multiPv: 6, window: 35),
  ]
}

/// The ratings a level can be set to.
public let MIN_RATING = 600, MAX_RATING = 2200

/// The level that plays like a rating on an engine, between its anchors.
public func levelFor(rating: Int, engine: EngineKind) -> Level {
  let anchors = engine.style.anchors
  let r = max(MIN_RATING, min(MAX_RATING, rating))
  let upper = anchors.firstIndex { $0.rating >= r } ?? anchors.count - 1
  let lower = max(0, upper - 1)
  let a = anchors[lower], b = anchors[upper]
  let t = b.rating == a.rating ? 0 : Double(r - a.rating) / Double(b.rating - a.rating)
  func between(_ x: Int, _ y: Int) -> Int { Int((Double(x) + t * Double(y - x)).rounded()) }
  let temperature = a.temperature + t * (b.temperature - a.temperature)
  let window = a.window + t * (b.window - a.window)
  return Level(
    id: String(r), name: String(r), rating: r, engine: engine, depth: between(a.depth, b.depth),
    multiPv: between(a.multiPv, b.multiPv), temperature: temperature, window: window)
}

/// The ratings Play offers as levels.
public let LEVEL_RATINGS = [800, 1200, 1600, 2000]

/// The levels Play offers, on an engine.
public func levels(_ engine: EngineKind) -> [Level] { LEVEL_RATINGS.map { levelFor(rating: $0, engine: engine) } }

public let DEFAULT_LEVEL = "1200"

/// Levels saved under their old names.
private let OLD_LEVELS = ["casual": 800, "club": 1200, "strong": 1600, "full": 2000]

/// A saved level on an engine: a rating, or one of the old names.
public func levelById(_ id: String, engine: EngineKind) -> Level {
  levelFor(rating: Int(id) ?? OLD_LEVELS[id] ?? Int(DEFAULT_LEVEL)!, engine: engine)
}

/// A line's score in centipawns, mate as a large number.
private func centipawns(_ line: EngineLine) -> Double? {
  if let cp = line.cp { return cp }
  if let mate = line.mate { return mate > 0 ? 10_000 - mate : -10_000 - mate }
  return nil
}

/// The candidate lines a level may play, as its engine picks them.
public func levelMoves(_ lines: [EngineLine], _ level: Level) -> [LevelMove] {
  level.engine.style.levelMoves(lines, level)
}

/// The usual pick: the lines inside the window of the best, best first, a
/// move costing more being likelier the less it costs. With no temperature,
/// only the best.
public func windowMoves(_ lines: [EngineLine], _ level: Level) -> [LevelMove] {
  let scored = lines.filter { !$0.pv.isEmpty }.jsSorted { Double($0.multipv - $1.multipv) }
    .compactMap { line in centipawns(line).map { (line: line, cp: $0) } }
  guard let best = scored.first?.cp else { return [] }
  if level.temperature <= 0 { return [(scored[0].line, best, 1)] }
  // Scores are White's; the best line is the mover's best, so a loss is the distance from it.
  return scored.filter { abs(best - $0.cp) <= level.window }
    .map { ($0.line, $0.cp, exp(-abs(best - $0.cp) / level.temperature)) }
}

/// Which candidate line to play, the UCI move or nil: one of the good moves
/// inside the level's window, so it plays a less ideal move but never one
/// it sees losing more.
public func chooseMove(_ lines: [EngineLine], _ level: Level, _ rand: () -> Double) -> String? {
  let moves = levelMoves(lines, level)
  guard !moves.isEmpty else { return lines.first { !$0.pv.isEmpty }?.pv[0] }
  var ticket = rand() * moves.reduce(0) { $0 + $1.weight }
  for move in moves {
    ticket -= move.weight
    if ticket <= 0 { return move.line.pv[0] }
  }
  return moves.last!.line.pv[0]
}

/// How long a game's opening is worth keeping, in plies.
public let OPENING_PLIES = 16

/// The opening of a game, as the line to write into a repertoire: the first
/// plies, trimmed to end on your own move.
public func openingLine(_ moves: [String], _ color: Color, _ plies: Int = OPENING_PLIES) -> [String] {
  let cut = Array(moves.prefix(plies))
  if cut.isEmpty { return cut }
  // A White line has odd length (ends on White's move); a Black line, even.
  let isOdd = cut.count % 2 == 1
  return isOdd == (color == .w) ? cut : Array(cut.dropLast())
}

public enum GameResult: String, Sendable, Codable {
  case win, loss, draw, unfinished
}

