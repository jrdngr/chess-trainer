import ChessCore
import Foundation
import Shared

/// The record: what each opening, and the whole game, has done, day by day.

/// The modes whose activity is tallied. `run` and `repair` are kept for history.
public enum ActivityMode: String, Sendable, Codable, CaseIterable {
  case oldPlay, run, drill, growth, repair
}

public let ACTIVITY_MODES = ActivityMode.allCases

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

  public init(answered: Int = 0, correct: Int = 0, rounds: Int = 0) {
    self.answered = answered
    self.correct = correct
    self.rounds = rounds
  }
}

/// Everything one opening, or the whole game, has done.
public struct NodeStats: Equatable, Sendable, Codable {
  public var answered = 0
  public var correct = 0
  public var byMode: [ActivityMode: ModeTally] = Dictionary(uniqueKeysWithValues: ActivityMode.allCases.map { ($0, ModeTally()) })
  public var bestRun = 0
  public var lastAt: Double?
  /// `ScoreState.lineRounds` when a round last played here.
  public var lastRound: Int?
  /// "YYYY-MM-DD" → the day's numbers.
  public var days: [String: DayTally] = [:]

  public init() {}
}

/// One round: a run, a Drill session or line, or a Growth run.
public struct RoundRecord: Equatable, Sendable, Codable {
  public var mode: ActivityMode
  /// The opening the round was credited to.
  public var openingId: String
  public var color: Color
  public var answered: Int
  public var correct: Int
  public var perfect: Bool
  public var at: Double
  /// A run's prepared positions: how many it asked, how many you found.
  public var prep: Prep?
  /// The line the round was about.
  public var line: [String]?

  public struct Prep: Equatable, Sendable, Codable {
    public var asked: Int
    public var found: Int
    public init(asked: Int, found: Int) {
      self.asked = asked
      self.found = found
    }
  }

  public init(mode: ActivityMode, openingId: String, color: Color, answered: Int, correct: Int, perfect: Bool, at: Double, prep: Prep? = nil, line: [String]? = nil) {
    self.mode = mode
    self.openingId = openingId
    self.color = color
    self.answered = answered
    self.correct = correct
    self.perfect = perfect
    self.at = at
    self.prep = prep
    self.line = line
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

  public init() {}
}

/// The local calendar day a moment falls on.
public func dayKey(_ at: Double, _ calendar: Calendar = .current) -> String {
  let parts = calendar.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: at / 1000))
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
  /// A prepared position answered in a run: only these count for form.
  public var rated: Bool
  public var at: Double
  /// How long a right answer took; nil for a miss.
  public var seconds: Double?

  public init(mode: ActivityMode, line: [String], color: Color, correct: Bool, rated: Bool, at: Double, seconds: Double? = nil) {
    self.mode = mode
    self.line = line
    self.color = color
    self.correct = correct
    self.rated = rated
    self.at = at
    self.seconds = seconds
  }
}

/// The openings an answer counts as activity for: the deepest its line goes
/// through and every one above, shallowest first.
public func creditedNodes(_ tree: OpeningTree, _ line: [String]) -> [String] {
  guard let deepest = deepestNodeAlong(tree, line) else { return [] }
  return ancestorsOf(tree, deepest.id).map(\.id)
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

/// Apply one answer: activity for the openings its line names.
public func applyResult(_ state: ScoreState, _ tree: OpeningTree, _ result: MoveResult) -> ScoreState {
  var next = state
  for id in creditedNodes(tree, result.line) { next.nodes[id] = tallyAnswer(next.nodes[id] ?? NodeStats(), result) }
  next.global = tallyAnswer(state.global, result)
  return next
}

private func tallyRound(_ stats: NodeStats, _ round: RoundRecord, _ lineRounds: Int) -> NodeStats {
  var out = stats
  if round.mode == .oldPlay { out.bestRun = max(stats.bestRun, round.correct) }
  out.lastAt = round.at
  out.lastRound = lineRounds
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
  // A round that played a line is one the next should not repeat.
  if let line = round.line {
    next.lineRounds += 1
    next.seen = markSeen(state.seen, line, next.lineRounds)
  }
  for id in ancestorsOf(tree, round.openingId).map(\.id) { next.nodes[id] = tallyRound(state.nodes[id] ?? NodeStats(), round, next.lineRounds) }
  next.global = tallyRound(state.global, round, next.lineRounds)
  next.rounds.append(round)
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
/// Steps back by calendar days, so a day that daylight saving makes 23 hours long is not skipped.
public func streak(_ stats: NodeStats, _ now: Double = Env.now(), calendar: Calendar = .current) -> Int {
  let played = Set(stats.days.filter { $0.value.rounds > 0 }.map(\.key))
  var day = calendar.startOfDay(for: Date(timeIntervalSince1970: now / 1000))
  func key(_ date: Date) -> String { dayKey(date.timeIntervalSince1970 * 1000, calendar) }
  func before(_ date: Date) -> Date { calendar.date(byAdding: .day, value: -1, to: date)! }
  var count = 0
  if !played.contains(key(day)) { day = before(day) }
  while played.contains(key(day)) {
    count += 1
    day = before(day)
  }
  return count
}

// Keyed by mode name when saved.
extension ActivityMode: CodingKeyRepresentable {}
