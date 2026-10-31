import ChessCore
import Foundation
import Shared

/// The rating: how well you know one opening. `src/model/scoring.ts`.
///
/// A rating moves like a chess rating: each prepared position answered in a
/// run is one result against that opening, sized by how well the rating
/// already expects you to do.

/// The modes whose activity is tallied. `run` and `repair` are kept for history.
public enum ActivityMode: String, Sendable, Codable, CaseIterable {
  case run, survival, drill, growth, repair
}

public let ACTIVITY_MODES = ActivityMode.allCases

/// Where an Autopilot run started.
public enum StartKind: String, Sendable, Codable {
  case position, inside, cold
}

public enum RATING {
  /// Where an opening starts.
  public static let start: Double = 0
  /// It never goes below this.
  public static let floor: Double = 0
  /// The most one result can move a rating.
  public static let step: Double = 20
  /// Ratings this far apart differ by ten to one in odds.
  public static let scale: Double = 450
}

/// The share of answers a rating expects to be right.
public func expectedAccuracy(_ rating: Double) -> Double {
  1 / (1 + pow(10, -rating / RATING.scale))
}

/// The rating a result leaves behind, kept to two decimals.
public func ratingAfter(_ rating: Double, _ correct: Bool) -> Double {
  let moved = rating + RATING.step * ((correct ? 1 : 0) - expectedAccuracy(rating))
  return JS.round(max(RATING.floor, moved) * 100) / 100
}

public struct Tier: Equatable, Sendable, Codable {
  public var name: String
  public var color: String
  /// The rating that reaches it.
  public var at: Double
}

/// The ladder, named for how well you know the opening.
public let TIERS: [Tier] = [
  Tier(name: "Learning", color: "#94a3b8", at: 100),
  Tier(name: "Familiar", color: "#4ade80", at: 250),
  Tier(name: "Solid", color: "#2dd4bf", at: 400),
  Tier(name: "Strong", color: "#3b82f6", at: 550),
  Tier(name: "Fluent", color: "#a855f7", at: 700),
  Tier(name: "Mastered", color: "#facc15", at: 850),
]

/// Below the first rung, once rated: New until then.
public let UNRATED = Tier(name: "Shaky", color: "#4b4b55", at: 0)
public let NEW_LABEL = "New"

public struct Rank: Equatable, Sendable, Codable {
  public var rating: Double
  /// Tiers reached; 0 is unrated.
  public var reached: Int
  public var held: Tier?
  public var next: Tier?
  public var heldLabel: String
  public var nextLabel: String?
  public var floor: Double
  public var ceiling: Double
  /// 0...1 of the way from the tier held to the next.
  public var progress: Double
}

/// Where a rating stands on the ladder. `rated` decides New or Shaky below the first rung.
public func rankOf(_ rating: Double, _ rated: Int = 1) -> Rank {
  var reached = 0
  while reached < TIERS.count && rating >= TIERS[reached].at { reached += 1 }
  let held = reached == 0 ? nil : TIERS[reached - 1]
  let next = reached < TIERS.count ? TIERS[reached] : nil
  let floor = held?.at ?? 0
  let ceiling = next?.at ?? held?.at ?? TIERS[0].at
  return Rank(
    rating: rating, reached: reached, held: held, next: next,
    heldLabel: held?.name ?? (rated > 0 ? UNRATED.name : NEW_LABEL), nextLabel: next?.name,
    floor: floor, ceiling: ceiling,
    progress: next != nil ? max(0, min(1, (rating - floor) / (ceiling - floor))) : 1)
}

/* ── the record ── */

public struct ModeTally: Equatable, Sendable, Codable {
  public var rounds = 0
  public var answered = 0
  public var correct = 0
  public var lastAt: Double?
}

public struct DayTally: Equatable, Sendable, Codable {
  public var answered = 0
  public var correct = 0
  public var rounds = 0
  /// Where the rating stood at the end of the day, or nil if it never moved.
  public var rating: Double?

  public init(answered: Int = 0, correct: Int = 0, rounds: Int = 0, rating: Double? = nil) {
    self.answered = answered
    self.correct = correct
    self.rounds = rounds
    self.rating = rating
  }
}

/// Everything one opening, or the whole game, has done.
public struct NodeStats: Equatable, Sendable, Codable {
  public var rating = RATING.start
  /// Rated results this opening has had.
  public var rated = 0
  /// The Extensions rating: moved only by answers past where the line left the book.
  public var extRating = RATING.start
  public var extRated = 0
  public var answered = 0
  public var correct = 0
  public var byMode: [ActivityMode: ModeTally] = Dictionary(uniqueKeysWithValues: ActivityMode.allCases.map { ($0, ModeTally()) })
  public var bestRun = 0
  public var lastAt: Double?
  /// "YYYY-MM-DD" → the day's numbers.
  public var days: [String: DayTally] = [:]

  public init() {}
}

public func emptyNodeStats() -> NodeStats { NodeStats() }

/// One round: a Survival run, a Drill session or line, or a Growth run.
public struct RoundRecord: Equatable, Sendable, Codable {
  public var mode: ActivityMode
  /// The opening the round was credited to.
  public var openingId: String
  public var color: Color
  public var answered: Int
  public var correct: Int
  public var perfect: Bool
  public var at: Double
  /// A Survival run's prepared positions: how many it asked, how many you found.
  public var prep: Prep?
  /// The line the round was about.
  public var line: [String]?

  public struct Prep: Equatable, Sendable, Codable {
    public var asked: Int
    public var found: Int
  }
}

public struct ScoreState: Equatable, Sendable, Codable {
  /// Activity for the whole game. Never rated.
  public var global = NodeStats()
  public var nodes: [String: NodeStats] = [:]
  public var rounds: [RoundRecord] = []
  /// Position key → the line round that last saw it.
  public var seen: [String: Int] = [:]
  /// How many rounds have played a line: the clock freshness is read against.
  public var lineRounds = 0
  /// Where Autopilot's last runs started, oldest first.
  public var starts: [StartKind] = []

  public init() {}
}

public let EMPTY_SCORE = ScoreState()

/// The local calendar day a moment falls on.
public func dayKey(_ at: Double) -> String {
  let parts = Calendar.current.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: at / 1000))
  return String(format: "%d-%02d-%02d", parts.year!, parts.month!, parts.day!)
}

/* ── results ── */

/// One answer given somewhere in the app.
public struct MoveResult: Equatable, Sendable {
  public var mode: ActivityMode
  /// The line the position sits on: decides which openings it belongs to.
  public var line: [String]
  public var color: Color
  public var correct: Bool
  /// Whether this moves ratings: only a prepared position answered in a run.
  public var rated: Bool
  /// The answer was an extension: it rates the Extensions rating.
  public var ext: Bool
  public var at: Double

  public init(mode: ActivityMode, line: [String], color: Color, correct: Bool, rated: Bool, ext: Bool = false, at: Double) {
    self.mode = mode
    self.line = line
    self.color = color
    self.correct = correct
    self.rated = rated
    self.ext = ext
    self.at = at
  }
}

/// How one opening's rating moved.
public struct RatingMove: Equatable, Sendable {
  public var id: String
  /// The Extensions rating rather than the main one.
  public var ext: Bool
  public var before: Double
  public var after: Double
  /// 1 promoted a tier, -1 demoted, 0 neither.
  public var promotion: Int
}

/// The openings an answer counts as activity for: the deepest its line goes
/// through and every one above, shallowest first.
public func creditedNodes(_ tree: OpeningTree, _ line: [String]) -> [String] {
  guard let deepest = deepestNodeAlong(tree, line) else { return [] }
  return ancestorsOf(tree, deepest.id).map(\.id)
}

/// The openings a rated answer counts for: every one its line has reached.
public func ratedNodes(_ tree: OpeningTree, _ line: [String]) -> [String] {
  creditedNodes(tree, line)
}

private func tallyAnswer(_ stats: NodeStats, _ result: MoveResult) -> NodeStats {
  var out = stats
  let key = dayKey(result.at)
  let correct = result.correct ? 1 : 0
  out.answered += 1
  out.correct += correct
  out.lastAt = result.at
  var mode = stats.byMode[result.mode] ?? ModeTally()
  mode.answered += 1
  mode.correct += correct
  mode.lastAt = result.at
  out.byMode[result.mode] = mode
  var day = stats.days[key] ?? DayTally()
  day.answered += 1
  day.correct += correct
  out.days[key] = day
  return out
}

private func tallyRating(_ stats: NodeStats, _ result: MoveResult) -> NodeStats {
  var out = stats
  if result.ext {
    out.extRating = ratingAfter(stats.extRating, result.correct)
    out.extRated += 1
    return out
  }
  let after = ratingAfter(stats.rating, result.correct)
  let key = dayKey(result.at)
  var day = stats.days[key] ?? DayTally()
  day.rating = after
  out.rating = after
  out.rated += 1
  out.days[key] = day
  return out
}

/// Rate one run's answers into the openings `line` has reached. An opening
/// reached for the first time takes the run's earlier answers first, then
/// `result` rates every opening reached. One move per rating touched.
private func rateRun(
  _ nodes: inout [String: NodeStats], _ tree: OpeningTree, _ earlier: [MoveResult], _ line: [String], _ result: MoveResult?
) -> [RatingMove] {
  var before = OrderedMap<String, (id: String, ext: Bool, was: Double)>()
  func rate(_ id: String, _ answer: MoveResult) {
    let stats = nodes[id] ?? NodeStats()
    let key = answer.ext ? "\(id) ext" : id
    if !before.has(key) { before[key] = (id, answer.ext, answer.ext ? stats.extRating : stats.rating) }
    nodes[id] = tallyRating(stats, answer)
  }
  let reached = ratedNodes(tree, line)
  let counted = earlier.filter(\.rated)
  // Lines only grow within a run: an opening an earlier answer reached has every answer before it.
  let rated = Set(counted.flatMap { ratedNodes(tree, $0.line) })
  for id in reached where !rated.contains(id) { for answer in counted { rate(id, answer) } }
  if let result, result.rated { for id in reached { rate(id, result) } }
  return before.values.map { entry in
    let after = entry.ext ? nodes[entry.id]!.extRating : nodes[entry.id]!.rating
    let climbed = rankOf(after).reached - rankOf(entry.was).reached
    return RatingMove(id: entry.id, ext: entry.ext, before: entry.was, after: after, promotion: climbed > 0 ? 1 : climbed < 0 ? -1 : 0)
  }
}

/// Apply one answer: activity for the openings its line names and, when rated,
/// the rating of every opening its line has reached. `earlier` is the run's
/// answers before this one.
public func applyResult(_ state: ScoreState, _ tree: OpeningTree, _ result: MoveResult, _ earlier: [MoveResult] = []) -> (state: ScoreState, moves: [RatingMove]) {
  var nodes = state.nodes
  for id in creditedNodes(tree, result.line) { nodes[id] = tallyAnswer(nodes[id] ?? NodeStats(), result) }
  let moves = result.rated ? rateRun(&nodes, tree, earlier, result.line, result) : []
  var next = state
  next.global = tallyAnswer(state.global, result)
  next.nodes = nodes
  return (next, moves)
}

/// A run is over and its line went further than its last answer: the
/// openings only that stretch reached take the run's rated answers too.
public func settleRun(_ state: ScoreState, _ tree: OpeningTree, _ earlier: [MoveResult], _ line: [String]) -> (state: ScoreState, moves: [RatingMove]) {
  if earlier.isEmpty { return (state, []) }
  var nodes = state.nodes
  let moves = rateRun(&nodes, tree, earlier, line, nil)
  guard !moves.isEmpty else { return (state, moves) }
  var next = state
  next.nodes = nodes
  return (next, moves)
}

private func tallyRound(_ stats: NodeStats, _ round: RoundRecord) -> NodeStats {
  var out = stats
  if round.mode == .run { out.bestRun = max(stats.bestRun, round.correct) }
  out.lastAt = round.at
  var mode = stats.byMode[round.mode] ?? ModeTally()
  mode.rounds += 1
  mode.lastAt = round.at
  out.byMode[round.mode] = mode
  let key = dayKey(round.at)
  var day = stats.days[key] ?? DayTally()
  day.rounds += 1
  out.days[key] = day
  return out
}

/// Log a finished round against its opening and every opening above it.
public func recordRound(_ state: ScoreState, _ tree: OpeningTree, _ round: RoundRecord) -> ScoreState {
  var next = state
  for id in ancestorsOf(tree, round.openingId).map(\.id) { next.nodes[id] = tallyRound(state.nodes[id] ?? NodeStats(), round) }
  next.global = tallyRound(state.global, round)
  next.rounds.append(round)
  // A round that played a line is one the next should not repeat.
  if let line = round.line {
    next.lineRounds += 1
    next.seen = markSeen(state.seen, line, next.lineRounds)
  }
  return next
}

/// How many of Autopilot's starts are remembered.
let STARTS_KEPT = 6

/// Autopilot started a run: remembered across sessions.
public func recordStart(_ state: ScoreState, _ kind: StartKind) -> ScoreState {
  var next = state
  next.starts = Array((state.starts + [kind]).suffix(STARTS_KEPT))
  return next
}

public func nodeStats(_ state: ScoreState, _ id: String) -> NodeStats {
  id.isEmpty ? state.global : state.nodes[id] ?? NodeStats()
}

/// Correct over answered, or nil before anything was answered.
public func accuracy(answered: Int, correct: Int) -> Double? {
  answered > 0 ? Double(correct) / Double(answered) : nil
}

/* ── streaks ── */

/// Days in a row with a round, counting back from today, or from yesterday
/// when nothing has been played yet today.
public func streak(_ stats: NodeStats, _ now: Double = Env.now()) -> Int {
  let played = Set(stats.days.filter { $0.value.rounds > 0 }.map(\.key))
  var count = 0
  var cursor = now
  if !played.contains(dayKey(cursor)) { cursor -= DAY }
  while played.contains(dayKey(cursor)) {
    count += 1
    cursor -= DAY
  }
  return count
}

/// Where a rating stood at the end of a day: the last day at or before it that moved it.
public func ratingOn(_ stats: NodeStats, _ key: String) -> Double {
  var at: String?
  var rating = RATING.start
  for (day, tally) in stats.days {
    guard let r = tally.rating, day <= key, at == nil || day >= at! else { continue }
    at = day
    rating = r
  }
  return rating
}

/// How far a rating has moved over the last `days` days.
public func ratingChange(_ stats: NodeStats, _ days: Double, _ now: Double = Env.now()) -> Double {
  stats.rating - ratingOn(stats, dayKey(now - days * DAY))
}

// Keyed by mode name when saved, as the prototype's record is.
extension ActivityMode: CodingKeyRepresentable {}
