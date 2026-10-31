import ChessCore

/// What the app keeps, and what a run changes in it: the parts of
/// `src/store/useStore.ts` Autopilot needs, as pure functions on one value.
/// The app saves it; the event log, sync and imported games come later.

public struct Settings: Equatable, Sendable, Codable {
  public var selection = DEFAULT_SELECTION
  /// Starred openings, by tree node id.
  public var favoriteOpenings: [String] = []
  public var autopilot = DEFAULT_AUTOPILOT
  public var hapticFeedback = true
  public var showCoordinates = true
  /// Whether the opening question has been put to this player.
  public var onboarded = false
  /// Rounds that start inside an opening play the moves into it for you first.
  public var autoplay = true
  public var engineEnabled = true
  public var boardTheme = BoardTheme.slate
  public var cloudSync = true
  public var lichessUsername = ""
  public var chesscomUsername = ""
  public var growth = DEFAULT_GROWTH
  public init() {}

  enum CodingKeys: String, CodingKey {
    case selection, favoriteOpenings, autopilot, hapticFeedback, showCoordinates, onboarded, autoplay
    case engineEnabled, boardTheme, cloudSync, lichessUsername, chesscomUsername, growth
  }

  /// A save missing a setting takes its default.
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.init()
    selection = try c.decodeIfPresent(Selection.self, forKey: .selection) ?? selection
    favoriteOpenings = try c.decodeIfPresent([String].self, forKey: .favoriteOpenings) ?? favoriteOpenings
    autopilot = try c.decodeIfPresent(AutopilotPrefs.self, forKey: .autopilot) ?? autopilot
    hapticFeedback = try c.decodeIfPresent(Bool.self, forKey: .hapticFeedback) ?? hapticFeedback
    showCoordinates = try c.decodeIfPresent(Bool.self, forKey: .showCoordinates) ?? showCoordinates
    onboarded = try c.decodeIfPresent(Bool.self, forKey: .onboarded) ?? onboarded
    autoplay = try c.decodeIfPresent(Bool.self, forKey: .autoplay) ?? autoplay
    engineEnabled = try c.decodeIfPresent(Bool.self, forKey: .engineEnabled) ?? engineEnabled
    boardTheme = try c.decodeIfPresent(BoardTheme.self, forKey: .boardTheme) ?? boardTheme
    cloudSync = try c.decodeIfPresent(Bool.self, forKey: .cloudSync) ?? cloudSync
    lichessUsername = try c.decodeIfPresent(String.self, forKey: .lichessUsername) ?? lichessUsername
    chesscomUsername = try c.decodeIfPresent(String.self, forKey: .chesscomUsername) ?? chesscomUsername
    growth = try c.decodeIfPresent(GrowthPrefs.self, forKey: .growth) ?? growth
  }
}

/// The board's colours.
public enum BoardTheme: String, Sendable, Codable, CaseIterable { case slate, walnut, ocean }

public struct AppState: Equatable, Sendable, Codable {
  public var repertoires: [String: Repertoire] = [:]
  public var repertoireOrder: [String] = []
  public var cards: [String: Card] = [:]
  public var score = ScoreState()
  public var survival = SurvivalRecord()
  public var mistakes: [Mistake] = []
  public var lineCards: [String: LineCard] = [:]
  /// Every review, oldest first.
  public var log: [ReviewLogEntry] = []
  public var events: [AppEvent] = []
  public var settings = Settings()
  public init() {}

  enum CodingKeys: String, CodingKey {
    case repertoires, repertoireOrder, cards, score, survival, mistakes, lineCards, log, events, settings
  }

  /// A save from before a field existed takes its default.
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.init()
    repertoires = try c.decodeIfPresent([String: Repertoire].self, forKey: .repertoires) ?? repertoires
    repertoireOrder = try c.decodeIfPresent([String].self, forKey: .repertoireOrder) ?? repertoireOrder
    cards = try c.decodeIfPresent([String: Card].self, forKey: .cards) ?? cards
    score = try c.decodeIfPresent(ScoreState.self, forKey: .score) ?? score
    survival = try c.decodeIfPresent(SurvivalRecord.self, forKey: .survival) ?? survival
    mistakes = try c.decodeIfPresent([Mistake].self, forKey: .mistakes) ?? mistakes
    lineCards = try c.decodeIfPresent([String: LineCard].self, forKey: .lineCards) ?? lineCards
    log = try c.decodeIfPresent([ReviewLogEntry].self, forKey: .log) ?? log
    events = normalizeEvents(try c.decodeIfPresent([AppEvent].self, forKey: .events))
    settings = try c.decodeIfPresent(Settings.self, forKey: .settings) ?? settings
  }

  public var repertoireList: [Repertoire] { repertoireOrder.compactMap { repertoires[$0] } }
}

extension AppState {
  /// A rated answer: `useStore.recordMove`.
  public mutating func recordMove(_ tree: OpeningTree, _ result: MoveResult, _ earlier: [MoveResult]) -> [RatingMove] {
    let applied = applyResult(score, tree, result, earlier)
    score = applied.state
    return applied.moves
  }

  /// The run's line went further than its last answer.
  public mutating func settleRun(_ tree: OpeningTree, _ earlier: [MoveResult], _ line: [String]) -> [RatingMove] {
    let settled = Model.settleRun(score, tree, earlier, line)
    score = settled.state
    return settled.moves
  }

  public mutating func endRound(_ tree: OpeningTree, _ round: RoundRecord) {
    score = recordRound(score, tree, round)
  }

  public mutating func noteStart(_ kind: StartKind) {
    score = recordStart(score, kind)
  }

  public mutating func endSurvival(_ tree: OpeningTree, _ line: [String], _ moves: Int, _ points: Int) {
    survival = recordSurvival(survival, tree, line, moves, points)
  }

  public mutating func endSurvivalEarly(_ tree: OpeningTree, _ line: [String]) {
    survival = recordEndedSurvival(survival, tree, line)
  }

  /// A prepared position answered in a run: its card reviewed, and marked with the run that asked it.
  public mutating func answered(_ repertoireId: String, _ fen: String, _ played: String, _ grade: Grade, now: Double = Env.now()) {
    let key = positionKey(fen)
    let id = cardId(repertoireId, key)
    let existing = cards[id]
    var card = review(existing ?? createCard(id, repertoireId, key, fen, now), existing != nil ? grade : .good, now).card
    card.testedRound = score.lineRounds
    cards[id] = card
    // A logged mistake retires once the position is answered right.
    mistakes.removeAll { $0.id == "\(repertoireId)#\(key)" }
  }

  /// A prepared position missed in a run: its card failed, and the miss logged.
  public mutating func missed(_ repertoireId: String, _ fen: String, _ played: String, _ expected: String, now: Double = Env.now()) {
    let key = positionKey(fen)
    let id = cardId(repertoireId, key)
    var card = review(cards[id] ?? createCard(id, repertoireId, key, fen, now), .again, now).card
    card.testedRound = score.lineRounds
    cards[id] = card
    mistakes = Env.at(now) {
      addMistake(mistakes, Mistake(source: .openingRun, repertoireId: repertoireId, key: key, fen: fen, played: played, expected: expected))
    }
  }

  /// A starter set as a first Playbook: each opening exactly its own moves.
  public mutating func seed(_ tree: OpeningTree, _ set: StarterSet) {
    onboarded(tree, setOpenings(set).map { SeedOpening(sans: $0.id.split(separator: " ").map(String.init), color: $0.color) })
  }

  /// Finishing onboarding: `useStore.onboarded`. Picked openings go in as
  /// their own moves and are starred; lines played on the board go in whole,
  /// marked as played on the board, and starred only through a picked
  /// opening. A move order that is not legal is not an opening, and is left
  /// out. Skipping puts nothing in but is still an answer.
  public mutating func onboarded(_ tree: OpeningTree, _ openings: [SeedOpening], _ board: [OnboardingLine] = []) {
    let legal = { (sans: [String]) in walkSan(sans).fens.count == sans.count + 1 }
    let lines: [(line: OnboardingLine, source: MoveSource)] =
      board.filter { legal($0.sans) }.map { ($0, .board) }
      + openings.filter { legal($0.sans) }.map { (OnboardingLine(sans: $0.sans, color: $0.color), .picker) }
    for (line, source) in lines {
      let repId = ensureRepertoire(line.color)
      addLine(repId, line.sans, .fixed(source), via: .onboarding, lost: line.lost)
    }
    // Starred where the book names them, so they lead the quick picker and Home's ladder.
    let picks = openings.compactMap { opening -> (id: String, color: Color)? in
      guard let node = tree.byId[opening.sans.joined(separator: " ")], node.depth > 0 else { return nil }
      return (node.id, opening.color)
    }
    for pick in picks where !settings.favoriteOpenings.contains(pick.id) { settings.favoriteOpenings.append(pick.id) }
    // Nothing picked says nothing about which side they play.
    if !picks.isEmpty { settings.selection = selectionFor(picks) }
    settings.onboarded = true
  }
}

/// An opening picked to start with: its own moves, for the side that plays it.
public struct SeedOpening: Equatable, Sendable {
  public var sans: [String]
  public var color: Color
  public init(sans: [String], color: Color) {
    self.sans = sans
    self.color = color
  }
}

/// A line played on onboarding's board, with what each move lost, if known.
public struct OnboardingLine: Equatable, Sendable {
  public var sans: [String]
  public var color: Color
  public var lost: [Double?]?
  public init(sans: [String], color: Color, lost: [Double?]? = nil) {
    self.sans = sans
    self.color = color
    self.lost = lost
  }
}

/// Whose an opening is, read from its move order, unless a side is given.
public func seedFor(_ sans: [String], _ color: Color? = nil) -> SeedOpening {
  SeedOpening(sans: sans, color: color ?? playerOf(sans))
}

/// The global selection picks imply: `onboarding.selectionFor`.
public func selectionFor(_ picks: [(id: String, color: Color)]) -> Selection {
  guard let first = picks.first else { return DEFAULT_SELECTION }
  let colors = Set(picks.map(\.color))
  let color: ColorChoice = colors.count == 1 ? (first.color == .w ? .w : .b) : .random
  return Selection(color: color, opening: picks.count == 1 ? first.id : ANY_FAVORITE)
}
