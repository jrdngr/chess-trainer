import ChessCore
import Foundation

/// The games you played here, newest first: Survival, Autopilot and Middlegame
/// runs, and Play games. Recent reads the openings you picked from them, and
/// Export writes them out as PGN.

/// The mode a game was played in.
public enum GameMode: String, Sendable, Codable, CaseIterable {
  case survival, autopilot, middlegame, play

  public var label: String {
    switch self {
    case .survival: "Survival"
    case .autopilot: "Play"
    case .middlegame: "Middlegame"
    case .play: "Free play"
    }
  }
}

/// One game, whole: every move from the start position.
public struct GameRecord: Equatable, Sendable, Codable {
  /// One id per game, so a game ended again after a takeback replaces itself.
  public var id: String
  public var mode: GameMode
  public var at: Double
  /// The side you played.
  public var color: Color
  /// The selection saved when the game was played: an opening id, or "" for Any Opening (older saves may hold Any favorite).
  public var picked: Selection
  /// The opening the game was played in.
  public var opening: String
  public var moves: [String]
  /// Plies played for you before you took over.
  public var opened: Int
  /// "1-0", "0-1", "1/2-1/2", or "*" for a run that ended without a result.
  public var result: String
  /// How it ended: "blunder", "ended", "checkmate", "resigned" and so on.
  public var termination: String

  public init(
    id: String, mode: GameMode, at: Double, color: Color, picked: Selection, opening: String, moves: [String], opened: Int = 0,
    result: String, termination: String
  ) {
    self.id = id
    self.mode = mode
    self.at = at
    self.color = color
    self.picked = picked
    self.opening = opening
    self.moves = moves
    self.opened = opened
    self.result = result
    self.termination = termination
  }
}

/// How many games are kept; the oldest go past this.
public let GAMES_CAP = 100

/// The games after one more, newest first. A game with no moves is not kept,
/// and one with an id already kept replaces it.
public func addGame(_ games: [GameRecord], _ game: GameRecord) -> [GameRecord] {
  if game.moves.isEmpty { return games }
  return Array(([game] + games.filter { $0.id != game.id }).prefix(GAMES_CAP))
}

/// A result from your side, as PGN writes it: nil is a draw.
public func pgnResult(won: Bool?, color: Color) -> String {
  guard let won else { return "1/2-1/2" }
  return won == (color == .w) ? "1-0" : "0-1"
}

/// How a Survival, Autopilot or Middlegame run ended, as PGN's result and termination.
/// A run that stopped on a blunder or by your hand has no result.
public func runOutcome(_ how: Ending, color: Color) -> (result: String, termination: String) {
  switch how {
  case .blunder: ("*", "blunder")
  case .ended: ("*", "ended")
  case .won: (pgnResult(won: true, color: color), "checkmate")
  case .lost: (pgnResult(won: false, color: color), "checkmate")
  case .draw: ("1/2-1/2", "draw")
  }
}

/// The games an export takes.
public enum GameScope: String, Sendable, CaseIterable {
  case last, day, week, all
}

/// The games in a scope, newest first: the last one, the last 24 hours, the last 7 days, or all.
public func gamesIn(_ games: [GameRecord], _ scope: GameScope, now: Double) -> [GameRecord] {
  let day = 86_400_000.0
  switch scope {
  case .last: return Array(games.prefix(1))
  case .day: return games.filter { $0.at >= now - day }
  case .week: return games.filter { $0.at >= now - 7 * day }
  case .all: return games
  }
}

/// A selection's name for the PGN tags.
private func pickedName(_ tree: OpeningTree, _ selection: Selection) -> String {
  selection.opening == ANY_OPENING || selection.opening == LEGACY_ANY_FAVORITE ? "Any Opening" : nodeById(tree, selection.opening).name
}

/// One game as PGN: the standard tags, the app's own (Mode, Picked, Opening, Opened), then the moves.
public func gamePgn(_ game: GameRecord, _ tree: OpeningTree) -> String {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(identifier: "UTC")!
  let d = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date(timeIntervalSince1970: game.at / 1000))
  let opponent = "Chess Playbook \(game.mode.label)"
  var tags: [(String, String)] = [
    ("Event", "Chess Playbook \(game.mode.label)"),
    ("Site", "Chess Playbook"),
    ("Date", String(format: "%04d.%02d.%02d", d.year!, d.month!, d.day!)),
    ("Round", "-"),
    ("White", game.color == .w ? "You" : opponent),
    ("Black", game.color == .b ? "You" : opponent),
    ("Result", game.result),
    ("UTCTime", String(format: "%02d:%02d:%02d", d.hour!, d.minute!, d.second!)),
    ("Termination", game.termination),
    ("Mode", game.mode.rawValue),
    ("Picked", pickedName(tree, game.picked)),
    ("Opening", nodeById(tree, game.opening).name),
  ]
  if game.opened > 0 { tags.append(("Opened", "\(game.opened)")) }
  let head = tags.map { "[\($0.0) \"\($0.1.replacingOccurrences(of: "\"", with: "'"))\"]" }.joined(separator: "\n")
  let movetext = [sansToMoveText(game.moves), game.result].filter { !$0.isEmpty }.joined(separator: " ")
  return "\(head)\n\n\(movetext)\n"
}

/// Games as one PGN file, newest first.
public func gamesPgn(_ games: [GameRecord], _ tree: OpeningTree) -> String {
  games.map { gamePgn($0, tree) }.joined(separator: "\n")
}

extension AppState {
  /// A game finished: kept at the front of the history.
  public mutating func recordGame(_ game: GameRecord) {
    games = addGame(games, game)
  }
}

/* ── exports ── */

/// The whole profile, as Export's "Everything" writes it: every saved field,
/// the change log and the game history among them.
public struct ProfileExport: Encodable {
  public var format = "chess-playbook-profile"
  public var version = 1
  public var exportedAt: String
  public var profile: String
  public var state: AppState

  public init(exportedAt: String, profile: String, state: AppState) {
    self.exportedAt = exportedAt
    self.profile = profile
    self.state = state
  }
}

/// The Playbook alone: both sides' trees.
public struct PlaybookExport: Encodable {
  public var format = "chess-playbook-playbook"
  public var version = 1
  public var exportedAt: String
  public var repertoires: [Repertoire]

  public init(exportedAt: String, repertoires: [Repertoire]) {
    self.exportedAt = exportedAt
    self.repertoires = repertoires
  }
}

/// JSON for an export, readable and in a stable order.
public func exportJson<T: Encodable>(_ value: T) throws -> Data {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
  return try encoder.encode(value)
}
