import ChessCore

/// Past the opening: missions, and the extras a judged move earns.

public enum MissionKind: String, Sendable, Codable {
  case edge, lead, dig, convert
}

public struct PieceCount: Equatable, Sendable, Codable {
  public var mine: Int
  public var theirs: Int
  public init(mine: Int, theirs: Int) { self.mine = mine; self.theirs = theirs }
}

public struct Mission: Equatable, Sendable, Codable {
  public var kind: MissionKind
  /// Your judged moves since it was set.
  public var moves: Int
  /// Keep your edge: your moves at +1 or better so far.
  public var held: Int
  /// Convert it: each side's pieces when it was set.
  public var pieces: PieceCount?

  public init(kind: MissionKind, moves: Int = 0, held: Int = 0, pieces: PieceCount? = nil) {
    self.kind = kind
    self.moves = moves
    self.held = held
    self.pieces = pieces
  }
}

public let EDGE_MOVES = 10
public let MISSION_WINDOW = 15
public let MISSION_LEAD: Double = 100
public let MISSION_DUG: Double = -50
public let CONVERT_FROM: Double = 200
public let CONVERT_WINDOW = 6
public let MISSION_BREAK = 3

private func mine(_ color: Color, _ cp: Double) -> Double { color == .w ? cp : -cp }

/// Each side's pieces on the board, pawns and kings aside.
private func pieceCount(_ fen: String, _ color: Color) -> PieceCount {
  let pieces = piecesFromFen(fen).filter { $0.type != .p && $0.type != .k }
  let own = pieces.filter { $0.color == color }.count
  return PieceCount(mine: own, theirs: pieces.count - own)
}

/// The mission the eval calls for, in White's frame.
public func missionFor(_ color: Color, _ cp: Double, _ fen: String? = nil) -> Mission {
  let at = mine(color, cp)
  if let fen, at >= CONVERT_FROM {
    let pieces = pieceCount(fen, color)
    if pieces.mine > 0 && pieces.theirs > 0 { return Mission(kind: .convert, pieces: pieces) }
  }
  return Mission(kind: at >= MISSION_LEAD ? .edge : at <= -MISSION_LEAD ? .dig : .lead)
}

public func missionTitle(_ kind: MissionKind) -> String {
  switch kind {
  case .edge: return "Keep your edge"
  case .lead: return "Take the lead"
  case .dig: return "Dig in"
  case .convert: return "Convert it"
  }
}

/// What the goal card asks for, under the mission's name.
public func missionTarget(_ kind: MissionKind) -> String {
  switch kind {
  case .edge: return "Stay at +1 or better"
  case .lead: return "Reach +1"
  case .dig: return "Get back to \u{2212}0.5"
  case .convert: return "Trade a piece"
  }
}

/// Your moves left before the mission is settled.
public func missionTurnsLeft(_ mission: Mission) -> Int {
  switch mission.kind {
  case .edge: return EDGE_MOVES - mission.held
  case .convert: return CONVERT_WINDOW - mission.moves
  default: return MISSION_WINDOW - mission.moves
  }
}

public enum MissionResult: String, Sendable, Codable { case done, failed }

/// One of your judged moves against a mission, with the eval and position after it.
public func stepMission(_ mission: Mission, _ color: Color, _ cp: Double, _ fen: String? = nil) -> (mission: Mission, result: MissionResult?) {
  let at = mine(color, cp)
  var next = mission
  next.moves += 1
  switch mission.kind {
  case .edge:
    if at < MISSION_LEAD { return (next, .failed) }
    next.held = mission.held + 1
    return (next, next.held >= EDGE_MOVES ? .done : nil)
  case .lead:
    if at >= MISSION_LEAD { return (next, .done) }
    return (next, next.moves >= MISSION_WINDOW ? .failed : nil)
  case .dig:
    if at >= MISSION_DUG { return (next, .done) }
    return (next, next.moves >= MISSION_WINDOW ? .failed : nil)
  case .convert:
    if at < MISSION_LEAD { return (next, .failed) }
    // Traded: each side a piece fewer than when it was set, the lead held through it.
    if let fen, let was = mission.pieces {
      let now = pieceCount(fen, color)
      if now.mine < was.mine && now.theirs < was.theirs && at >= CONVERT_FROM { return (next, .done) }
      // A capture on your last turn waits for their reply: a recapture completes the trade.
      if next.moves >= CONVERT_WINDOW && now.theirs < was.theirs && at >= CONVERT_FROM { return (next, nil) }
    }
    return (next, next.moves >= CONVERT_WINDOW ? .failed : nil)
  }
}

/// The opponent's move against a Convert it mission, with the eval after your last judged move
/// and the position after their move: their recapture completes the trade, and a last-turn
/// capture they leave alone fails it.
public func theirMoveMission(_ mission: Mission, _ color: Color, _ cp: Double, _ fen: String) -> MissionResult? {
  guard mission.kind == .convert, let was = mission.pieces else { return nil }
  let now = pieceCount(fen, color)
  if now.mine < was.mine && now.theirs < was.theirs && mine(color, cp) >= CONVERT_FROM { return .done }
  return mission.moves >= CONVERT_WINDOW ? .failed : nil
}

public struct Moments: Equatable, Sendable, Codable {
  public var found = 0
  public var missed = 0
  public var streak = 0
}

public struct MissionTally: Equatable, Sendable, Codable {
  public var done = 0
  public var failed = 0
}

/// Where a run's extras stand.
public struct Extras: Equatable, Sendable, Codable {
  /// Pawns this run has earned: its score.
  public var pawns = 0
  /// The game has reached endgame rules, and paid for it.
  public var endgame = false
  public var moments = Moments()
  public var mission: Mission?
  /// Your judged moves still to go before the next mission is set.
  public var missionBreak = 0
  public var missions = MissionTally()
  public init() {}
}

public let NO_EXTRAS = Extras()

/// What a judged move did, for the screen to show. A bonus is the pawns it paid.
public struct Earned: Equatable, Sendable {
  public var pawns: Int
  public var moment: (found: Bool, bonus: Int)?
  public var mission: (kind: MissionKind, result: MissionResult, bonus: Int)?

  public static func == (a: Earned, b: Earned) -> Bool {
    a.pawns == b.pawns && a.moment?.found == b.moment?.found && a.moment?.bonus == b.moment?.bonus
      && a.mission?.kind == b.mission?.kind && a.mission?.result == b.mission?.result && a.mission?.bonus == b.mission?.bonus
  }
}

public struct ExtrasPrefs: Sendable {
  public var moments: Bool
  public var missions: Bool
  public init(moments: Bool, missions: Bool) {
    self.moments = moments
    self.missions = missions
  }
  public init(_ prefs: RunPrefs) {
    self.init(moments: prefs.moments, missions: prefs.missions)
  }
}

public struct JudgedMove: Sendable {
  public var lost: Double
  public var after: Double
  public var moment: Bool
  public var found: Bool
  public var fen: String?
  public init(lost: Double, after: Double, moment: Bool, found: Bool, fen: String? = nil) {
    self.lost = lost
    self.after = after
    self.moment = moment
    self.found = found
    self.fen = fen
  }
}

/// One of your moves the engine judged: a moment settles, a mission steps, and either may pay.
public func judgedExtras(_ extras: Extras, _ prefs: ExtrasPrefs, _ color: Color, _ move: JudgedMove) -> (extras: Extras, earned: Earned) {
  var moments = extras.moments
  var momentEarned: (found: Bool, bonus: Int)?
  if prefs.moments && move.moment {
    if move.found {
      let bonus = pawnsFor(.moment)
      moments.found += 1
      moments.streak += 1
      momentEarned = (true, bonus)
    } else {
      moments.missed += 1
      moments.streak = 0
      momentEarned = (false, 0)
    }
  }
  var pawns = extras.pawns + (momentEarned?.bonus ?? 0)
  var mission = extras.mission
  var missionBreak = extras.missionBreak
  var missions = extras.missions
  var missionEarned: (kind: MissionKind, result: MissionResult, bonus: Int)?
  if prefs.missions {
    if let current = mission {
      let stepped = stepMission(current, color, move.after, move.fen)
      if let result = stepped.result {
        let bonus = result == .done ? pawnsFor(.mission) : 0
        missionEarned = (current.kind, result, bonus)
        pawns += bonus
        if result == .done { missions.done += 1 } else { missions.failed += 1 }
        mission = nil
        missionBreak = MISSION_BREAK
      } else {
        mission = stepped.mission
      }
    } else if missionBreak > 0 {
      missionBreak -= 1
      if missionBreak == 0 { mission = missionFor(color, move.after, move.fen) }
    }
  }
  var out = extras
  out.pawns = pawns
  out.moments = moments
  out.mission = mission
  out.missionBreak = missionBreak
  out.missions = missions
  return (out, Earned(pawns: pawns - extras.pawns, moment: momentEarned, mission: missionEarned))
}

/// The opponent's move: a Convert it mission may settle on it.
public func theirExtras(_ extras: Extras, _ color: Color, _ cp: Double, _ fen: String) -> (extras: Extras, earned: Earned?) {
  guard let current = extras.mission, let result = theirMoveMission(current, color, cp, fen) else { return (extras, nil) }
  let bonus = result == .done ? pawnsFor(.mission) : 0
  var out = extras
  out.pawns += bonus
  if result == .done { out.missions.done += 1 } else { out.missions.failed += 1 }
  out.mission = nil
  out.missionBreak = MISSION_BREAK
  return (out, Earned(pawns: bonus, moment: nil, mission: (current.kind, result, bonus)))
}

/// The first mission, set from the eval where the prep runs out.
public func firstMission(_ extras: Extras, missions on: Bool, _ color: Color, _ cp: Double, _ fen: String? = nil) -> Extras {
  if !on || extras.mission != nil || extras.missionBreak > 0 || extras.missions.done + extras.missions.failed > 0 { return extras }
  var out = extras
  out.mission = missionFor(color, cp, fen)
  return out
}
