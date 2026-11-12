import ChessCore
import Engine
import Model

/// A small, fast engine with fixed answers, for headless games and tests: every
/// move is searched two plies deep on material and a little mobility, ties go to
/// the earlier move, and the same position always gets the same lines. A test
/// can fix what it says of a position with `script`.
public struct ScriptedEngine: ChessEngine {
  /// Lines for a position, by `positionKey`, used instead of the search.
  public var script: [String: [EngineLine]]

  public init(script: [String: [EngineLine]] = [:]) {
    self.script = script
  }

  public func analyse(_ fen: String, _ limits: EngineLimits, onUpdate: @escaping @Sendable (EngineSnapshot) -> Bool) async -> EngineSnapshot {
    let lines = self.lines(fen, limits)
    let depth = lines.first?.depth ?? 0
    return EngineSnapshot(lines: lines, depth: depth, nodes: 0, thinking: false, fen: fen)
  }

  /// The lines a search of `fen` gives, best first.
  public func lines(_ fen: String, _ limits: EngineLimits) -> [EngineLine] {
    let count = max(1, limits.multiPv ?? 1)
    if var fixed = script[positionKey(fen)] {
      if let only = limits.searchmoves { fixed = fixed.filter { $0.pv.first.map(only.contains) ?? false } }
      return Array(fixed.prefix(count)).enumerated().map { i, line in
        var line = line
        line.multipv = i + 1
        return line
      }
    }
    var moves = legalMoves(fen)
    if let only = limits.searchmoves { moves = moves.filter { only.contains($0.uci) } }
    let white = fenTurn(fen) == .w
    let scored = moves.map { move -> (move: LegalMove, score: Score) in (move, Self.reply(move)) }
    let ranked = scored.sorted { a, b in
      let (x, y) = (a.score.cp, b.score.cp)
      if x != y { return white ? x > y : x < y }
      return a.move.uci < b.move.uci
    }
    return ranked.prefix(count).enumerated().map { i, item in
      EngineLine(multipv: i + 1, depth: 2, cp: item.score.mate == nil ? item.score.cp : nil, mate: item.score.mate, pv: [item.move.uci] + item.score.pv)
    }
  }

  /// A score from White's side: centipawns, or a mate in so many moves.
  struct Score: Sendable {
    var cp: Double
    var mate: Double?
    var pv: [String]
  }

  /// The position after `move`, with the opponent's best reply taken.
  private static func reply(_ move: LegalMove) -> Score {
    let fen = move.after
    let moverWhite = fenTurn(fen) == .b
    let replies = legalMoves(fen)
    if replies.isEmpty {
      if positionStatus(fen).check { return Score(cp: moverWhite ? 100_000 : -100_000, mate: moverWhite ? 1 : -1, pv: []) }
      return Score(cp: 0, mate: nil, pv: [])
    }
    let replierWhite = !moverWhite
    var best: (cp: Double, uci: String)?
    for reply in replies {
      let cp = replyScore(reply)
      if let b = best, replierWhite ? cp <= b.cp : cp >= b.cp { continue }
      best = (cp, reply.uci)
    }
    return Score(cp: best!.cp, mate: nil, pv: [best!.uci])
  }

  /// A reply's worth: mate where it mates, else the material and mobility left.
  private static func replyScore(_ reply: LegalMove) -> Double {
    if reply.san.hasSuffix("#") { return fenTurn(reply.after) == .b ? 100_000 : -100_000 }
    return evaluate(reply.after)
  }

  /// Material, centre and development, in centipawns from White's side.
  public static func evaluate(_ fen: String) -> Double {
    let values: [PieceType: Double] = [.p: 100, .n: 300, .b: 320, .r: 500, .q: 900, .k: 0]
    var score = 0.0
    for piece in piecesFromFen(fen) {
      let sign: Double = piece.color == .w ? 1 : -1
      score += sign * values[piece.type]!
      let file = Double(Int(piece.square.unicodeScalars.first!.value) - 97)
      let rank = Double(Int(piece.square.unicodeScalars.last!.value) - 49)
      let centre = 3.5 - max(abs(file - 3.5), abs(rank - 3.5))
      switch piece.type {
      case .n, .b: score += sign * centre * 6
      case .p: score += sign * (centre * 3 + (piece.color == .w ? rank - 1 : 6 - rank) * 2)
      default: break
      }
    }
    return score
  }
}
