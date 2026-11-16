import ChessCore

/// A log of everything the app did with you: what changed the playbook and
/// what Growth put in front of you, every game's moves and how each was
/// judged, the engine's look at each position, callouts, tips, pawns earned
/// and spent, purchases, settings changed. Data for diagnosing, not a screen.

/// Where in the app an event came from.
public enum EventPlace: String, Sendable, Codable {
  case home, playbook, tidy, analysis, stats, growth, play, run, drill, repair, freePlay, `import`, onboarding, board, session, unknown
}

/// One event. Each kind uses its own fields;
/// the rest stay nil, so the saved JSON has the same shape.
public struct AppEvent: Equatable, Sendable, Codable {
  public var kind: String
  public var at: Double = 0
  public var via: EventPlace = .unknown
  public var playbookId: String?
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
  /// The game it happened in: the run's id.
  public var game: String?
  public var san: String?
  public var fen: String?
  /// Evals, White's side, and what a move gave away.
  public var before: Double?
  public var after: Double?
  public var lost: Double?
  /// A judged move kept the game going.
  public var ok: Bool?
  /// The engine's move.
  public var best: String?
  public var seconds: Double?
  public var moment: Bool?
  public var found: Bool?
  /// Words: a callout, an ending, a setting's change.
  public var text: String?

  public init(
    kind: String, via: EventPlace? = nil, playbookId: String? = nil, color: Color? = nil, line: String? = nil,
    added: Int? = nil, source: String? = nil, removed: [String]? = nil, count: Int? = nil, delta: Int? = nil,
    to: String? = nil, rows: [String]? = nil, picked: String? = nil, start: String? = nil, offered: [String]? = nil,
    from: String? = nil, all: Bool? = nil, game: String? = nil, san: String? = nil, fen: String? = nil,
    before: Double? = nil, after: Double? = nil, lost: Double? = nil, ok: Bool? = nil, best: String? = nil,
    seconds: Double? = nil, moment: Bool? = nil, found: Bool? = nil, text: String? = nil
  ) {
    self.kind = kind
    self.via = via ?? .unknown
    self.placeGiven = via != nil
    self.playbookId = playbookId
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
    self.game = game
    self.san = san
    self.fen = fen
    self.before = before
    self.after = after
    self.lost = lost
    self.ok = ok
    self.best = best
    self.seconds = seconds
    self.moment = moment
    self.found = found
    self.text = text
  }

  /// Whether a new event named its own place; otherwise it takes the app's.
  var placeGiven = true

  enum CodingKeys: String, CodingKey {
    case kind, at, via, playbookId, color, line, added, source, removed, count, delta, to, rows, picked, start, offered, from, all
    case game, san, fen, before, after, lost, ok, best, seconds, moment, found, text
  }

  public static func == (a: AppEvent, b: AppEvent) -> Bool {
    a.kind == b.kind && a.at == b.at && a.via == b.via && a.playbookId == b.playbookId && a.color == b.color
      && a.line == b.line && a.added == b.added && a.source == b.source && a.removed == b.removed && a.count == b.count
      && a.delta == b.delta && a.to == b.to && a.rows == b.rows && a.picked == b.picked && a.start == b.start
      && a.offered == b.offered && a.from == b.from && a.all == b.all && a.game == b.game && a.san == b.san
      && a.fen == b.fen && a.before == b.before && a.after == b.after && a.lost == b.lost && a.ok == b.ok
      && a.best == b.best && a.seconds == b.seconds && a.moment == b.moment && a.found == b.found && a.text == b.text
  }

  /// What a delete took, spread into the event.
  public func with(_ removal: (removed: [String], count: Int)) -> AppEvent {
    var e = self
    e.removed = removal.removed
    e.count = removal.count
    return e
  }
}

/// How many events are kept: every move of the last hundred or so games.
public let EVENT_CAP = 5000
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
public func lineAt(_ rep: Playbook, _ nodeId: String?) -> String {
  pathTo(rep, nodeId).map(\.san).joined(separator: " ")
}

/// What went between two versions of a tree: every line of the old one that
/// lost a move, whole, and how many moves went in all.
public func removedBetween(_ before: Playbook, _ after: Playbook) -> (removed: [String], count: Int) {
  let gone = { (id: String) in after.nodes[id] == nil }
  let count = before.nodes.keys.filter(gone).count
  let removed = leafLines(before).filter { gone($0.tipId) }.map { $0.sans.joined(separator: " ") }
  return (Array(removed.prefix(REMOVED_CAP)), count)
}
