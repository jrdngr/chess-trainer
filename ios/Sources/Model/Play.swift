import ChessCore
import Foundation
import Shared

/* Play: a game against the engine, with the opening kept. `src/model/play.ts`.
 *
 * Strength is made here rather than in the engine: a weak level thinks
 * briefly, looks at more candidates, and often takes one that is not the best. */

/// A Play strength.
public struct Level: Equatable, Sendable {
  public var id: String
  public var name: String
  public var depth: Int
  public var multiPv: Int
  /// How often it declines the best line, 0...1. The rest of the distribution
  /// is spread over the remaining candidates, nearest first.
  public var slip: Double
}

public let LEVELS: [Level] = [
  Level(id: "casual", name: "Casual", depth: 1, multiPv: 5, slip: 0.65),
  Level(id: "club", name: "Club", depth: 5, multiPv: 4, slip: 0.3),
  Level(id: "strong", name: "Strong", depth: 11, multiPv: 3, slip: 0.08),
  Level(id: "full", name: "Full", depth: 16, multiPv: 1, slip: 0),
]

public let DEFAULT_LEVEL = "club"

public func levelById(_ id: String) -> Level {
  LEVELS.first { $0.id == id } ?? LEVELS[1]
}

/// Which candidate line to play: weights fall off geometrically from the
/// best, so a slip usually costs one place. The UCI move, or nil.
public func chooseMove(_ lines: [EngineLine], _ level: Level, _ rand: () -> Double) -> String? {
  let usable = lines.filter { !$0.pv.isEmpty }.jsSorted { Double($0.multipv - $1.multipv) }
  guard let first = usable.first else { return nil }
  if usable.count == 1 || level.slip <= 0 { return first.pv[0] }
  let weights = usable.indices.map { $0 == 0 ? 1 - level.slip : level.slip / pow(2, Double($0)) }
  var ticket = rand() * weights.reduce(0, +)
  for (i, line) in usable.enumerated() {
    ticket -= weights[i]
    if ticket <= 0 { return line.pv[0] }
  }
  return usable.last!.pv[0]
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

/* ── games played here ── */

/// How many Play games are kept. Older ones fall off the end.
public let PLAY_GAMES_CAP = 200

/// How much of a Play game is kept: the opening.
public let PLAY_GAME_PLIES = 40

/// A finished Play game, kept in the shape of an import; nil for an
/// unfinished game or one under 2 plies.
public func playedGame(id: String, color: Color, moves: [String], result: GameResult, level: Level, at: Double) -> ImportedGame? {
  if result == .unfinished || moves.count < 2 { return nil }
  let score = result == .draw ? "1/2-1/2" : (result == .win) == (color == .w) ? "1-0" : "0-1"
  let engine = "Engine (\(level.name))"
  return ImportedGame(
    id: id, source: .play, white: color == .w ? "You" : engine, black: color == .b ? "You" : engine,
    result: score, userColor: color, date: utcDay(at), moves: Array(moves.prefix(PLAY_GAME_PLIES)))
}

/// `new Date(at).toISOString().slice(0, 10)`: the UTC calendar day.
private func utcDay(_ at: Double) -> String {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(identifier: "UTC")!
  let d = calendar.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: at / 1000))
  return String(format: "%04d-%02d-%02d", d.year!, d.month!, d.day!)
}

/// The games that were imported, leaving out the ones played here.
public func importedOnly(_ games: [ImportedGame]) -> [ImportedGame] {
  games.filter { $0.source != .play }
}

/// The games played here, newest first.
public func playGames(_ games: [ImportedGame]) -> [ImportedGame] {
  games.filter { $0.source == .play }
}

/// Add a Play game, or replace it when the same game is recorded again.
/// Play games sit newest first ahead of the imports; only the newest
/// `PLAY_GAMES_CAP` are kept.
public func withPlayGame(_ games: [ImportedGame], _ game: ImportedGame) -> [ImportedGame] {
  let played = ([game] + playGames(games).filter { $0.id != game.id }).prefix(PLAY_GAMES_CAP)
  return Array(played) + importedOnly(games)
}

/// Games from two devices: this device's imports, and both devices' Play
/// games merged by id, newest date first.
public func mergeGames(_ local: [ImportedGame], _ remote: [ImportedGame]) -> [ImportedGame] {
  var seen = Set<String>()
  let played = (playGames(local) + playGames(remote))
    .filter { seen.insert($0.id).inserted }
    .jsSorted { Double(JS.localeCompare($1.date ?? "", $0.date ?? "")) }
    .prefix(PLAY_GAMES_CAP)
  return Array(played) + importedOnly(local)
}
