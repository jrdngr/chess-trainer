import Foundation
import ChessCore
import Shared

/// What Autopilot's next Survival run should be: an opening inside the
/// selection, a colour, and a focus. `src/model/recommend.ts`.

public enum Focus: String, Sendable, Codable, CaseIterable {
  case test, review
}

public let FOCUSES = Focus.allCases
public let DEPTH = 0.6
public let STALENESS = 2.0
public let BRAKE = 0.5
public let BRAKE_WINDOW = 5
public let STEER_GAP = 3

/// Whether one of the last few rounds was steered below the selection.
public func steeredRecently(_ recentSteered: [Bool]) -> Bool {
  recentSteered.suffix(STEER_GAP).contains(true)
}

/// The share of its parent's work a variation must hold to be steered toward.
public func narrowingBar(_ level: Int) -> Double {
  let at = Double(max(1, level))
  return at / (at + 1)
}

/// A star is worth one level.
public func effectiveLevel(_ level: Int, _ starred: Bool) -> Int {
  max(0, level - (starred ? 1 : 0))
}

/// Whether a round on this opening starts in its position rather than from move one.
public func startsInside(_ opening: OpeningNode) -> Bool {
  opening.depth >= 2
}

public enum Start: String, Sendable, Codable {
  case first, inside
}

public struct Recommendation: Sendable {
  public var focus: Focus
  public var opening: OpeningNode
  public var color: Color
  public var start: Start
  public init(focus: Focus, opening: OpeningNode, color: Color, start: Start) {
    self.focus = focus
    self.opening = opening
    self.color = color
    self.start = start
  }
}

/// Whether a round was steered: started inside an opening below the selection.
public func isSteered(opening: OpeningNode, start: Start, _ selection: Selection) -> Bool {
  start == .inside && opening.id != selection.opening
}

public struct Candidate: Equatable, Sendable {
  public var focus: Focus
  public var openingId: String
  public var color: Color
  /// 0...1, how loudly this asks.
  public var need: Double
  /// Pieces of work strictly inside this opening.
  public var work: Int
  public var lastAt: Double?
  public var starred: Bool
  /// Levels below the selection.
  public var level: Int
  /// need × staleness × depth × brake.
  public var score: Double = 0

  public init(focus: Focus, openingId: String, color: Color, need: Double, work: Int, lastAt: Double?, starred: Bool, level: Int) {
    self.focus = focus
    self.openingId = openingId
    self.color = color
    self.need = need
    self.work = work
    self.lastAt = lastAt
    self.starred = starred
    self.level = level
  }
}

/// A game of yours, as Repair reads it: what the recommendation weighs.
public struct RepairRef: Sendable {
  public var kind: String
  public var color: Color
  public var fen: String
  public init(kind: String, color: Color, fen: String) {
    self.kind = kind
    self.color = color
    self.fen = fen
  }
}

public struct RecommendInput {
  public var tree: OpeningTree
  public var selection: Selection
  public var reps: [Repertoire]
  public var cards: [String: Card]
  public var repairs: [RepairRef]
  public var score: ScoreState
  public var starred: [String]
  public var newPerSession: Int
  /// The focuses of the session's rounds so far, oldest first.
  public var recentFocuses: [Focus]
  public var recentSteered: [Bool] = []
  public var seen: Seen?
  public var now: Double?

  public init(tree: OpeningTree, selection: Selection, reps: [Repertoire], cards: [String: Card], repairs: [RepairRef] = [], score: ScoreState, starred: [String], newPerSession: Int, recentFocuses: [Focus]) {
    self.tree = tree
    self.selection = selection
    self.reps = reps
    self.cards = cards
    self.repairs = repairs
    self.score = score
    self.starred = starred
    self.newPerSession = newPerSession
    self.recentFocuses = recentFocuses
  }
}

/// Diminishing returns on a count: `half` scores 0.5.
public func saturate(_ count: Double, _ half: Double) -> Double {
  count <= 0 ? 0 : count / (count + half)
}

private func clamp(_ n: Double) -> Double { max(0, min(1, n)) }

/// Review debt: due cards lead; unseen positions are never urgent.
public func reviewNeed(_ due: Int, _ unseen: Int, _ newPerSession: Int) -> Double {
  let review = 0.9 * saturate(Double(due), 24)
  let learn = 0.5 * saturate(Double(min(unseen, max(newPerSession, 0))), 4)
  return clamp(max(review, learn))
}

public let TEST_FLOOR = 0.25

/// A Test's need: more for prep added since, mostly as loud as its line has been left.
public func testNeed(_ untested: Int, _ everRun: Bool, _ stalest: Double = 1) -> Double {
  let base = 0.4 + 0.4 * saturate(Double(untested), 10)
  let left = TEST_FLOOR + (1 - TEST_FLOOR) * clamp(stalest)
  return clamp((everRun ? base : max(base, 0.55)) * left)
}

/// How many of the last few rounds were this focus.
public func recentCount(_ recentFocuses: [Focus], _ focus: Focus) -> Int {
  recentFocuses.suffix(BRAKE_WINDOW).filter { $0 == focus }.count
}

private let ORDER: [Focus: Double] = [.test: 0, .review: 1]

/// Score and sort, best first. Staleness is read off the other candidates.
public func rank(_ list: [Candidate], _ recentFocuses: [Focus]) -> [Candidate] {
  let when = { (c: Candidate) in c.lastAt ?? 0 }
  let scored = list.map { cand -> Candidate in
    let staler = list.filter { when($0) < when(cand) }.count
    let freshness = list.count < 2 ? 1 : 1 - Double(staler) / Double(list.count - 1)
    let brake = pow(BRAKE, Double(recentCount(recentFocuses, cand.focus)))
    let depth = pow(DEPTH, Double(effectiveLevel(cand.level, cand.starred)))
    var out = cand
    out.score = cand.need * (1 + STALENESS * freshness) * depth * brake
    return out
  }
  return scored.jsSorted { a, b in
    if b.score != a.score { return b.score - a.score }
    if b.need != a.need { return b.need - a.need }
    if ORDER[a.focus]! != ORDER[b.focus]! { return ORDER[a.focus]! - ORDER[b.focus]! }
    let id = JS.localeCompare(a.openingId, b.openingId)
    if id != 0 { return Double(id) }
    return Double(JS.localeCompare(a.color.rawValue, b.color.rawValue))
  }
}

private struct Placed<T> {
  var item: T
  var regions: [String: LineStatus]
}

private func place<T>(_ tree: OpeningTree, _ nodes: [OpeningNode], _ items: [T], _ line: (T) -> [String]) -> [Placed<T>] {
  items.map { Placed(item: $0, regions: regionsOf(tree, nodes, line($0))) }
}

private func within<T>(_ placed: [Placed<T>], _ node: OpeningNode) -> [T] {
  placed.filter { $0.regions[node.id] != .outside }.map(\.item)
}

private func reachedIn<T>(_ placed: [Placed<T>], _ node: OpeningNode) -> [T] {
  placed.filter { $0.regions[node.id] == .reached }.map(\.item)
}

/// Every move in a repertoire, with the line that reaches it.
private func repMoves(_ rep: Repertoire) -> [(sans: [String], addedAt: Double)] {
  var out: [(sans: [String], addedAt: Double)] = []
  func visit(_ ids: [String], _ path: [String]) {
    for id in ids {
      guard let node = rep.nodes[id] else { continue }
      let line = path + [node.san]
      out.append((line, node.addedAt))
      visit(node.children, line)
    }
  }
  visit(rep.rootChildren, [])
  return out
}

/// Every (focus, opening, colour) that could be started now, with its need.
public func candidates(_ input: RecommendInput) -> [Candidate] {
  let tree = input.tree, score = input.score
  let region = nodeById(tree, input.selection.opening)
  let nodes = [region] + descendantsOf(region)
  var out: [Candidate] = []
  let now = input.now ?? Env.now()
  let lastAt = { (id: String) in nodeStats(score, id).byMode[.run]?.lastAt }
  let everRun = (score.global.byMode[.run]?.rounds ?? 0) > 0
  func push(_ focus: Focus, _ node: OpeningNode, _ color: Color, _ need: Double, _ work: Int) {
    if need <= 0 { return }
    out.append(Candidate(
      focus: focus, openingId: node.id, color: color, need: need, work: work, lastAt: lastAt(node.id),
      starred: starredWithin(tree, node.id, input.starred), level: node.depth - region.depth))
  }

  for color in colorsOf(input.selection.color) {
    let reps = input.reps.filter { $0.color == color }
    if reps.isEmpty { continue }
    let repairs = input.repairs.filter { $0.color == color }
    let items = place(tree, nodes, allItems(reps), \.pathSans)
    let moves = place(tree, nodes, reps.flatMap(repMoves), \.sans)
    let seen = input.seen ?? NOTHING_SEEN
    let lines = place(tree, nodes, reps.flatMap { rep in
      leafLines(rep).map { (sans: $0.sans, stale: lineStaleness(seen, rep, $0.tipId)) }
    }, \.sans)
    let slipped = Set(repairs.filter { $0.kind == "offprep" }.map { positionKey($0.fen) })

    for node in nodes {
      let mine = reachedIn(moves, node)
      if mine.isEmpty { continue }
      let wanting = { (item: TrainingItem) -> Bool in
        guard let card = input.cards[item.cardId] else { return true }
        return runNeed(card, score.lineRounds, now) >= 1 || slipped.contains(item.key)
      }
      var due = 0, unseen = 0
      for item in within(items, node) {
        if let card = input.cards[item.cardId] {
          if runNeed(card, score.lineRounds, now) >= 1 || slipped.contains(item.key) { due += 1 }
        } else {
          unseen += 1
        }
      }
      push(.review, node, color, reviewNeed(due, unseen, input.newPerSession), reachedIn(items, node).filter(wanting).count)

      // A Test is only ever the selection, from move one.
      if node === region {
        let since = lastAt(node.id) ?? 0
        let untested = mine.filter { $0.addedAt > since }.count
        let stalest = ([0] + reachedIn(lines, node).map(\.stale)).max()!
        push(.test, node, color, testNeed(untested, everRun, stalest), untested > 0 ? untested : mine.count)
      }
    }
  }
  return out
}

/// The one thing to start, or nil when there is nothing to drill. A winning
/// Review is narrowed while a variation holds most of its work.
public func recommend(_ input: RecommendInput) -> Recommendation? {
  let tree = input.tree
  let closed = steeredRecently(input.recentSteered)
  let open = { (id: String) in !closed || !isSteered(opening: nodeById(tree, id), start: .inside, input.selection) }
  let ranked = rank(candidates(input).filter { open($0.openingId) }, input.recentFocuses)
  guard var best = ranked.first else { return nil }
  while best.focus != .test {
    let node = nodeById(tree, best.openingId)
    let parent = best
    let child = ranked
      .filter { c in
        c.focus == parent.focus && c.color == parent.color && node.children.contains { $0.id == c.openingId } && open(c.openingId)
          && Double(c.work) > Double(parent.work) * narrowingBar(effectiveLevel(c.level, c.starred))
      }
      .jsSorted { cmp($1.work, $0.work) }
      .first
    guard let child else { break }
    best = child
  }
  let opening = nodeById(tree, best.openingId)
  return Recommendation(focus: best.focus, opening: opening, color: best.color, start: startsInside(opening) ? .inside : .first)
}

/// How many recent Survival runs your prep accuracy is read over.
public let ACCURACY_RUNS = 5

/// How far your prep is missing: 0 at 95% found or better, 1 at 85% or worse.
public func missingPrep(_ accuracy: Double?) -> Double {
  guard let accuracy else { return 0 }
  return clamp((0.95 - accuracy) / 0.1)
}
