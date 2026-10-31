/// What Play remembers between visits: `PlayPrefs` in `src/model/modes.ts`.
public struct PlayPrefs: Equatable, Sendable, Codable {
  /// One of LEVELS.
  public var level: String
  /// Write the opening into a repertoire when the game ends.
  public var save: Bool
  /// Say so the moment you leave your own prep.
  public var warnOffBook: Bool
  public var showEval: Bool
  public var takeBacks: Bool

  public init(level: String, save: Bool, warnOffBook: Bool, showEval: Bool, takeBacks: Bool) {
    self.level = level
    self.save = save
    self.warnOffBook = warnOffBook
    self.showEval = showEval
    self.takeBacks = takeBacks
  }

  enum CodingKeys: String, CodingKey { case level, save, warnOffBook, showEval, takeBacks }

  /// A save missing an option takes its default.
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let d = DEFAULT_PLAY
    level = try c.decodeIfPresent(String.self, forKey: .level) ?? d.level
    save = try c.decodeIfPresent(Bool.self, forKey: .save) ?? d.save
    warnOffBook = try c.decodeIfPresent(Bool.self, forKey: .warnOffBook) ?? d.warnOffBook
    showEval = try c.decodeIfPresent(Bool.self, forKey: .showEval) ?? d.showEval
    takeBacks = try c.decodeIfPresent(Bool.self, forKey: .takeBacks) ?? d.takeBacks
  }
}

public let DEFAULT_PLAY = PlayPrefs(level: DEFAULT_LEVEL, save: true, warnOffBook: true, showEval: false, takeBacks: true)

extension AppState {
  /// Keep a game finished in Play: `useStore.recordPlayGame`.
  public mutating func recordPlayGame(_ game: ImportedGame) {
    importedGames = withPlayGame(importedGames, game)
  }

  /// A move off your prep in Play, logged for practice: `useStore.logMistake`.
  public mutating func logMistake(_ mistake: Mistake) {
    mistakes = addMistake(mistakes, mistake)
  }
}
