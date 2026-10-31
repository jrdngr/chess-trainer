import Engine

/// The hints' own engine: lenses and the end screen's eval bar ask it, so
/// they never wait on, or interrupt, the game's engine.
enum HintEngine {
  static let shared = BasicEngine()
}
