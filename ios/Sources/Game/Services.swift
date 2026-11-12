import ChessCore
import Engine
import Foundation
import Model

/// Time as the game sees it: what the clock reads, and how a beat is waited out.
/// The app waits in real time; a headless game waits on `VirtualClock`.
@MainActor public protocol GameClock: AnyObject {
  /// Seconds since the epoch.
  var now: Double { get }
  /// Wait `seconds`. Returns early when the task is cancelled.
  func sleep(_ seconds: Double) async
}

/// The device's clock.
@MainActor public final class LiveClock: GameClock {
  public init() {}
  public var now: Double { Date().timeIntervalSince1970 }
  public func sleep(_ seconds: Double) async { try? await Task.sleep(for: .seconds(seconds)) }
}

/// Something the game shows or does for a moment, besides what stays on the board.
public enum GameSignal: Equatable, Sendable {
  /// A haptic buzz of this many milliseconds.
  case buzz(Int)
  /// The success haptic, for a find.
  case success
  /// A word over the board: "Off prep", "Found it".
  case callout(String, good: Bool)
  /// A move's score floating over its square.
  case pop(Pop)
  /// Your prepared move shown after a miss.
  case miss(MissFlash)
  /// A short message: Growth's toasts, or a mode saying it can't start.
  case toast(String)
  /// "End of the book" over a Growth sitting's board.
  case edgeFlash
}

/// Where the game sends its signals: the app turns buzzes into haptics; a headless game keeps them all.
@MainActor public protocol SignalSink: AnyObject {
  func emit(_ signal: GameSignal)
}

/// Everything the game needs from outside itself: the clock, an engine for each use,
/// and somewhere to send signals. One per app; headless games each have their own.
@MainActor public final class GameServices {
  public let clock: GameClock
  /// A new engine, with its own memory of positions.
  public let makeEngine: @Sendable () -> ChessEngine
  public weak var sink: SignalSink?
  /// How long Play's deal holds before the board takes over.
  public var dealSeconds: Double
  /// Work started and not yet finished, for a headless game to wait on.
  public private(set) var busy = 0

  public init(clock: GameClock = LiveClock(), makeEngine: @escaping @Sendable () -> ChessEngine = { Engine.makeEngine() }, dealSeconds: Double = 1.2) {
    self.clock = clock
    self.makeEngine = makeEngine
    self.dealSeconds = dealSeconds
  }

  /// The hints' engine: lenses, evals and checks ask it, so they never wait on the game's engine.
  public private(set) lazy var hints: ChessEngine = makeEngine()
  /// What Growth asks the engine: the eval bar and each answer's eval.
  public private(set) lazy var growthEngine = GrowthEngine(services: self)
  /// Single-move checks: soundness and what a move gives away.
  public private(set) lazy var checks = EngineChecks(services: self)

  /// Engines kept per use, made on first ask: Play's opponent, Middlegame's builder.
  private var slots: [String: ChessEngine] = [:]
  public func engine(_ use: String) -> ChessEngine {
    if let made = slots[use] { return made }
    let made = makeEngine()
    slots[use] = made
    return made
  }

  public func emit(_ signal: GameSignal) { sink?.emit(signal) }

  /// Wait `seconds` on the game's clock.
  public func sleep(_ seconds: Double) async { await clock.sleep(seconds) }

  /// Start work on the main actor, counted until it ends.
  @discardableResult
  public func spawn(_ work: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
    busy += 1
    return Task { @MainActor in
      await work()
      self.busy -= 1
    }
  }
}
