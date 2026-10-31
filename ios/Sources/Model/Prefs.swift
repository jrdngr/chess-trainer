/// What each mode plays on, and Autopilot's fixed setup. `modes.ts`,
/// `survival.ts`'s prefs and `autopilotPrefs.ts`.

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

public let SURVIVAL_STEERS = SurvivalSteer.allCases

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
  /// A tint around the board for who is better.
  public var boardGlow: Bool
  public var moments: Bool
  public var missions: Bool
  public var combo: Bool
  /// Before your move lands, what it leaves undefended flashes.
  public var undefendedFlash: Bool
}

public let DEFAULT_SURVIVAL = SurvivalPrefs(
  steer: .lines, clock: .off, moveScores: true, boardGlow: true, moments: true, missions: true, combo: true,
  undefendedFlash: false)

public enum DrillForm: String, Sendable, Codable { case positions, lines }
public enum DrillDraw: String, Sendable, Codable { case due, new, cram }

public struct DrillPrefs: Equatable, Sendable, Codable {
  public var form: DrillForm
  public var draw: DrillDraw
  public var newPerSession: Int
  public var followLine: Bool
  public var weakFirst: Bool
  public var explain: Bool
  public var batchSimilar: Bool
  public var clock: ClockMode
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
  public var boardGlow: Bool
  public init(moveScores: Bool, boardGlow: Bool) {
    self.moveScores = moveScores
    self.boardGlow = boardGlow
  }
}

public let DEFAULT_AUTOPILOT = AutopilotPrefs(moveScores: true, boardGlow: true)

/// Drill rounds: no clock, Why? always offered.
public let AUTO_DRILL = DrillPrefs(
  form: .positions, draw: .due, newPerSession: 8, followLine: true, weakFirst: false, explain: true,
  batchSimilar: true, clock: .off)

/// Growth rounds, and what counts as ready to grow. Autopilot never grows past the book.
public let AUTO_GROWTH = GrowthPrefs(minShare: 1, maxPly: 18, nudgePriority: .transposition, nudgePawns: false, pastBook: false)

/// Survival rounds: Autopilot steers, there is no clock, the feedback is yours.
public func autoSurvival(_ prefs: AutopilotPrefs) -> SurvivalPrefs {
  SurvivalPrefs(
    steer: .lines, clock: .off, moveScores: prefs.moveScores, boardGlow: prefs.boardGlow, moments: true,
    missions: true, combo: true, undefendedFlash: false)
}

public struct ModePrefs: Equatable, Sendable, Codable {
  public var survival: SurvivalPrefs
  public var drill: DrillPrefs
  public var growth: GrowthPrefs
}

public func autopilotModes(_ prefs: AutopilotPrefs) -> ModePrefs {
  ModePrefs(survival: autoSurvival(prefs), drill: AUTO_DRILL, growth: AUTO_GROWTH)
}
