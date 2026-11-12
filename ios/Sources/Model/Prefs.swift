/// What each mode plays on, and Autopilot's fixed setup.

/// How long you get for each of your own moves.
public enum ClockMode: String, Sendable, Codable, CaseIterable {
  case off, move10, move30
}

public let CLOCK_MODES = ClockMode.allCases

/// Seconds per move, or nil with the clock off.
public func clockSeconds(_ mode: ClockMode) -> Double? {
  switch mode {
  case .move10: return 10
  case .move30: return 30
  case .off: return nil
  }
}

public func clockLabel(_ mode: ClockMode) -> String {
  switch mode {
  case .move10: return "10s"
  case .move30: return "30s"
  case .off: return "Off"
  }
}

/// What a Survival opponent steers toward.
public enum SurvivalSteer: String, Sendable, Codable, CaseIterable {
  case lines, gaps, book
}

public func survivalSteerLabel(_ steer: SurvivalSteer) -> String {
  switch steer {
  case .gaps: return "My gaps"
  case .book: return "Ignore my lines"
  case .lines: return "My lines"
  }
}

public struct SurvivalPrefs: Equatable, Sendable, Codable {
  public var steer: SurvivalSteer
  public var clock: ClockMode
  /// What each engine-judged move cost, floated up from its square.
  public var moveScores: Bool
  public var moments: Bool
  public var missions: Bool
  public var combo: Bool
  /// Before your move lands, what it leaves undefended flashes.
  public var undefendedFlash: Bool
  /// Who plays the other side past the book: `OPPONENT_MATCH` for your own
  /// strength, or a level's id.
  public var opponent: String = OPPONENT_MATCH
}

/// The opponent plays at your own strength.
public let OPPONENT_MATCH = "match"

extension SurvivalPrefs {
  /// The level the opponent plays at, given your strength.
  public func opponentLevel(_ strength: PlayerStrength) -> Level {
    opponent == OPPONENT_MATCH ? levelMatching(strength) : levelById(opponent)
  }
}

public let DEFAULT_SURVIVAL = SurvivalPrefs(
  steer: .lines, clock: .off, moveScores: true, moments: true, missions: true, combo: true,
  undefendedFlash: false)

extension SurvivalPrefs {
  /// A saved setup missing an option takes its default: `{ ...DEFAULT_SURVIVAL, ...known.survival }`.
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let d = DEFAULT_SURVIVAL
    self.init(
      steer: try c.decodeIfPresent(SurvivalSteer.self, forKey: .steer) ?? d.steer,
      clock: try c.decodeIfPresent(ClockMode.self, forKey: .clock) ?? d.clock,
      moveScores: try c.decodeIfPresent(Bool.self, forKey: .moveScores) ?? d.moveScores,
      moments: try c.decodeIfPresent(Bool.self, forKey: .moments) ?? d.moments,
      missions: try c.decodeIfPresent(Bool.self, forKey: .missions) ?? d.missions,
      combo: try c.decodeIfPresent(Bool.self, forKey: .combo) ?? d.combo,
      undefendedFlash: try c.decodeIfPresent(Bool.self, forKey: .undefendedFlash) ?? d.undefendedFlash,
      opponent: try c.decodeIfPresent(String.self, forKey: .opponent) ?? d.opponent)
  }
}

public enum NudgePriority: String, Sendable, Codable { case transposition, habit }

public struct GrowthPrefs: Equatable, Sendable, Codable {
  public var minShare: Double
  public var maxPly: Int
  public var nudgePriority: NudgePriority
  public var nudgePawns: Bool
  public var pastBook: Bool
}

/// Autopilot's own options: matters of taste only.
public struct AutopilotPrefs: Equatable, Sendable, Codable {
  public var moveScores: Bool
  public init(moveScores: Bool) {
    self.moveScores = moveScores
  }
}

public let DEFAULT_AUTOPILOT = AutopilotPrefs(moveScores: true)

/// How many new moves a round may ask.
public let NEW_PER_ROUND = 8

/// Growth rounds, and what counts as ready to grow. Autopilot never grows past the book.
/// Growth's own defaults.
public let DEFAULT_GROWTH = GrowthPrefs(minShare: 1, maxPly: 18, nudgePriority: .transposition, nudgePawns: false, pastBook: false)

/// One fill's size, in your moves; the settings slider runs 1...5.
public let DEFAULT_MOVES_PER_FILL = 3
public let MOVES_PER_FILL_RANGE = 1...5

public let AUTO_GROWTH = GrowthPrefs(minShare: 1, maxPly: 18, nudgePriority: .transposition, nudgePawns: false, pastBook: false)

/// Survival rounds: Autopilot steers, there is no clock, the feedback is yours.
public func autoSurvival(_ prefs: AutopilotPrefs) -> SurvivalPrefs {
  SurvivalPrefs(
    steer: .lines, clock: .off, moveScores: prefs.moveScores, moments: true,
    missions: true, combo: true, undefendedFlash: false)
}

