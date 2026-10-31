import ChessCore

/// A log of what changed the repertoire, and what Growth put in front of
/// you: `src/model/events.ts`. The repertoire says what your prep is, never
/// how it got that way; this is the record that does. Data for diagnosing,
/// not a screen.

/// Where in the app an event came from.
public enum EventPlace: String, Sendable, Codable {
  case home, repertoire, tidy, analysis, stats, growth, autopilot, survival, drill, repair, play, `import`, onboarding, board, session, unknown
}

/// One event. Each kind uses its own fields, as the prototype's union does;
/// the rest stay nil, so the saved JSON has the same shape.
public struct AppEvent: Equatable, Sendable, Codable {
  public var kind: String
  public var at: Double = 0
  public var via: EventPlace = .unknown
  public var repertoireId: String?
  public var color: Color?
  public var line: String?
  public var added: Int?
  public var source: String?
  public var removed: [String]?
  public var count: Int?
  public var delta: Int?
  public var to: String?
  public var rows: [String]?
  public var picked: String?
  public var start: String?
  public var offered: [String]?
  public var from: String?
  public var all: Bool?

  public init(
    kind: String, via: EventPlace? = nil, repertoireId: String? = nil, color: Color? = nil, line: String? = nil,
    added: Int? = nil, source: String? = nil, removed: [String]? = nil, count: Int? = nil, delta: Int? = nil,
    to: String? = nil, rows: [String]? = nil, picked: String? = nil, start: String? = nil, offered: [String]? = nil,
    from: String? = nil, all: Bool? = nil
  ) {
    self.kind = kind
    self.via = via ?? .unknown
    self.placeGiven = via != nil
    self.repertoireId = repertoireId
    self.color = color
    self.line = line
    self.added = added
    self.source = source
    self.removed = removed
    self.count = count
    self.delta = delta
    self.to = to
    self.rows = rows
    self.picked = picked
    self.start = start
    self.offered = offered
    self.from = from
    self.all = all
  }

  /// Whether a new event named its own place; otherwise it takes the app's.
  var placeGiven = true

  enum CodingKeys: String, CodingKey {
    case kind, at, via, repertoireId, color, line, added, source, removed, count, delta, to, rows, picked, start, offered, from, all
  }

  public static func == (a: AppEvent, b: AppEvent) -> Bool {
    a.kind == b.kind && a.at == b.at && a.via == b.via && a.repertoireId == b.repertoireId && a.color == b.color
      && a.line == b.line && a.added == b.added && a.source == b.source && a.removed == b.removed && a.count == b.count
      && a.delta == b.delta && a.to == b.to && a.rows == b.rows && a.picked == b.picked && a.start == b.start
      && a.offered == b.offered && a.from == b.from && a.all == b.all
  }

  /// What a delete took, spread into the event.
  public func with(_ removal: (removed: [String], count: Int)) -> AppEvent {
    var e = self
    e.removed = removal.removed
    e.count = removal.count
    return e
  }
}

/// How many events are kept: enough for weeks of use, small enough to sync.
public let EVENT_CAP = 1000
/// How many removed lines one event lists; the count says how many moves went in all.
public let REMOVED_CAP = 20

nonisolated(unsafe) private var place: EventPlace = .unknown

/// Where the app is now, for events that do not say. Set as you move around.
public func setEventPlace(_ next: EventPlace) { place = next }

/// The log with one more event on the end, the oldest dropped past the cap.
public func appendEvent(_ events: [AppEvent], _ event: AppEvent, _ now: Double = Env.now()) -> [AppEvent] {
  var full = event
  full.at = now
  if !event.placeGiven { full.via = place }
  full.placeGiven = true
  return Array(events.suffix(EVENT_CAP - 1)) + [full]
}

/// A saved log: its newest `EVENT_CAP`.
public func normalizeEvents(_ saved: [AppEvent]?) -> [AppEvent] {
  Array((saved ?? []).suffix(EVENT_CAP))
}

/// A node's line from the start, as moves.
public func lineAt(_ rep: Repertoire, _ nodeId: String?) -> String {
  pathTo(rep, nodeId).map(\.san).joined(separator: " ")
}

/// What went between two versions of a tree: every line of the old one that
/// lost a move, whole, and how many moves went in all.
public func removedBetween(_ before: Repertoire, _ after: Repertoire) -> (removed: [String], count: Int) {
  let gone = { (id: String) in after.nodes[id] == nil }
  let count = before.nodes.keys.filter(gone).count
  let removed = leafLines(before).filter { gone($0.tipId) }.map { $0.sans.joined(separator: " ") }
  return (Array(removed.prefix(REMOVED_CAP)), count)
}
