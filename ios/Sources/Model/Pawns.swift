import ChessCore
import Foundation
import Shared

/// Pawns: what the Pawn Shop sells for. They come only from the events here,
/// one at a time, in Play, Middlegame and Endgames, plus each streak day.

public enum PawnEvent: String, Sendable, Codable, CaseIterable {
  /// Your prep ran out with no miss: one pawn for each prep move asked.
  case prepComplete
  /// The opponent's move threw away a lot and your reply took it.
  case blunderPunished
  case moment
  case mission
  /// The game reached endgame rules.
  case endgame
  case checkmate
  /// An Endgames round's goal met.
  case endgameGoal
  /// The first game of a day in a streak; its pawns come from `streakPawns`.
  case streak
}

/// What an event pays. Prep complete pays this for each prep move asked; a streak day pays by
/// the streak's length.
public func pawnsFor(_ event: PawnEvent) -> Int {
  switch event {
  case .prepComplete, .endgameGoal: return 1
  case .blunderPunished, .endgame: return 3
  case .moment, .mission: return 6
  case .checkmate: return 15
  case .streak: return 1
  }
}

/// A prepared move this quick is fast: the time that grades its card easy.
public let FAST_PREP_SECONDS: Double = 3
/// How far the opponent's move must drop their own eval to be a blunder you can punish.
public let PUNISH_DROP: Double = 200
/// How much your reply may give back and still take what their blunder gave.
public let PUNISH_KEPT: Double = 50

/// Where earned pawns pop out on the play screen.
public enum PawnSource: Equatable, Sendable {
  /// A square on the board: the move that earned them, or the mated king.
  case square(String)
  /// The pot beside the prep bar, for prep complete.
  case pot
  /// The goal card, for a mission done.
  case goal
  /// The board as a whole: an endgame reached, an Endgames goal met.
  case board
  /// The streak ring on Home, for a streak day.
  case streak
}

/// Pawns earned by one event, and where they pop out.
public struct PawnAward: Equatable, Sendable {
  public var event: PawnEvent
  public var count: Int
  public var source: PawnSource
  public init(_ event: PawnEvent, _ source: PawnSource, count: Int? = nil) {
    self.event = event
    self.count = count ?? pawnsFor(event)
    self.source = source
  }
}

/// The pawns a run's prep pays when it runs out: one for each prep move asked, with no miss.
public func prepPawns(misses: Int, times: [Double]) -> Int {
  misses == 0 ? times.count * pawnsFor(.prepComplete) : 0
}

/// Whether your judged move punished the opponent's blunder: their move dropped their
/// own eval by `PUNISH_DROP` or more since your last scored move, and yours gave back at most
/// `PUNISH_KEPT`. Evals are White's; nil across a mate.
public func punished(_ color: Color, lastScored: Double?, before: Double, lost: Double) -> Bool {
  guard let lastScored, let gained = evalSwing(color, lastScored, before) else { return false }
  return gained >= PUNISH_DROP && lost <= PUNISH_KEPT
}

/* ── the streak ── */

/// The days in a row with a game, for streak pawns.
public struct PawnStreak: Equatable, Sendable, Codable {
  /// The last day a game paid, "YYYY-MM-DD".
  public var day: String?
  /// Days in a row, counting that day.
  public var days = 0
  public init(day: String? = nil, days: Int = 0) {
    self.day = day
    self.days = days
  }
}

/// What a streak day pays: 1 a day in its first week, 2 in its second, and so on, 5 from day 29.
public func streakPawns(_ days: Int) -> Int {
  max(1, min(5, (days - 1) / 7 + 1))
}

/// A game finished on `today`: the first game of a day extends the streak, or starts it again
/// after a missed day, and pays. Later games that day pay nothing.
public func streakDay(_ streak: PawnStreak, today: String, yesterday: String) -> (streak: PawnStreak, pawns: Int) {
  if streak.day == today { return (streak, 0) }
  let days = streak.day == yesterday ? streak.days + 1 : 1
  return (PawnStreak(day: today, days: days), streakPawns(days))
}

/// Where the streak stands on `today`, for its ring: the day today is or will be, whether
/// today's game has paid yet, and what it pays.
public struct StreakToday: Equatable, Sendable {
  /// Today's day in the streak: counted once today's game is played, the next one before.
  public var day: Int
  public var paid: Bool
  public var pawns: Int
  public init(day: Int, paid: Bool, pawns: Int) {
    self.day = day
    self.paid = paid
    self.pawns = pawns
  }
  /// Today's place in its week of the streak, 1 to 7.
  public var weekday: Int { (day - 1) % 7 + 1 }
}

public func streakToday(_ streak: PawnStreak, today: String, yesterday: String) -> StreakToday {
  if streak.day == today { return StreakToday(day: streak.days, paid: true, pawns: streakPawns(streak.days)) }
  let day = streak.day == yesterday ? streak.days + 1 : 1
  return StreakToday(day: day, paid: false, pawns: streakPawns(day))
}

/// The local calendar day before `day`.
public func dayBefore(_ at: Double, _ calendar: Calendar = .current) -> String {
  let date = Date(timeIntervalSince1970: at / 1000)
  let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
  let before = calendar.date(byAdding: .day, value: -1, to: noon) ?? noon.addingTimeInterval(-86_400)
  return dayKey(before.timeIntervalSince1970 * 1000, calendar)
}

extension AppState {
  /// Pawns added to the balance.
  public mutating func earn(_ count: Int) {
    pawns += max(0, count)
  }

  /// A game finished: the day's first pays the streak. Returns what it paid.
  public mutating func finishedGame(now: Double = Env.now()) -> Int {
    let paid = streakDay(pawnStreak, today: dayKey(now), yesterday: dayBefore(now))
    pawnStreak = paid.streak
    earn(paid.pawns)
    return paid.pawns
  }
}
