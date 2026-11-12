import Engine
import Game

/// The hints' own engine: lenses and the end screen's eval bar ask it, so
/// they never wait on, or interrupt, the game's engine.
@MainActor
enum HintEngine {
  static var shared: ChessEngine { LiveGame.services.hints }
}

extension GrowthEngine {
  /// The app's Growth evals.
  static var shared: GrowthEngine { LiveGame.services.growthEngine }
}

extension EngineChecks {
  /// The app's move checks.
  static var shared: EngineChecks { LiveGame.services.checks }
}
