import Foundation

/// Openings you picked and then played, read from the game history: the quick
/// picker's Recent section and its full list. Newest first, one entry per opening.

/// One opening picked and played, with the side it was played as and when.
public struct RecentPick: Equatable, Sendable {
  public var opening: String
  public var color: ColorChoice
  public var at: Double

  public init(opening: String, color: ColorChoice, at: Double) {
    self.opening = opening
    self.color = color
    self.at = at
  }
}

/// How many Recent tiles the quick picker shows.
public let RECENT_SHOWN = 4

/// The openings picked in the game history, newest first, once each. Only a
/// single opening counts: My Playbook and Any favorite are not picks of one.
public func recentPicks(_ games: [GameRecord]) -> [RecentPick] {
  var seen: Set<String> = []
  var out: [RecentPick] = []
  for game in games {
    let id = game.picked.opening
    guard id != ANY_OPENING, id != ANY_FAVORITE, seen.insert(id).inserted else { continue }
    out.append(RecentPick(opening: id, color: game.picked.color, at: game.at))
  }
  return out
}

/// The quick picker's Recent tiles: the newest picks that aren't one tap
/// away already. A favorite is skipped by its own id only, so the lines under it still show.
public func quickRecent(_ recent: [RecentPick], skipping: Set<String>, count: Int = RECENT_SHOWN) -> [RecentPick] {
  Array(recent.filter { !skipping.contains($0.opening) }.prefix(count))
}

extension AppState {
  /// Openings you picked and played, newest first.
  public var recent: [RecentPick] { recentPicks(games) }
}

/// One stretch of the full Recent list, under its heading.
public struct RecentGroup: Equatable, Sendable {
  public var label: String
  public var picks: [RecentPick]
}

/// The full list in stretches of time, newest first: Today, Yesterday, This
/// week, then each month by name ("October", or "October 2025" in another year).
public func recentGroups(_ recent: [RecentPick], now: Double, calendar: Calendar = .current) -> [RecentGroup] {
  let today = calendar.startOfDay(for: Date(timeIntervalSince1970: now / 1000))
  let thisYear = calendar.component(.year, from: today)
  let months = DateFormatter()
  months.calendar = calendar
  months.timeZone = calendar.timeZone
  months.locale = Locale(identifier: "en_US_POSIX")
  months.dateFormat = "LLLL"
  var out: [RecentGroup] = []
  for pick in recent {
    let date = Date(timeIntervalSince1970: pick.at / 1000)
    let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: today).day ?? 0
    let label: String
    if days <= 0 {
      label = "Today"
    } else if days == 1 {
      label = "Yesterday"
    } else if days < 7 {
      label = "This week"
    } else {
      let year = calendar.component(.year, from: date)
      label = year == thisYear ? months.string(from: date) : "\(months.string(from: date)) \(year)"
    }
    if out.last?.label == label { out[out.count - 1].picks.append(pick) } else { out.append(RecentGroup(label: label, picks: [pick])) }
  }
  return out
}
