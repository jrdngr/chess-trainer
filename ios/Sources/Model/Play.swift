import ChessCore
import Foundation
import Shared

/* Play: a game against the engine, with the opening kept.
 *
 * Strength is made here rather than in the engine, to play like a person of
 * a given rating: a lower rating searches shallower, so long tactics and
 * quiet threats go unseen, and picks among the candidates by what each one
 * costs, so small slips are common and big ones rare. */

/// A playing strength, named by the rating it plays like.
public struct Level: Equatable, Sendable {
  public var id: String
  public var name: String
  public var rating: Int
  /// How far it looks.
  public var depth: Int
  /// How many candidate moves it weighs.
  public var multiPv: Int
  /// How readily it gives up centipawns: a move that costs this much is
  /// e (about 2.7) times less likely than the best.
  public var temperature: Double
}

/// The ratings a level can be set to.
public let MIN_RATING = 600, MAX_RATING = 2200

/// Anchor points the levels are drawn between: rating, depth, temperature,
/// and how many candidates it weighs (more for lower ratings, so a poor
/// move is among them).
private let LEVEL_ANCHORS: [(rating: Int, depth: Int, temperature: Double, multiPv: Int)] = [
  (600, 1, 700, 20), (800, 2, 500, 16), (1200, 3, 280, 12), (1600, 5, 150, 8), (2000, 7, 75, 6), (2200, 8, 55, 5),
]

/// The level that plays like a rating, between the anchors.
public func levelFor(rating: Int) -> Level {
  let r = max(MIN_RATING, min(MAX_RATING, rating))
  let upper = LEVEL_ANCHORS.firstIndex { $0.rating >= r } ?? LEVEL_ANCHORS.count - 1
  let lower = max(0, upper - 1)
  let a = LEVEL_ANCHORS[lower], b = LEVEL_ANCHORS[upper]
  let t = b.rating == a.rating ? 0 : Double(r - a.rating) / Double(b.rating - a.rating)
  func between(_ x: Int, _ y: Int) -> Int { Int((Double(x) + t * Double(y - x)).rounded()) }
  let temperature = a.temperature + t * (b.temperature - a.temperature)
  return Level(
    id: String(r), name: String(r), rating: r, depth: between(a.depth, b.depth), multiPv: between(a.multiPv, b.multiPv),
    temperature: temperature)
}

/// The levels Play offers.
public let LEVELS: [Level] = [800, 1200, 1600, 2000].map { levelFor(rating: $0) }

public let DEFAULT_LEVEL = "1200"

/// Levels saved under their old names.
private let OLD_LEVELS = ["casual": 800, "club": 1200, "strong": 1600, "full": 2000]

/// A saved level: a rating, or one of the old names.
public func levelById(_ id: String) -> Level {
  if let rating = Int(id) ?? OLD_LEVELS[id] { return levelFor(rating: rating) }
  return levelFor(rating: Int(DEFAULT_LEVEL)!)
}

/// A line's score in centipawns, mate as a large number.
private func centipawns(_ line: EngineLine) -> Double? {
  if let cp = line.cp { return cp }
  if let mate = line.mate { return mate > 0 ? 10_000 - mate : -10_000 - mate }
  return nil
}

/// Which candidate line to play, the UCI move or nil. Each candidate is
/// weighed by what it costs against the best, so a move that loses a
/// little is often played and one that loses a piece seldom is.
public func chooseMove(_ lines: [EngineLine], _ level: Level, _ rand: () -> Double) -> String? {
  let usable = lines.filter { !$0.pv.isEmpty }.jsSorted { Double($0.multipv - $1.multipv) }
  guard let first = usable.first else { return nil }
  guard usable.count > 1, level.temperature > 0, let best = centipawns(first) else { return first.pv[0] }
  // Scores are White's; the best line is the mover's best, so a loss is the distance from it.
  let weights = usable.map { line -> Double in
    guard let cp = centipawns(line) else { return 0 }
    return exp(-abs(best - cp) / level.temperature)
  }
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
func utcDay(_ at: Double) -> String {
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
