import ChessCore
import Shared

/// Endgame rules: once little material is left, a move is judged by the result
/// it keeps (win, draw or loss), not by the centipawns it gives away. A slower
/// win costs points, never the run.

/// At or below this phase the game is an endgame: knights and bishops count 1,
/// rooks 2, queens 4, so 24 at the start.
public let ENDGAME_PHASE = 8
/// From this far ahead, in centipawns, the engine's score counts as a win.
public let RESULT_WIN_CP: Double = 300
/// Scores are held inside this many centipawns when an endgame move's cost is
/// measured, so a mate missed in a won ending costs a few points, not thousands.
public let ENDGAME_SCORE_CAP: Double = 600

public enum EndResult: Int, Sendable, Codable, Comparable {
  case loss, draw, win
  public static func < (a: EndResult, b: EndResult) -> Bool { a.rawValue < b.rawValue }
  public var flipped: EndResult { self == .win ? .loss : self == .loss ? .win : .draw }
}

/// How much material is left: 1 per knight or bishop, 2 per rook, 4 per queen.
public func gamePhase(_ fen: String) -> Int {
  let placement = fen.split(separator: " ").first.map(String.init) ?? fen
  var phase = 0
  for ch in placement {
    switch ch.lowercased() {
    case "n", "b": phase += 1
    case "r": phase += 2
    case "q": phase += 4
    default: break
    }
  }
  return phase
}

public func isEndgame(_ fen: String) -> Bool { gamePhase(fen) <= ENDGAME_PHASE }

/// Whether a game played from the start has reached an endgame at any point:
/// once it has, its endgame rules stay on, even after a promotion adds material.
public func endgameReached(_ played: [String]) -> Bool { walkSan(played).fens.contains(where: isEndgame) }

/// The result an engine score points to for one side; the score is White's.
public func resultOf(_ color: Color, _ cp: Double) -> EndResult {
  let mine = color == .w ? cp : -cp
  return mine >= RESULT_WIN_CP ? .win : mine <= -RESULT_WIN_CP ? .loss : .draw
}

/// Judge an endgame move. It fails only when the result it keeps is worse than
/// the best move's and it also gives away more than the blunder line, so a
/// score wobbling across the win line on its own never ends a run. `exact`
/// results, where known (tablebase or a recognized ending), stand over the
/// engine's score: then a worse result always fails.
public func judgeEndgame(
  _ color: Color, _ before: Double, _ after: Double,
  exact: (before: EndResult, after: EndResult)? = nil
) -> EvalVerdict {
  func cap(_ x: Double) -> Double { max(-ENDGAME_SCORE_CAP, min(ENDGAME_SCORE_CAP, x)) }
  let lost = max(0, evalLoss(color, cap(before), cap(after)))
  if let exact { return EvalVerdict(ok: exact.after >= exact.before, lost: lost) }
  let slipped = resultOf(color, after) < resultOf(color, before)
  return EvalVerdict(ok: !slipped || lost <= BLUNDER_LIMIT, lost: lost)
}

/// Judge a move past the prep in the position `fen`: by its result in an
/// endgame, by the blunder line before that. `exact` results, or a game that
/// has `reached` an endgame, put any position under the endgame rules.
public func judgeMove(
  _ fen: String, _ color: Color, _ before: Double, _ after: Double,
  exact: (before: EndResult, after: EndResult)? = nil, reached: Bool = false
) -> EvalVerdict {
  exact != nil || reached || isEndgame(fen) ? judgeEndgame(color, before, after, exact: exact) : judgeByEval(color, before, after)
}

/// What a slip in an endgame did to the result, for the end screen: "Win
/// slipped to a draw". Nil when the result held.
public func slipText(_ from: EndResult, _ to: EndResult) -> String? {
  guard to < from else { return nil }
  func word(_ r: EndResult) -> String { r == .win ? "win" : r == .draw ? "draw" : "loss" }
  return "\(word(from).prefix(1).uppercased())\(word(from).dropFirst()) slipped to a \(word(to))"
}

/// The position Endgame mode keeps when a run ends on an endgame result given
/// away: `fen` is the position before the move, yours to play. Its fifty-move
/// count starts afresh, so the round it becomes has the moves to win. Nil when
/// the run ended any other way.
public func endgameGivenAway(_ how: Ending, fen: String, name: String, at: Double) -> SavedEndgame? {
  guard case .blunder(_, _, _, _, let slip?) = how, slip.to < slip.from else { return nil }
  var fields = fen.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
  if fields.count > 4 { fields[4] = "0" }
  let fresh = fields.joined(separator: " ")
  return SavedEndgame(id: "saved-\(positionKey(fresh))", fen: fresh, goal: slip.from == .win ? .win : .hold, name: name, at: at)
}
