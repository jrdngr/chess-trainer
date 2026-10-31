import Book
import ChessCore
import Shared

/// Tidy: finding the places a repertoire could converge. `src/model/tidy.ts`.
///
/// Every move you have chosen is compared with the moves you could have chosen
/// instead, by the same familiarity the Growth arrows use. Where another move
/// is closer to the rest of your lines than yours, that is a find: switch to
/// it, and your move and everything under it go. Your own move is judged
/// against the repertoire *without* its subtree, so it gets no credit for being
/// the line it already is.

public struct TidyFind: Equatable, Sendable {
  /// Stable while the line is unchanged: the repertoire and your move's node.
  public var id: String
  public var repertoireId: String
  public var color: Color
  /// Your move at the position.
  public var nodeId: String
  public var mine: String
  /// The line to the position, and the position itself.
  public var path: [String]
  public var fen: String
  public var key: String
  /// The move to switch to, and what makes it familiar.
  public var suggestion: String
  public var kind: TowardKind
  /// Green when the board would draw it anyway; yellow when it is pulled in.
  public var tone: NudgeTone
  /// A move the book does not have (or ranks under the minimum): the engine must pass it first.
  public var offBook: Bool
  public var reason: String
  /// Why your move works against your lines, when it does.
  public var against: String?
  /// Moves the switch removes: your move and everything under it.
  public var removes: Int
}

public struct TidyOptions: Sendable {
  public var prefs: NudgePrefs
  /// The least share of games a book move needs to be offered, in percent.
  public var minShare: Double
  public init(prefs: NudgePrefs, minShare: Double) {
    self.prefs = prefs
    self.minShare = minShare
  }
}

/// The one switch that would tidy a position, or nil when your move is as familiar as any.
public func findAt(_ rep: Repertoire, _ index: ReferenceIndex, _ node: RepMove, _ opts: TidyOptions, _ candidates: [String]? = nil) -> TidyFind? {
  let line = pathTo(rep, node.parentId)
  let path = line.map(\.san)
  // Your first move picks the opening; two first moves are two openings, not a loose end.
  if isFirstMove(path) { return nil }
  let fen = node.fenBefore
  let gone = goneWith(rep, index, node.id)
  let keys = [positionKey(rep.rootFen)] + line.map { positionKey($0.fenAfter) }
  let siblings = Set(childrenOf(rep, node.parentId).map(\.san))
  let book = popularReplies(index, fen, opts.minShare).map(\.san)
  let signalOpts = SignalOptions(gone: gone, pathKeys: keys)
  let extra = candidates != nil
    ? []
    : familiarOffBook(rep, index, path, fen, opts.prefs, opts.minShare, signalOpts, habitsOnly: true)
  let options = (candidates ?? book + extra).filter { !siblings.contains($0) }
  if options.isEmpty { return nil }

  // Moves handed in are the one just played over the board.
  guard let best = bestSwitch(
    rep, index, path, fen, node.san, options, opts.prefs, opts.minShare, signalOpts, against: false, played: candidates != nil)
  else { return nil }
  let drawn = Set(movesToDraw(index, fen).map(\.san))
  return TidyFind(
    id: "\(rep.id)#\(node.id)", repertoireId: rep.id, color: rep.color, nodeId: node.id, mine: node.san, path: path,
    fen: fen, key: node.key, suggestion: best.san, kind: best.kind, tone: drawn.contains(best.san) ? .toward : .towardFar,
    offBook: !book.contains(best.san), reason: best.reason, against: best.against, removes: subtreeIds(rep, node.id).count)
}

/// Your moves in a repertoire: the positions where you chose.
public func yourMoves(_ rep: Repertoire) -> [RepMove] {
  nodesInOrder(rep).filter { fenTurn($0.fenBefore) == rep.color }
}

/// The positions a scan looks at: your moves inside a region. A position met
/// by two move orders is one decision, so it is looked at once.
public func tidyPositions(_ reps: [Repertoire], _ tree: OpeningTree, _ region: OpeningNode) -> [(rep: Repertoire, node: RepMove)] {
  var out: [(rep: Repertoire, node: RepMove)] = []
  for rep in reps {
    var seen = Set<String>()
    for node in yourMoves(rep) where seen.insert("\(node.key)|\(node.san)").inserted {
      if lineInRegion(tree, region, pathTo(rep, node.parentId).map(\.san)) { out.append((rep, node)) }
    }
  }
  return out
}

public func sortFinds(_ finds: [TidyFind]) -> [TidyFind] {
  finds.jsSorted { a, b in
    let d = b.removes - a.removes
    return Double(d != 0 ? d : a.path.count - b.path.count)
  }
}

/// The hint at the end of a round: was the move you played off your prep
/// closer to the rest of your lines than the prepared one? The prepared move
/// is found by position, since a round can reach it by another move order.
public func offPrepHint(
  _ rep: Repertoire?, _ index: ReferenceIndex, _ fen: String, _ played: String, _ expected: String, _ opts: TidyOptions
) -> TidyFind? {
  guard let rep else { return nil }
  let key = positionKey(fen)
  guard let node = nodesInOrder(rep).first(where: { $0.key == key && $0.san == expected }) else { return nil }
  return findAt(rep, index, node, opts, [played])
}

/// Switch your move at a position: the new move becomes yours there, and the
/// old one goes with everything under it. Nil when the move is not legal.
public func switchMove(_ rep: Repertoire, _ nodeId: String, _ san: String) -> Repertoire? {
  guard let old = rep.nodes[nodeId], let added = addMove(rep, old.parentId, san, .tidy) else { return nil }
  return removeSubtree(setPreferred(added.rep, added.node.id), nodeId)
}

/// "6.g3", "6...Nf6": a move with its number, from the plies before it.
public func moveLabel(_ ply: Int, _ san: String) -> String {
  "\(ply / 2 + 1)\(ply % 2 == 0 ? "." : "...")\(san)"
}
