import Foundation

/// Openings you picked and then played: the quick picker's Recent section and
/// its full list. Newest first, one entry per opening.

/// One opening picked and played, with the side it was played as and when.
public struct RecentPick: Equatable, Sendable, Codable {
  public var opening: String
  public var color: ColorChoice
  public var at: Double

  public init(opening: String, color: ColorChoice, at: Double) {
    self.opening = opening
    self.color = color
    self.at = at
  }
}

/// How many picks the history keeps; the oldest go past this.
public let RECENT_CAP = 100

/// How many Recent tiles the quick picker shows.
public let RECENT_SHOWN = 4

/// The history after a round played on `selection`. Only a single opening
/// counts: My Playbook and Any favorite are not picks of one. Playing an opening
/// again moves it to the front.
public func notePick(_ recent: [RecentPick], _ selection: Selection, at: Double) -> [RecentPick] {
  let id = selection.opening
  guard id != ANY_OPENING, id != ANY_FAVORITE else { return recent }
  let rest = recent.filter { $0.opening != id }
  return Array(([RecentPick(opening: id, color: selection.color, at: at)] + rest).prefix(RECENT_CAP))
}

/// The quick picker's Recent tiles: the newest picks that aren't one tap
/// away already. A favorite is skipped by its own id only, so the lines under it still show.
public func quickRecent(_ recent: [RecentPick], skipping: Set<String>, count: Int = RECENT_SHOWN) -> [RecentPick] {
  Array(recent.filter { !skipping.contains($0.opening) }.prefix(count))
}

extension AppState {
  /// A round has started on the saved selection.
  public mutating func notePlayed(at: Double = Env.now()) {
    recent = notePick(recent, settings.selection, at: at)
  }
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
