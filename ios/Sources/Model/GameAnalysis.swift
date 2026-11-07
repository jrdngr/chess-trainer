import ChessCore
import Shared

/// Games folded into the positions the player reached.

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

/// A game without a decisive result ("1/2-1/2", or "*" for one unfinished) counts as a draw.
private func scoreFor(_ game: ImportedGame, _ color: Color) -> Outcome {
  switch game.result {
  case "1-0": return color == .w ? .win : .loss
  case "0-1": return color == .b ? .win : .loss
  default: return .draw
  }
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
