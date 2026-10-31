import ChessCore
import Shared

/// Repair: the openings you actually got wrong, in games you actually played.
/// `src/model/repair.ts`.
///
/// Everything comes from imported games compared against the repertoire, and
/// mistakes logged in the app; no position is invented. Two things can be
/// wrong at a position, and they stay separate all the way to the screen:
///
///   off prep    — you had a prepared move here and played something else.
///   unprepared  — you reached this repeatedly with nothing prepared at all.

public enum RepairKind: String, Sendable {
  case offprep, unprepared
}

/// Where the evidence came from: `games`, or a mistake's source.
public enum RepairSource: Equatable, Sendable {
  case games
  case mistake(MistakeSource)

  public var name: String {
    switch self {
    case .games: return "games"
    case .mistake(let source): return source.rawValue
    }
  }
}

public struct RepairItem: Sendable {
  /// Stable across rebuilds, so a fixed item can be skipped.
  public var id: String
  public var kind: RepairKind
  public var source: RepairSource
  public var repertoireId: String
  /// The side you were playing: always this repertoire's colour.
  public var color: Color
  public var key: String
  /// The position you are to move in.
  public var fen: String
  /// Moves from the start to that position.
  public var path: [String]
  public var lineText: String
  /// How many of your games reached it.
  public var games: Int
  public var results: GameResults
  /// What you actually played there, most often first.
  public var played: [PlayedMove]
  /// What the repertoire says. Empty for `unprepared`.
  public var expected: [String]
  /// Ranking weight: bigger is more worth fixing.
  public var weight: Double
}

public enum RepairSort: String, Sendable {
  case common, costly
}

public enum RepairKinds: Sendable, Equatable {
  case both
  case only(RepairKind)
}

public struct RepairOptions {
  /// Mistakes made in the app, merged in alongside the imported games.
  public var mistakes: [Mistake] = []
  /// "": every repertoire.
  public var repertoireId = ""
  public var kinds = RepairKinds.both
  /// How many of your games must have reached a position before it counts.
  public var minGames = DEFAULT_MIN_GAMES
  /// Only positions from games you went on to lose.
  public var lossesOnly = false
  public var sort = RepairSort.common
  public var limit: Int?

  public init(mistakes: [Mistake] = [], repertoireId: String = "", kinds: RepairKinds = .both, minGames: Int = DEFAULT_MIN_GAMES, lossesOnly: Bool = false, sort: RepairSort = .common, limit: Int? = nil) {
    self.mistakes = mistakes
    self.repertoireId = repertoireId
    self.kinds = kinds
    self.minGames = minGames
    self.lossesOnly = lossesOnly
    self.sort = sort
    self.limit = limit
  }

  func wants(_ kind: RepairKind) -> Bool { kinds == .both || kinds == .only(kind) }
}

public let DEFAULT_MIN_GAMES = 2

/// The ply at which this colour makes its first choice of the game.
private func firstDecisionPly(_ color: Color) -> Int { color == .w ? 0 : 1 }

private func kindOf(_ kind: FindingKind) -> RepairKind? {
  switch kind {
  case .deviation: return .offprep
  case .gap: return .unprepared
  case .unplayed: return nil
  }
}

/// How much a mistake cost, as a share of the games it appeared in. Draws
/// count as half a loss so a line that never wins still surfaces.
public func costOf(_ item: RepairItem) -> Double {
  let r = item.results
  let played = r.wins + r.draws + r.losses
  if played == 0 { return 0 }
  return (Double(r.losses) + Double(r.draws) * 0.5) / Double(played)
}

/// Every repairable position across the given repertoires.
public func buildRepairs(_ games: [ImportedGame], _ reps: [Repertoire], _ opts: RepairOptions = RepairOptions()) -> [RepairItem] {
  var out: [RepairItem] = []

  for rep in reps {
    if !opts.repertoireId.isEmpty && rep.id != opts.repertoireId { continue }
    let tree = buildPlayerTree(games, rep.color)
    if tree.games == 0 { continue }

    for finding in analyseAgainstRepertoire(tree, rep, minGames: opts.minGames, maxFindings: 200) {
      guard let kind = kindOf(finding.kind), opts.wants(kind), !finding.played.isEmpty else { continue }
      // The first decision of the game is which opening to play, not a move
      // to get right: `openingMismatch` reports it instead.
      if finding.path.count <= firstDecisionPly(rep.color) { continue }

      var item = RepairItem(
        id: "\(rep.id)#\(finding.key)#\(kind.rawValue)", kind: kind, source: .games, repertoireId: rep.id,
        color: rep.color, key: finding.key, fen: finding.fen, path: finding.path, lineText: finding.lineText,
        games: finding.games, results: finding.results, played: finding.played, expected: finding.expected, weight: 0)
      if opts.lossesOnly && item.results.losses == 0 { continue }
      // An off-prep move is a mistake you know how to fix, so it outranks a
      // position you never prepared at the same frequency.
      item.weight = Double(finding.games) * (kind == .offprep ? 1.5 : 1) * (1 + costOf(item))
      out.append(item)
    }
  }

  for item in fromMistakes(opts.mistakes, reps, opts) {
    // A position already found in the archive keeps the archive's figures.
    if out.contains(where: { $0.key == item.key && $0.repertoireId == item.repertoireId }) { continue }
    out.append(item)
  }

  let sorted = out.jsSorted { a, b in
    if opts.sort == .costly {
      let c = costOf(b) - costOf(a)
      return c != 0 ? c : Double(b.games - a.games)
    }
    let w = b.weight - a.weight
    return w != 0 ? w : Double(a.path.count - b.path.count)
  }
  return opts.limit.map { Array(sorted.prefix($0)) } ?? sorted
}

/// Repairs from mistakes made inside the app: always `offprep`, weighted as if
/// seen in a couple of games.
private func fromMistakes(_ log: [Mistake], _ reps: [Repertoire], _ opts: RepairOptions) -> [RepairItem] {
  if log.isEmpty || !opts.wants(.offprep) { return [] }
  // A mistake carries no result, so it cannot satisfy a losses-only filter.
  if opts.lossesOnly { return [] }

  let byId = Dictionary(reps.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
  var out: [RepairItem] = []
  for mistake in recentMistakes(log, opts.repertoireId.isEmpty ? nil : opts.repertoireId) {
    guard let rep = byId[mistake.repertoireId], !mistake.expected.isEmpty else { continue }
    // Only ask about positions it is still this player's turn in.
    if fenTurn(mistake.fen) != rep.color { continue }
    let path = mistake.path ?? []
    out.append(RepairItem(
      id: "\(rep.id)#\(mistake.key)#mistake", kind: .offprep, source: .mistake(mistake.source), repertoireId: rep.id,
      color: rep.color, key: mistake.key, fen: mistake.fen, path: path,
      lineText: path.isEmpty ? "From a position you reached" : sansToMoveText(path),
      games: 1, results: GameResults(wins: 0, draws: 0, losses: 0),
      played: [PlayedMove(san: mistake.played, count: 1)], expected: [mistake.expected], weight: 2.5))
  }
  return out
}
