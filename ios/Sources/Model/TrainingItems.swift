import ChessCore

/// The positions you answer, as the training screens ask them: the item half of `src/model/session.ts`.

public struct ExpectedMove: Equatable, Sendable {
  public var nodeId: String
  public var san: String
  public var preferred: Bool
  public var note: String?
}

/// Everything a screen needs to ask one question.
public struct TrainingItem: Equatable, Sendable {
  public var cardId: String
  public var repertoireId: String
  public var repertoireName: String
  public var key: String
  public var fen: String
  public var orientation: Color
  public var expected: [ExpectedMove]
  /// SAN path from the start to this position.
  public var pathSans: [String]
  /// The preferred continuation after the answer.
  public var continuation: [String]
  public var depth: Int
}

public func cardId(_ repertoireId: String, _ key: String) -> String {
  "\(repertoireId)#\(key)"
}

/// Follow preferred children from a node for up to `plies` moves.
private func preferredContinuation(_ rep: Repertoire, _ nodeId: String, _ plies: Int) -> [String] {
  var out: [String] = []
  var cur: String? = nodeId
  for _ in 0..<plies {
    guard let at = cur else { break }
    let kids = childrenOf(rep, at)
    guard let next = kids.first(where: \.preferred) ?? kids.first else { break }
    out.append(next.san)
    cur = next.id
  }
  return out
}

public func buildItem(_ rep: Repertoire, _ dp: DecisionPoint) -> TrainingItem {
  let preferred = dp.options.first(where: \.preferred) ?? dp.options.first
  return TrainingItem(
    cardId: cardId(rep.id, dp.key), repertoireId: rep.id, repertoireName: rep.name, key: dp.key, fen: dp.fen,
    orientation: rep.color,
    expected: dp.options.map { ExpectedMove(nodeId: $0.id, san: $0.san, preferred: $0.preferred, note: $0.note) },
    pathSans: dp.pathSans,
    continuation: preferred.map { [$0.san] + preferredContinuation(rep, $0.id, 5) } ?? [],
    depth: dp.depth)
}

/// Every position to answer across the trees.
public func allItems(_ reps: [Repertoire]) -> [TrainingItem] {
  reps.flatMap { rep in decisionPoints(rep).map { buildItem(rep, $0) } }
}
