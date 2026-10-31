import Foundation
import Shared

/// Stats: the numbers behind one opening, or the whole game, shaped for a
/// chart. `src/model/stats.ts`. Everything reads the per-day tallies the
/// record keeps and folds them into series; nothing is stored twice.

public struct DayPoint: Equatable, Sendable {
  /// Start of the day, local time.
  public var at: Double
  public var key: String
  public var value: Double
}

/// Midnight, local time, `back` days before `now`.
private func dayStart(_ now: Double, _ back: Int) -> Double {
  let date = Date(timeIntervalSince1970: (now - Double(back) * DAY) / 1000)
  return Calendar.current.startOfDay(for: date).timeIntervalSince1970 * 1000
}

/// The last `days` days, oldest first, each with the rounds played that day.
public func dailyRounds(_ stats: NodeStats, _ days: Int, _ now: Double = Env.now()) -> [DayPoint] {
  stride(from: days - 1, through: 0, by: -1).map { back in
    let at = dayStart(now, back)
    let key = dayKey(at)
    return DayPoint(at: at, key: key, value: Double(stats.days[key]?.rounds ?? 0))
  }
}

/// The rating as it stood at the end of each day in the window.
///
/// A day the rating never moved holds the day before's, so the line is
/// continuous. It starts from wherever the rating stood going into the
/// window, and an opening that has never been rated has no line at all.
public func ratingOverTime(_ stats: NodeStats, _ days: Int, _ now: Double = Env.now()) -> [DayPoint] {
  if stats.rated == 0 { return [] }
  let first = dayKey(dayStart(now, days - 1))
  var running = RATING.start
  var latest = ""
  for (key, day) in stats.days {
    guard key < first, let rating = day.rating, key > latest else { continue }
    latest = key
    running = rating
  }
  return stride(from: days - 1, through: 0, by: -1).map { back in
    let at = dayStart(now, back)
    let key = dayKey(at)
    if let rating = stats.days[key]?.rating { running = rating }
    return DayPoint(at: at, key: key, value: running)
  }
}

/// Accuracy over the window, smoothed: each day is the share of the answers
/// over the seven days ending there that were right. Days with nothing to
/// average over are left out rather than drawn as zero.
public func rollingAccuracy(_ stats: NodeStats, _ days: Int, _ now: Double = Env.now(), _ window: Int = 7) -> [DayPoint] {
  var out: [DayPoint] = []
  for back in stride(from: days - 1, through: 0, by: -1) {
    var answered = 0
    var correct = 0
    for w in 0..<window {
      guard let day = stats.days[dayKey(dayStart(now, back + w))] else { continue }
      answered += day.answered
      correct += day.correct
    }
    if answered == 0 { continue }
    let at = dayStart(now, back)
    out.append(DayPoint(at: at, key: dayKey(at), value: Double(correct) / Double(answered)))
  }
  return out
}

/// Rounds in the last `days` days.
public func recentRounds(_ stats: NodeStats, _ days: Int, _ now: Double = Env.now()) -> Int {
  stride(from: days - 1, through: 0, by: -1).reduce(0) { $0 + (stats.days[dayKey(dayStart(now, $1))]?.rounds ?? 0) }
}

/* ── favouriteness ── */

public struct Sibling: Sendable {
  public var node: OpeningNode
  public var rounds: Int
  /// Of the rounds among these siblings.
  public var share: Double
}

public struct Favouriteness: Sendable {
  public var rank: Int
  public var of: Int
  public var siblings: [Sibling]
  public var parent: OpeningNode?
}

/// How an opening ranks against its siblings by rounds played lately: "your
/// second favourite Sicilian". Siblings never played are left out.
public func favouriteness(_ tree: OpeningTree, _ score: ScoreState, _ id: String, _ days: Int = 30, _ now: Double = Env.now()) -> Favouriteness? {
  guard let node = tree.byId[id], node.depth > 0 else { return nil }
  let parent = node.parentId.map { nodeById(tree, $0) }
  let pool = parent?.children ?? tree.root.children
  var siblings = pool
    .map { Sibling(node: $0, rounds: recentRounds(nodeStats(score, $0.id), days, now), share: 0) }
    .filter { $0.rounds > 0 }
    .jsSorted { a, b in
      let c = cmp(b.rounds, a.rounds)
      return c != 0 ? c : Double(JS.localeCompare(a.node.name, b.node.name))
    }
  let total = siblings.reduce(0) { $0 + $1.rounds }
  for i in siblings.indices { siblings[i].share = total > 0 ? Double(siblings[i].rounds) / Double(total) : 0 }
  guard let rank = siblings.firstIndex(where: { $0.node.id == id }) else { return nil }
  return Favouriteness(rank: rank + 1, of: siblings.count, siblings: siblings, parent: parent)
}

/* ── the openings that matter ── */

public struct Ranked: Sendable {
  public var node: OpeningNode
  public var stats: NodeStats
  public var trail: String
}

private func ranked(_ tree: OpeningTree, _ score: ScoreState, _ id: String) -> Ranked {
  Ranked(
    node: nodeById(tree, id), stats: nodeStats(score, id),
    trail: ancestorsOf(tree, id).dropLast().map(\.name).joined(separator: " \u{203a} "))
}

private func byRating(_ a: Ranked, _ b: Ranked) -> Double {
  let r = b.stats.rating - a.stats.rating
  if r != 0 { return r }
  let d = cmp(a.node.depth, b.node.depth)
  return d != 0 ? d : Double(JS.localeCompare(a.node.name, b.node.name))
}

/// Your starred openings, best rated first. Stars below the ladder are kept
/// and sort last: an untested star is still one of yours.
public func starredOpenings(_ tree: OpeningTree, _ score: ScoreState, _ starred: [String]) -> [Ranked] {
  var seen = Set<String>()
  var out: [Ranked] = []
  for id in starred {
    guard let node = tree.byId[id], node.depth > 0, !seen.contains(id) else { continue }
    seen.insert(id)
    out.append(ranked(tree, score, id))
  }
  return out.jsSorted(byRating)
}

/// Every opening Survival has rated that is not a favorite, best rated first.
/// One never rated is not listed: it is not yours until you have played it.
public func ratedOpenings(_ tree: OpeningTree, _ score: ScoreState, _ starred: [String]) -> [Ranked] {
  let stars = Set(starred)
  return score.nodes
    .filter { id, stats in stats.rated > 0 && !stars.contains(id) && (tree.byId[id]?.depth ?? 0) > 0 }
    .map { ranked(tree, score, $0.key) }
    .jsSorted(byRating)
}

/// Ticks for an axis: a few round numbers that cover the range.
public func niceTicks(_ max: Double, _ count: Double = 3) -> [Double] {
  if max <= 0 { return [0] }
  let rough = max / count
  let magnitude = pow(10, floor(log10(rough)))
  let step = [1.0, 2, 5, 10].map { $0 * magnitude }.first { $0 >= rough } ?? magnitude * 10
  var out: [Double] = []
  var tick = 0.0
  while tick <= max + step * 0.999 {
    out.append(tick)
    tick += step
  }
  return out
}
