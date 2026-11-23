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
  /// A mate you gave; its pawns come from `winPawns`.
  case checkmate
  /// Every 5 of your moves past prep; its pawns come from `distancePawns`.
  case distance
  /// A draw held from −1.5 or worse after the prep.
  case heldDraw
  /// Endgames bounties, each paid once for an ending: its first clear, its first mission, its
  /// mastery. Then each passed tune-up, and a From your games position's first conversion.
  case endgameClear, endgameMission, endgameMastery, endgameTuneUp, endgameConverted
  /// The first game of a day in a streak; its pawns come from `streakPawns`.
  case streak
}

/// Why pawns were paid, shown under the counter as they land. Distance pawns say nothing:
/// the bar they pop out of says it.
public func pawnReason(_ event: PawnEvent) -> String? {
  switch event {
  case .prepComplete: return "Prep complete"
  case .blunderPunished: return "Blunder punished"
  case .moment: return "Found it"
  case .mission: return "Mission complete"
  case .endgame: return "Endgame reached"
  case .checkmate: return "Checkmate"
  case .distance: return nil
  case .heldDraw: return "Held the draw"
  case .endgameClear: return "First clear"
  case .endgameMission: return "First mission"
  case .endgameMastery: return "Mastered"
  case .endgameTuneUp: return "Tune-up passed"
  case .endgameConverted: return "Converted"
  case .streak: return "Daily streak"
  }
}

/// What an event pays. Prep complete pays this for each prep move asked; a streak day pays by
/// the streak's length.
public func pawnsFor(_ event: PawnEvent) -> Int {
  switch event {
  case .prepComplete: return 1
  case .endgameClear: return ENDGAME_CLEAR_PAWNS
  case .endgameMission: return ENDGAME_MISSION_PAWNS
  case .endgameMastery: return ENDGAME_MASTERY_PAWNS
  case .endgameTuneUp: return ENDGAME_TUNE_UP_PAWNS
  case .endgameConverted: return ENDGAME_CONVERTED_PAWNS
  case .blunderPunished, .endgame: return 3
  case .moment, .mission: return 6
  case .checkmate: return WIN_PAWNS
  case .heldDraw: return HELD_DRAW_PAWNS
  case .distance: return DISTANCE_PAWNS
  case .streak: return 1
  }
}

/// How many of your moves past prep make a distance marker.
public let DISTANCE_EVERY = 5
/// What each marker pays.
public let DISTANCE_PAWNS = 20
/// What each marker pays in Middlegame.
public let MIDDLEGAME_DISTANCE_PAWNS = 15
/// The most distance markers a run pays.
public let DISTANCE_MAX_MARKERS = 10

/// Whether your next move past prep counts toward a distance marker: not once the game has
/// reached endgame rules, and not past the run's last marker.
public func countsTowardMarker(pastPrep: Int, endgame: Bool) -> Bool {
  !endgame && pastPrep < DISTANCE_MAX_MARKERS * DISTANCE_EVERY
}

/// A move that takes the piece your previous move moved straight back to the square it left:
/// Nd7 after Nc5 from d7. It doesn't count toward a distance marker.
public func goesBack(from: String, to: String, after previous: (from: String, to: String)?) -> Bool {
  guard let previous else { return false }
  return from == previous.to && to == previous.from
}

/// Your moves toward the next distance marker, 0 to 4, and what it pays.
public func nextMarker(_ pastPrep: Int, middlegame: Bool = false) -> (moves: Int, pays: Int) {
  (pastPrep % DISTANCE_EVERY, distancePawns(pastPrep / DISTANCE_EVERY + 1, middlegame: middlegame))
}

/// What the `n`th distance marker of a run pays (from 1).
public func distancePawns(_ n: Int, middlegame: Bool = false) -> Int {
  middlegame ? MIDDLEGAME_DISTANCE_PAWNS : DISTANCE_PAWNS
}

/// What a run's first `count` distance markers pay together.
public func distancePawns(markers count: Int, middlegame: Bool = false) -> Int {
  count > 0 ? (1...count).reduce(0) { $0 + distancePawns($1, middlegame: middlegame) } : 0
}

/// What a mate you give pays at most: with no move of yours played under endgame rules.
public let WIN_PAWNS = 100
/// What each of your moves under endgame rules before the mate takes off it.
public let WIN_PAWNS_STEP = 2
/// The least a mate you give pays.
public let WIN_PAWNS_FLOOR = 25

/// What a mate you give pays, after `endgameMoves` of your moves under endgame rules.
public func winPawns(endgameMoves: Int) -> Int {
  max(WIN_PAWNS_FLOOR, WIN_PAWNS - WIN_PAWNS_STEP * endgameMoves)
}

/// What a held draw pays: under the least a win pays, so any win beats it.
public let HELD_DRAW_PAWNS = 20
/// How far behind under endgame rules a draw must be held from to pay, in centipawns from your
/// side: a lost ending.
public let HELD_DRAW_FROM: Double = -RESULT_WIN_CP

/// Whether a draw was held: under endgame rules you stood at `HELD_DRAW_FROM` or worse.
/// `low` is your worst score there, from your side.
public func heldDraw(low: Double?) -> Bool {
  guard let low else { return false }
  return low <= HELD_DRAW_FROM
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
  /// The pawn at the end of the distance bar in the header, for a distance marker.
  case marker
  /// The board as a whole: an endgame reached, a held draw, an Endgames bounty.
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
  /// The last day of the streak, "YYYY-MM-DD": a day a game paid.
  public var day: String?
  /// Days in a row, counting that day.
  public var days = 0
  public init(day: String? = nil, days: Int = 0) {
    self.day = day
    self.days = days
  }

  enum CodingKeys: String, CodingKey { case day, days }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    day = try c.decodeIfPresent(String.self, forKey: .day)
    days = try c.decodeIfPresent(Int.self, forKey: .days) ?? 0
  }
}

/// What a streak day pays: 10 on day 1, 10 more each day, up to 90.
public func streakPawns(_ days: Int) -> Int {
  min(STREAK_CAP, STREAK_STEP * max(1, days))
}

public let STREAK_STEP = 10, STREAK_CAP = 90

/// The days before today, newest first: yesterday, the day before, and so on.
public typealias PastDays = [String]

/// A game finished on `today`: the first game of a day extends the streak, or starts it again
/// after a missed day, and pays. Later games that day pay nothing.
public func streakDay(_ streak: PawnStreak, today: String, past: PastDays) -> (streak: PawnStreak, pawns: Int) {
  if streak.day == today { return (streak, 0) }
  var next = streak
  next.days = next.day == past.first ? next.days + 1 : 1
  next.day = today
  return (next, streakPawns(next.days))
}

public func streakDay(_ streak: PawnStreak, today: String, yesterday: String) -> (streak: PawnStreak, pawns: Int) {
  streakDay(streak, today: today, past: [yesterday])
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

public func streakToday(_ streak: PawnStreak, today: String, past: PastDays) -> StreakToday {
  if streak.day == today {
    return StreakToday(day: streak.days, paid: true, pawns: streakPawns(streak.days))
  }
  let day = streak.day == past.first ? streak.days + 1 : 1
  return StreakToday(day: day, paid: false, pawns: streakPawns(day))
}

public func streakToday(_ streak: PawnStreak, today: String, yesterday: String) -> StreakToday {
  streakToday(streak, today: today, past: [yesterday])
}

/// The `count` local calendar days before `at`'s, newest first.
public func daysBefore(_ at: Double, _ count: Int = 1, _ calendar: Calendar = .current) -> PastDays {
  var out: PastDays = []
  var t = at
  for _ in 0..<count {
    let date = Date(timeIntervalSince1970: t / 1000)
    let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
    let before = calendar.date(byAdding: .day, value: -1, to: noon) ?? noon.addingTimeInterval(-86_400)
    t = before.timeIntervalSince1970 * 1000
    out.append(dayKey(t, calendar))
  }
  return out
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
    let paid = streakDay(pawnStreak, today: dayKey(now), past: daysBefore(now))
    pawnStreak = paid.streak
    earn(paid.pawns)
    return paid.pawns
  }

  /// Where the streak stands today, for its ring.
  public func streakNow(_ now: Double = Env.now()) -> StreakToday {
    streakToday(pawnStreak, today: dayKey(now), past: daysBefore(now))
  }
}
