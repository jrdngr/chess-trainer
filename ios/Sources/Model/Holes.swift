import Book
import ChessCore
import Shared

/// Holes: replies you have no answer to. The part of `src/model/growth.ts`
/// a run's draw and Grow this line need.

/// How often a hole comes up, in percent, for ranking.
public func holeShare(share: Double, kept: Bool) -> Double {
  kept ? max(share, PREPARED_FLOOR * 100) : share
}

public func holeShare(_ hole: Hole) -> Double { holeShare(share: hole.share, kept: hole.kept) }

/// The least popular a reply can be and still be worth preparing for.
public let DEFAULT_MIN_SHARE: Double = 1
/// The most one batch of answers may add.
public let MAX_ADDS = 8
/// Past here, a line running out is play rather than a hole in the prep.
public let DEFAULT_MAX_PLY = 18

/// How many moves are worth adding at a hole this far into a line.
public func movesToFit(_ depth: Int, _ maxPly: Int = 18) -> Int {
  max(1, Int(JS.round(Double(maxPly - depth) / 2)))
}

/// What a batch of answers may add, starting at this depth.
public func addsToFit(_ depth: Int, _ maxPly: Int = DEFAULT_MAX_PLY) -> Int {
  min(MAX_ADDS, movesToFit(depth, maxPly))
}

public struct GrowthOptions {
  public var minShare: Double?
  public var maxPly: Int?
  public var starred: [String]?
  /// Only holes that lead into this region, or toward it.
  public var region: (tree: OpeningTree, node: OpeningNode)?
  public var pastBook: Bool?
  public init(minShare: Double? = nil, maxPly: Int? = nil, starred: [String]? = nil, region: (tree: OpeningTree, node: OpeningNode)? = nil, pastBook: Bool? = nil) {
    self.minShare = minShare
    self.maxPly = maxPly
    self.starred = starred
    self.region = region
    self.pastBook = pastBook
  }
}

/// A reply you have no answer to.
public struct Hole: Equatable, Sendable {
  /// Moves from the start to the position the opponent chooses in.
  public var path: [String]
  public var fen: String
  /// The reply you cannot meet.
  public var san: String
  public var share: Double
  public var games: Double
  /// The position the reply leads to.
  public var after: String
  /// The tree node the opponent moved from, or nil at the root.
  public var nodeId: String?
  /// In your tree already, with nothing after it.
  public var kept = false
  /// Past the book: one of the engine's top replies, with no share.
  public var engine = false
  /// The share of games that get to this position, 0...1.
  public var reach: Double

  public init(path: [String], fen: String, san: String, share: Double, games: Double, after: String, nodeId: String?, kept: Bool = false, engine: Bool = false, reach: Double) {
    self.path = path
    self.fen = fen
    self.san = san
    self.share = share
    self.games = games
    self.after = after
    self.nodeId = nodeId
    self.kept = kept
    self.engine = engine
    self.reach = reach
  }
}

/// A reply the opponent might play, with how often the book sees it.
public struct Reply: Equatable, Sendable {
  public var san: String
  public var games: Double
  public var white: Double
  public var draw: Double
  public var black: Double
  public var share: Double
  public var engine = false
  /// Where the move leads, when the book links it.
  public var next: String?

  public init(san: String, games: Double, white: Double, draw: Double, black: Double, share: Double, engine: Bool = false, next: String? = nil) {
    self.next = next
    self.san = san
    self.games = games
    self.white = white
    self.draw = draw
    self.black = black
    self.share = share
    self.engine = engine
  }
}

struct Choice {
  var path: [String]
  var fen: String
  var nodeId: String?
  var reach: Double
  var replies: [Reply]
  var prepared: Set<String>
  var answered: Set<String>
  var kept: [RepMove]
  var bookless: Bool
}

/// What a move the book has never seen is worth, so a line through it is not lost.
private let RARE = 0.0001

/// Every position inside a repertoire where the opponent has the move.
func walkChoices(_ rep: Repertoire, _ index: ReferenceIndex, _ opts: GrowthOptions, _ visit: (Choice) -> Void) {
  let minShare = opts.minShare ?? DEFAULT_MIN_SHARE
  let maxPly = opts.maxPly ?? DEFAULT_MAX_PLY
  var seen = Set<String>()
  let wanted = { (line: [String]) -> Bool in
    guard let region = opts.region else { return true }
    return lineInRegion(region.tree, region.node, line)
  }
  let preparedAt = Set(rep.nodes.values.map(\.key))

  func walk(_ nodeId: String?, _ path: [String], _ reach: Double) {
    let fen = fenAt(rep, nodeId)
    let kids = childrenOf(rep, nodeId)
    let theirs = fenTurn(fen) != rep.color
    if path.count < maxPly && theirs {
      let key = positionKey(fen)
      if seen.insert(key).inserted {
        let bookless = popularReplies(index, fen, 0).isEmpty
        let replies = bookless ? Array(engineAsReplies(fen).prefix(ENGINE_THEIR_REPLIES)) : popularReplies(index, fen, minShare)
        let answered = kids.filter { childrenOf(rep, $0.id).count > 0 || preparedAt.contains(positionKey($0.fenAfter)) }
        let answeredIds = Set(answered.map(\.id))
        visit(Choice(
          path: path, fen: fen, nodeId: nodeId, reach: reach,
          replies: replies.filter { wanted(path + [$0.san]) },
          prepared: Set(kids.map(\.san)), answered: Set(answered.map(\.san)),
          kept: kids.filter { !answeredIds.contains($0.id) && wanted(path + [$0.san]) },
          bookless: bookless))
      }
    }
    if path.count >= maxPly { return }
    // Only their moves narrow the field.
    let shares = theirs ? shareMap(index, fen, kids.map(\.san)) : nil
    for kid in kids where wanted(path + [kid.san]) {
      walk(kid.id, path + [kid.san], shares.map { reach * ($0[kid.san] ?? RARE) } ?? reach)
    }
  }
  walk(nil, [], 1)
}

/// How often each move at a position comes up, 0...1, prepared replies lifted to the floor.
private func shareMap(_ index: ReferenceIndex, _ fen: String, _ prepared: [String]) -> [String: Double] {
  let entry = lookup(index, fen)
  let total = entry.map { totalGamesAt($0) } ?? 0
  var out: [String: Double] = [:]
  guard let entry, total != 0 else {
    for san in prepared { out[san] = max(1 / Double(prepared.count), RARE) }
    return out
  }
  let book = entry.moves.map(\.san)
  let sans = book + prepared.filter { !book.contains($0) }
  var games: [String: Double] = [:]
  for move in entry.moves where games[move.san] == nil { games[move.san] = move.games }
  let shares = withFloor(sans.map { games[$0] ?? 0 }, sans.map { prepared.contains($0) })
  for (i, san) in sans.enumerated() { out[san] = max(shares[i], RARE) }
  return out
}

/// The engine's moves at a position the book does not know, as replies with no share.
private func engineAsReplies(_ fen: String) -> [Reply] {
  (engineReplies(fen) ?? []).map { Reply(san: $0, games: 0, white: 0, draw: 0, black: 0, share: 0, engine: true) }
}

/// Every unanswered reply in a repertoire, shallowest and most popular first.
public func findHoles(_ rep: Repertoire, _ index: ReferenceIndex, _ opts: GrowthOptions = GrowthOptions()) -> [Hole] {
  var holes: [Hole] = []
  walkChoices(rep, index, opts) { choice in
    func push(_ move: Reply, _ kept: Bool) {
      guard let after = applySan(choice.fen, move.san) else { return }
      holes.append(Hole(
        path: choice.path, fen: choice.fen, san: move.san, share: move.share, games: move.games, after: after.after,
        nodeId: choice.nodeId, kept: kept, engine: move.engine, reach: choice.reach))
    }
    for move in choice.replies where !choice.answered.contains(move.san) { push(move, choice.prepared.contains(move.san)) }
    // A reply you kept with no answer is a hole however rarely it is played.
    for kid in choice.kept where !choice.replies.contains(where: { $0.san == kid.san }) {
      let book = popularReplies(index, choice.fen, 0).first { $0.san == kid.san }
      push(book ?? Reply(san: kid.san, games: 0, white: 0, draw: 0, black: 0, share: 0), true)
    }
  }
  return holes.jsSorted { a, b in
    let depth = Double(a.path.count - b.path.count)
    return depth != 0 ? depth : b.share - a.share
  }
}

/// Book replies at a position played often enough to prepare for.
public func popularReplies(_ index: ReferenceIndex, _ fen: String, _ minShare: Double) -> [Reply] {
  guard let entry = lookup(index, fen) else { return [] }
  let total = totalGamesAt(entry)
  if total == 0 { return [] }
  return entry.moves
    .map { Reply(san: $0.san, games: $0.games, white: $0.white, draw: $0.draw, black: $0.black, share: JS.round($0.games / total * 1000) / 10, next: $0.next) }
    .filter { $0.share >= minShare }
    .jsSorted { cmp($1.games, $0.games) }
}
