import Book
import ChessCore
import Shared

/// Line drills: Drill's way of asking a whole line from move one.
/// Each line has its own `LineCard`, moved only by
/// the one grade given at its end.

public struct DrillLine: Equatable, Sendable {
  public var repertoireId: String
  public var color: Color
  /// The leaf the line ends on.
  public var tipId: String
  public var sans: [String]
  public init(repertoireId: String, color: Color, tipId: String, sans: [String]) {
    self.repertoireId = repertoireId
    self.color = color
    self.tipId = tipId
    self.sans = sans
  }
}

/// What a drawn line leans toward.
public enum LineLean: String, Sendable { case popular, weak }

/// Your moves along a line: the positions it asks you, by key.
public func askedKeys(_ rep: Repertoire, _ tipId: String) -> [String] {
  pathTo(rep, tipId).filter { fenTurn($0.fenBefore) == rep.color }.map(\.key)
}

/// Every leaf line of yours that reaches the region and asks you at least one move.
public func drillableLines(_ rep: Repertoire, _ tree: OpeningTree, _ region: OpeningNode) -> [DrillLine] {
  leafLines(rep)
    .filter { lineStatus(tree, region, $0.sans) == .reached }
    .filter { !askedKeys(rep, $0.tipId).isEmpty }
    .map { DrillLine(repertoireId: rep.id, color: rep.color, tipId: $0.tipId, sans: $0.sans) }
}

/// How much a line wants practice, from its card. Only compared, so the scale does not matter.
public func lineCardWeakness(_ card: LineCard?, _ now: Double = Env.now()) -> Double {
  guard let card else { return 1.5 }
  var score = 1 + Double(card.lapses) * 1.2 + max(0, 2.5 - card.ease) * 2
  if card.stage == .learning { score += 1 }
  if card.due <= now { score += 1 }
  let answered = card.correct + card.incorrect
  if answered > 0 { score += Double(card.incorrect) / Double(answered) * 2 }
  return score
}

/// Lines whose card is due.
public func dueLines(_ lines: [DrillLine], _ cards: [String: LineCard], _ now: Double = Env.now()) -> [DrillLine] {
  lines.filter { line in cards[lineCardId(line.repertoireId, line.tipId)].map { isDue($0, now) } ?? false }
}

/// The most of your own moves a sized round asks, and the most lines in it.
public let LINE_BUDGET = 15
public let MAX_LINES = 3

/// Whether it is your move at this ply of a line.
public func yoursAt(_ color: Color, _ ply: Int) -> Bool {
  (ply % 2 == 0) == (color == .w)
}

/// How many of your own moves a line asks.
public func yourMoves(_ line: DrillLine) -> Int {
  line.sans.indices.filter { yoursAt(line.color, $0) }.count
}

/// How many moves two lines share from the start.
public func sharedMoves(_ a: [String], _ b: [String]) -> Int {
  var n = 0
  while n < a.count && n < b.count && a[n] == b[n] { n += 1 }
  return n
}

public struct DrawOptions {
  public var rep: Repertoire
  public var tree: OpeningTree
  public var region: OpeningNode
  public var index: ReferenceIndex?
  public var lean: LineLean
  public var cards: [String: LineCard] = [:]
  public var draw: DrillDraw?
  public var only: Set<String>?
  public var avoid: Set<String>?
  public var count: Int
  public var budget: Int?
  public var similar = false
  public var rand: () -> Double
  public var now: Double?
  public init(
    rep: Repertoire, tree: OpeningTree, region: OpeningNode, index: ReferenceIndex?, lean: LineLean,
    cards: [String: LineCard] = [:], draw: DrillDraw? = nil, only: Set<String>? = nil, avoid: Set<String>? = nil,
    count: Int, budget: Int? = nil, similar: Bool = false, rand: @escaping () -> Double, now: Double? = nil
  ) {
    self.rep = rep
    self.tree = tree
    self.region = region
    self.index = index
    self.lean = lean
    self.cards = cards
    self.draw = draw
    self.only = only
    self.avoid = avoid
    self.count = count
    self.budget = budget
    self.similar = similar
    self.rand = rand
    self.now = now
  }
}

/// Draw up to `count` different lines: by tier (`draw`), then in proportion
/// to how often you would meet each, times its weakness when leaning weak.
/// `DrawOptions` documents `only`, `avoid`, `budget` and `similar`.
public func drawLines(_ o: DrawOptions) -> [DrillLine] {
  let rep = o.rep
  let now = o.now ?? Env.now()
  var lines = drillableLines(rep, o.tree, o.region)
  if let only = o.only, !only.isEmpty {
    let held = lines.filter { only.contains($0.tipId) }
    if !held.isEmpty { lines = held }
  }
  if let avoid = o.avoid, !avoid.isEmpty {
    let rest = lines.filter { !avoid.contains($0.tipId) }
    if !rest.isEmpty { lines = rest }
  }
  if lines.isEmpty { return [] }
  let odds = lineOdds(rep, rep.color, o.index, Set(lines.map(\.tipId)))
  let cardOf = { (line: DrillLine) in o.cards[lineCardId(line.repertoireId, line.tipId)] }
  let weight = { (line: DrillLine) -> Double in
    let meet = odds.isEmpty ? 1 : (odds[line.tipId] ?? 0)
    let want = o.lean == .weak ? lineCardWeakness(cardOf(line), now) : 1
    return meet * want
  }
  let due = Set(dueLines(lines, o.cards, now).map(\.tipId))
  let tier = { (line: DrillLine) -> Int in
    let draw = o.draw ?? .cram
    if draw == .cram { return 0 }
    let fresh = cardOf(line) == nil
    if draw == .new { return fresh ? 0 : 1 }
    return due.contains(line.tipId) ? 0 : fresh ? 1 : 2
  }

  var drawn: [DrillLine] = []
  for level in [0, 1, 2] {
    var pool = lines.filter { tier($0) == level }
    while !pool.isEmpty {
      let total = pool.reduce(0) { $0 + weight($1) }
      var at = 0
      if total > 0 {
        var roll = o.rand() * total
        at = pool.firstIndex { line in
          roll -= weight(line)
          return roll <= 0
        } ?? pool.count - 1
      } else {
        at = Int((o.rand() * Double(pool.count)).rounded(.down))
      }
      drawn.append(pool.remove(at: at))
    }
  }

  let first = drawn[0]
  let others = Array(drawn.dropFirst())
  let ordered = o.similar
    ? others.enumerated().map { (line: $0.element, i: $0.offset, shared: sharedMoves($0.element.sans, first.sans)) }
      .jsSorted { cmp($1.shared, $0.shared) != 0 ? cmp($1.shared, $0.shared) : cmp($0.i, $1.i) }
      .map(\.line)
    : others
  var out = [first]
  var moves = yourMoves(first)
  for line in ordered {
    if out.count >= o.count { break }
    if let budget = o.budget, moves + yourMoves(line) > budget { continue }
    out.append(line)
    moves += yourMoves(line)
  }
  return o.count > 0 ? out : []
}

/// A line to carry on along after another of your prepared moves: the
/// played moves, then your preferred continuation to a leaf.
public func continueLine(_ rep: Repertoire, _ prefix: [String]) -> DrillLine? {
  guard var node = nodeAtLine(rep, prefix) else { return nil }
  var sans = prefix
  while true {
    let kids = childrenOf(rep, node.id)
    guard let next = kids.first(where: \.preferred) ?? kids.first else { break }
    node = next
    sans.append(node.san)
  }
  return DrillLine(repertoireId: rep.id, color: rep.color, tipId: node.id, sans: sans)
}
