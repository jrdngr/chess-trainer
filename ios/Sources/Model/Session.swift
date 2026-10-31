import ChessCore
import Shared

/// Lining positions up into a sitting: the session half of `src/model/session.ts`.
/// The items are `TrainingItems.swift`; `weakness` and `weakestFirst` are in `Autopilot.swift`.

/// Items restricted to the subtree under `nodeId`, its own position included.
public func branchItems(_ rep: Repertoire, _ nodeId: String) -> [TrainingItem] {
  let ids = Set(subtreeIds(rep, nodeId))
  let node = rep.nodes[nodeId]
  return decisionPoints(rep).compactMap { dp in
    let inBranch = dp.options.contains { ids.contains($0.id) }
    let isTheNodeItself = node.map { fenTurn($0.fenAfter) == rep.color && dp.fen == $0.fenAfter } ?? false
    return inBranch || isTheNodeItself ? buildItem(rep, dp) : nil
  }
}

/// The sitting opens on a position with moves leading to it: a move-one
/// position is moved behind the first that has a way in.
public func leadWithAWayIn(_ queue: [TrainingItem]) -> [TrainingItem] {
  guard let first = queue.first, first.pathSans.isEmpty else { return queue }
  guard let at = queue.firstIndex(where: { !$0.pathSans.isEmpty }) else { return queue }
  return [queue[at]] + queue[0..<at] + queue[(at + 1)...]
}

public enum SessionMode: String, Sendable, Codable {
  case due, branch, repertoire, cram, new
}

public struct SessionOptions: Sendable {
  public var mode: SessionMode
  public var now: Double
  public var maxItems: Int
  public var maxNew: Int
  /// Deterministic shuffle seed.
  public var seed: Double
  public init(mode: SessionMode, now: Double, maxItems: Int, maxNew: Int, seed: Double = 1) {
    self.mode = mode
    self.now = now
    self.maxItems = maxItems
    self.maxNew = maxNew
    self.seed = seed
  }
}

/// Fisher–Yates, as the prototype draws it.
public func shuffle<T>(_ arr: [T], _ rand: () -> Double) -> [T] {
  var out = arr
  var i = out.count - 1
  while i > 0 {
    let j = Int((rand() * Double(i + 1)).rounded(.down))
    out.swapAt(i, j)
    i -= 1
  }
  return out
}

private func isFresh(_ card: Card?) -> Bool { card == nil || card!.stage == .new }

/// Order candidate items into a queue: due reviews and learning cards
/// shuffled together, then a capped number of new positions, shallow first,
/// woven in.
public func buildSession(_ items: [TrainingItem], _ cards: [String: Card], _ opts: SessionOptions) -> [TrainingItem] {
  let rand = mulberry32(seed: opts.seed)
  let withCard = items.map { (item: $0, card: cards[$0.cardId]) }
  let shallowFirst = { (a: (item: TrainingItem, card: Card?), b: (item: TrainingItem, card: Card?)) in cmp(a.item.depth, b.item.depth) }

  switch opts.mode {
  case .cram, .branch, .repertoire:
    return Array(withCard.jsSorted(shallowFirst).prefix(max(0, opts.maxItems)).map(\.item))
  case .new:
    return Array(withCard.filter { isFresh($0.card) }.jsSorted(shallowFirst).prefix(max(0, min(opts.maxItems, opts.maxNew))).map(\.item))
  case .due:
    break
  }
  func due(_ stage: CardStage) -> [(item: TrainingItem, card: Card?)] {
    withCard.filter { $0.card?.stage == stage && isDue($0.card!, opts.now) }.jsSorted { cmp($0.card!.due, $1.card!.due) }
  }
  let fresh = withCard.filter { isFresh($0.card) }.jsSorted(shallowFirst).prefix(max(0, opts.maxNew))
  let head = shuffle(due(.review) + due(.learning), rand).map(\.item)
  return Array(interleave(head, fresh.map(\.item)).prefix(max(0, opts.maxItems)))
}

/// What to practise once nothing is due: the least recently practised, a
/// generous slice of them shuffled.
public func extraPractice(
  _ items: [TrainingItem], _ cards: [String: Card], _ count: Int, _ rand: () -> Double, _ skip: (String) -> Bool = { _ in false }
) -> [TrainingItem] {
  let pool = items.filter { !skip($0.cardId) }
    .map { (item: $0, seen: cards[$0.cardId]?.lastReviewed ?? 0) }
    .jsSorted { cmp($0.seen, $1.seen) }
  let slice = Array(pool.prefix(max(0, max(count, min(pool.count, count * 3)))))
  return shuffle(slice, rand).prefix(max(0, count)).map(\.item)
}

/// Spread `b` evenly through `a` rather than appending it.
public func interleave<T>(_ a: [T], _ b: [T]) -> [T] {
  if b.isEmpty { return a }
  if a.isEmpty { return b }
  var out: [T] = []
  let gap = Double(a.count) / Double(b.count)
  var bi = 0
  for i in 0..<a.count {
    out.append(a[i])
    while bi < b.count && Double(bi + 1) * gap <= Double(i + 1) {
      out.append(b[bi])
      bi += 1
    }
  }
  out.append(contentsOf: b[bi...])
  return out
}

public struct AnswerCheck: Equatable, Sendable {
  public var correct: Bool
  /// The expected move that matched, when correct.
  public var matched: ExpectedMove?
  /// The preferred move, present whenever the item has options.
  public var preferred: ExpectedMove?
}

/// A played SAN against what the position expects.
public func checkAnswer(_ item: TrainingItem, _ playedSan: String) -> AnswerCheck {
  let preferred = item.expected.first(where: \.preferred) ?? item.expected.first
  let matched = item.expected.first { $0.san == playedSan }
  return AnswerCheck(correct: matched != nil, matched: matched, preferred: preferred)
}
