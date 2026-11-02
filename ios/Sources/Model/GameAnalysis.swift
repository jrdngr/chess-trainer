import ChessCore
import Shared

/// Your games against your Playbook.

/// One position in the player's own game history.
public struct PlayedNode {
  public var key: String
  public var fen: String
  /// SAN path from the start position (shortest route seen).
  public var path: [String]
  public var games = 0
  public var wins = 0
  public var draws = 0
  public var losses = 0
  /// SAN -> times the player chose it (only for positions on their turn).
  public var choices = OrderedMap<String, Int>()
}

public struct PlayerTree {
  public var color: Color
  public var nodes: OrderedMap<String, PlayedNode>
  public var games: Int
}

private enum Outcome { case win, draw, loss }

private func scoreFor(_ game: ImportedGame, _ color: Color) -> Outcome {
  if game.result == "1/2-1/2" { return .draw }
  let whiteWon = game.result == "1-0"
  return whiteWon == (color == .w) ? .win : .loss
}

/// Fold a set of games into a tree of the positions the player actually reached.
public func buildPlayerTree(_ games: [ImportedGame], _ color: Color, _ maxPlies: Int = 24) -> PlayerTree {
  var nodes = OrderedMap<String, PlayedNode>()
  var counted = 0

  for game in games where game.userColor == color {
    counted += 1
    let outcome = scoreFor(game, color)
    var fen = START_FEN
    var path: [String] = []

    for i in 0...min(game.moves.count, maxPlies) {
      let key = positionKey(fen)
      var node = nodes[key] ?? PlayedNode(key: key, fen: fen, path: path)
      node.games += 1
      switch outcome {
      case .win: node.wins += 1
      case .draw: node.draws += 1
      case .loss: node.losses += 1
      }
      let san = i < game.moves.count ? game.moves[i] : nil
      if let san, fenTurn(fen) == color { node.choices[san] = (node.choices[san] ?? 0) + 1 }
      nodes[key] = node
      guard let san, let move = applySan(fen, san) else { break }
      fen = move.after
      path.append(move.san)
    }
  }

  return PlayerTree(color: color, nodes: nodes, games: counted)
}

public enum FindingKind: String, Sendable {
  case gap, deviation, unplayed
}

public struct GameResults: Equatable, Sendable {
  public var wins: Int
  public var draws: Int
  public var losses: Int
}

public struct PlayedMove: Equatable, Sendable {
  public var san: String
  public var count: Int
}

public struct Finding: Sendable {
  public var kind: FindingKind
  public var key: String
  public var fen: String
  public var path: [String]
  public var lineText: String
  /// How many of the player's games reached this position.
  public var games: Int
  public var score: Double
  public var results: GameResults
  /// For 'deviation' and 'gap': what the player actually played, most common first.
  public var played: [PlayedMove]
  /// For 'deviation' and 'unplayed': what the repertoire says.
  public var expected: [String]
}

/// The repertoire's moves by position key, transpositions merged; `yoursOnly`
/// keeps only the positions it is the repertoire's side to move in.
private func movesByKey(_ rep: Repertoire, yoursOnly: Bool) -> OrderedMap<String, [String]> {
  var out = OrderedMap<String, [String]>()
  func visit(_ nodeId: String?) {
    let fen = fenAt(rep, nodeId)
    let kids = childrenOf(rep, nodeId)
    if !kids.isEmpty && (!yoursOnly || fenTurn(fen) == rep.color) {
      let key = positionKey(fen)
      var existing = out[key] ?? []
      for kid in kids where !existing.contains(kid.san) { existing.append(kid.san) }
      out[key] = existing
    }
    for kid in kids { visit(kid.id) }
  }
  visit(nil)
  return out
}

/// Compare what the player actually played against what their repertoire says.
///
/// - gap:       a position they reach often with nothing prepared
/// - deviation: a position where they played something other than their prep
/// - unplayed:  prepared lines that never came up (lowest priority)
public func analyseAgainstRepertoire(_ tree: PlayerTree, _ rep: Repertoire?, minGames: Int = 2, maxFindings: Int = 40) -> [Finding] {
  var findings: [Finding] = []
  // Indexed by position key for transposition-tolerant matching.
  let repByKey = rep.map { movesByKey($0, yoursOnly: true) } ?? OrderedMap()

  for node in tree.nodes.values {
    if node.choices.isEmpty || node.games < minGames { continue }
    let expected = repByKey[node.key]
    let played = node.choices.entries.map { PlayedMove(san: $0.key, count: $0.value) }.jsSorted { cmp($1.count, $0.count) }
    let results = GameResults(wins: node.wins, draws: node.draws, losses: node.losses)
    let lineText = node.path.isEmpty ? "Starting position" : sansToMoveText(node.path)
    func finding(_ kind: FindingKind, _ played: [PlayedMove], _ expected: [String], _ score: Double) -> Finding {
      Finding(
        kind: kind, key: node.key, fen: node.fen, path: node.path, lineText: lineText, games: node.games,
        score: score, results: results, played: played, expected: expected)
    }

    if let expected {
      let offPrep = played.filter { !expected.contains($0.san) }
      let offCount = offPrep.reduce(0) { $0 + $1.count }
      if offCount > 0 { findings.append(finding(.deviation, offPrep, expected, Double(offCount) * 1.5)) }
    } else {
      // No prep at all here. Deeper positions matter less than early ones.
      let depthPenalty = 1 / (1 + Double(node.path.count) / 6)
      let score = Double(node.games) * depthPenalty * (1 + Double(node.losses) / Double(max(1, node.games)))
      findings.append(finding(.gap, played, [], score))
    }
  }

  // Prepared lines that never appeared in the games.
  if let rep {
    let ordered = nodesInOrder(rep)
    for (key, sans) in repByKey.entries where !tree.nodes.has(key) {
      guard let node = ordered.first(where: { $0.key == key }) else { continue }
      findings.append(Finding(
        kind: .unplayed, key: key, fen: node.fenBefore, path: [], lineText: sansToMoveText(Array(sans.prefix(1)), node.fenBefore),
        games: 0, score: 0.01, results: GameResults(wins: 0, draws: 0, losses: 0), played: [], expected: sans))
    }
  }

  return Array(findings.jsSorted { $1.score - $0.score }.prefix(maxFindings))
}

public struct RepertoireCoverage: Equatable, Sendable {
  /// Games whose opening stayed inside the repertoire for at least 6 plies.
  public var inPrep: Int
  public var outOfPrep: Int
  /// Average ply at which the game left the repertoire.
  public var averageExitPly: Double
  public var games: Int
}

/// How long the player's games stayed inside their prepared lines.
public func measureCoverage(_ games: [ImportedGame], _ rep: Repertoire) -> RepertoireCoverage {
  let repByKey = movesByKey(rep, yoursOnly: false)
  var inPrep = 0
  var exitSum = 0
  var counted = 0

  for game in games where game.userColor == rep.color {
    counted += 1
    var fen = START_FEN
    var ply = 0
    for san in game.moves {
      guard let known = repByKey[positionKey(fen)], known.contains(san), let move = applySan(fen, san) else { break }
      fen = move.after
      ply += 1
    }
    exitSum += ply
    if ply >= 6 { inPrep += 1 }
  }

  return RepertoireCoverage(
    inPrep: inPrep, outOfPrep: counted - inPrep,
    averageExitPly: counted > 0 ? Double(exitSum) / Double(counted) : 0, games: counted)
}
