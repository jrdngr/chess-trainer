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

/// Why pawns were paid, shown under the counter as they land.
public func pawnReason(_ event: PawnEvent) -> String {
  switch event {
  case .prepComplete: return "Prep complete"
  case .blunderPunished: return "Blunder punished"
  case .moment: return "Found it"
  case .mission: return "Mission complete"
  case .endgame: return "Endgame reached"
  case .checkmate: return "Checkmate"
  case .distance: return "5 more moves"
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
  case .checkmate: return 15
  case .heldDraw: return pawnsFor(.checkmate) / 2
  case .distance: return DISTANCE_PAWNS[0]
  case .streak: return 1
  }
}

/// How many of your moves past prep make a distance marker.
public let DISTANCE_EVERY = 5
/// What the first markers pay; each one after pays the last.
public let DISTANCE_PAWNS = [10, 15, 20]
/// The share of a marker Middlegame pays.
public let MIDDLEGAME_DISTANCE_SHARE = 0.4

/// What the `n`th distance marker of a run pays (from 1).
public func distancePawns(_ n: Int, middlegame: Bool = false) -> Int {
  let full = DISTANCE_PAWNS[min(max(n, 1), DISTANCE_PAWNS.count) - 1]
  return middlegame ? Int((Double(full) * MIDDLEGAME_DISTANCE_SHARE).rounded()) : full
}

/// What a run's first `count` distance markers pay together.
public func distancePawns(markers count: Int, middlegame: Bool = false) -> Int {
  count > 0 ? (1...count).reduce(0) { $0 + distancePawns($1, middlegame: middlegame) } : 0
}

/// How far behind after the prep a draw must be held from to pay, in centipawns from your side.
public let HELD_DRAW_FROM: Double = -150

/// Whether a draw was held: you stood at `HELD_DRAW_FROM` or worse after the prep. `cp` is White's.
public func heldDraw(_ color: Color, afterPrep cp: Double?) -> Bool {
  guard let cp else { return false }
  return (color == .w ? cp : -cp) <= HELD_DRAW_FROM
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
  /// The last day of the streak, "YYYY-MM-DD": a day a game paid, or one frozen or repaired.
  public var day: String?
  /// Days in a row, counting that day, frozen and repaired days among them.
  public var days = 0
  /// Freezes held, up to `MAX_FREEZES`.
  public var freezes = 0
  /// The streak's days (counted from 1) that a freeze or a repair kept.
  public var frozen: [Int] = []
  public init(day: String? = nil, days: Int = 0, freezes: Int = 0, frozen: [Int] = []) {
    self.day = day
    self.days = days
    self.freezes = freezes
    self.frozen = frozen
  }

  enum CodingKeys: String, CodingKey { case day, days, freezes, frozen }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    day = try c.decodeIfPresent(String.self, forKey: .day)
    days = try c.decodeIfPresent(Int.self, forKey: .days) ?? 0
    freezes = try c.decodeIfPresent(Int.self, forKey: .freezes) ?? 0
    frozen = try c.decodeIfPresent([Int].self, forKey: .frozen) ?? []
  }
}

/// What a streak day pays: 10 on day 1, 10 more each day, up to 90.
public func streakPawns(_ days: Int) -> Int {
  min(STREAK_CAP, STREAK_STEP * max(1, days))
}

public let STREAK_STEP = 10, STREAK_CAP = 90
/// Freezes held at most; what one costs; what a repair costs.
public let MAX_FREEZES = 2, FREEZE_PRICE = 1_000, REPAIR_PRICE = 2_000
/// What Continue after a blunder costs, once a run.
public let CONTINUE_PRICE = 500

/// The days before today, newest first: yesterday, the day before, and so on.
public typealias PastDays = [String]

/// Freezes cover the days missed since the streak's last day, oldest first, one each, while
/// they last. Only gaps short enough for freezes and a repair to reach are looked at.
public func settleStreak(_ streak: PawnStreak, past: PastDays) -> PawnStreak {
  guard streak.days > 0, streak.freezes > 0, let last = streak.day, let k = past.firstIndex(of: last), k > 0 else { return streak }
  var out = streak
  for missed in past[0..<k].reversed() {
    guard out.freezes > 0 else { break }
    out.freezes -= 1
    out.days += 1
    out.frozen.append(out.days)
    out.day = missed
  }
  return out
}

/// Whether a repair is offered today: the streak's only missed day is yesterday.
public func repairOffered(_ streak: PawnStreak, today: String, past: PastDays) -> Bool {
  let settled = settleStreak(streak, past: past)
  return settled.days > 0 && settled.day != today && past.count > 1 && settled.day == past[1]
}

/// A game finished on `today`: the first game of a day extends the streak, or starts it again
/// after a missed day freezes don't cover, and pays. Later games that day pay nothing.
public func streakDay(_ streak: PawnStreak, today: String, past: PastDays) -> (streak: PawnStreak, pawns: Int) {
  if streak.day == today { return (streak, 0) }
  var next = settleStreak(streak, past: past)
  if next.day == past.first {
    next.days += 1
  } else {
    next.days = 1
    next.frozen = []
  }
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
  /// This week's places (1 to 7) kept by a freeze or a repair.
  public var frozen: [Int] = []
  /// Yesterday was missed and a repair can still keep the streak.
  public var repairable = false
  public init(day: Int, paid: Bool, pawns: Int, frozen: [Int] = [], repairable: Bool = false) {
    self.day = day
    self.paid = paid
    self.pawns = pawns
    self.frozen = frozen
    self.repairable = repairable
  }
  /// Today's place in its week of the streak, 1 to 7.
  public var weekday: Int { (day - 1) % 7 + 1 }
}

public func streakToday(_ streak: PawnStreak, today: String, past: PastDays) -> StreakToday {
  let settled = settleStreak(streak, past: past)
  let week = { (day: Int) in settled.frozen.filter { ($0 - 1) / 7 == (day - 1) / 7 }.map { ($0 - 1) % 7 + 1 } }
  if settled.day == today {
    return StreakToday(day: settled.days, paid: true, pawns: streakPawns(settled.days), frozen: week(settled.days))
  }
  if repairOffered(streak, today: today, past: past) {
    // Shown as it stands: a repair would make today the day after yesterday's.
    let day = settled.days + 2
    return StreakToday(day: day, paid: false, pawns: streakPawns(day), frozen: week(day), repairable: true)
  }
  let day = settled.day == past.first ? settled.days + 1 : 1
  return StreakToday(day: day, paid: false, pawns: streakPawns(day), frozen: day == 1 ? [] : week(day))
}

public func streakToday(_ streak: PawnStreak, today: String, yesterday: String) -> StreakToday {
  streakToday(streak, today: today, past: [yesterday])
}

/// The `count` local calendar days before `at`'s, newest first.
public func daysBefore(_ at: Double, _ count: Int = MAX_FREEZES + 2, _ calendar: Calendar = .current) -> PastDays {
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

  /// Freezes cover the days missed since the streak's last, as they will at the next game.
  public mutating func settleStreak(now: Double = Env.now()) {
    pawnStreak = Model.settleStreak(pawnStreak, past: daysBefore(now))
  }

  /// Where the streak stands today, for its ring.
  public func streakNow(_ now: Double = Env.now()) -> StreakToday {
    streakToday(pawnStreak, today: dayKey(now), past: daysBefore(now))
  }

  /// Pawns spent in play: off the balance when there are enough. Returns whether they were.
  @discardableResult
  public mutating func spend(_ count: Int, on what: String) -> Bool {
    guard count >= 0, pawns >= count else { return false }
    pawns -= count
    logEvent(AppEvent(kind: "buy", count: count, picked: what, text: "balance \(pawns)"))
    return true
  }

  /// Buy a streak freeze: held for a missed day, up to 2. Returns whether it was bought.
  @discardableResult
  public mutating func buyFreeze() -> Bool {
    guard pawnStreak.freezes < MAX_FREEZES, pawns >= FREEZE_PRICE else { return false }
    pawns -= FREEZE_PRICE
    pawnStreak.freezes += 1
    logEvent(AppEvent(kind: "buy", count: FREEZE_PRICE, picked: "freeze", text: "balance \(pawns)"))
    return true
  }

  /// Repair yesterday, missed: the streak goes on as if it was played, paying nothing for it.
  @discardableResult
  public mutating func repairStreak(now: Double = Env.now()) -> Bool {
    let past = daysBefore(now)
    guard repairOffered(pawnStreak, today: dayKey(now), past: past), pawns >= REPAIR_PRICE else { return false }
    pawns -= REPAIR_PRICE
    var streak = Model.settleStreak(pawnStreak, past: past)
    streak.days += 1
    streak.frozen.append(streak.days)
    streak.day = past[0]
    pawnStreak = streak
    logEvent(AppEvent(kind: "buy", count: REPAIR_PRICE, picked: "repair", text: "balance \(pawns)"))
    return true
  }
}
