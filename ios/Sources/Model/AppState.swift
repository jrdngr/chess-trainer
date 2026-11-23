import ChessCore

/// What the app keeps, and what a run changes in it, as pure functions on
/// one value.
/// The app saves it; the event log, sync and imported games come later.

public struct Settings: Equatable, Sendable, Codable {
  public var selection = DEFAULT_SELECTION
  /// Starred openings from older saves, by tree node id. Nothing reads them;
  /// they are kept so a save round-trips.
  public var favoriteOpenings: [String] = []
  public var play = DEFAULT_PLAY
  public var hapticFeedback = true
  public var showCoordinates = true
  /// Whether the opening question has been put to this player.
  public var onboarded = false
  /// Whether the pages on how the app works have been shown.
  public var seenIntro = false
  public var lichessUsername = ""
  public var chesscomUsername = ""
  public var growth = DEFAULT_GROWTH
  /// Whether the note on autoplay has been shown.
  public var seenAutoplayNote = false
  /// Whether the tip on drawing from the deck after a Play round has been put away.
  public var seenDeckTip = false
  /// The tips already shown.
  public var seenTips: Set<GameTip> = []
  /// Middlegame mode's setup.
  public var middlegame = DEFAULT_MIDDLEGAME
  /// How Play's runs start: from move one, or wherever your prep needs work.
  public var start = RunStart.drill
  /// How a run's header names its opening.
  public var openingNames = OpeningNames.family
  public init() {}

  enum CodingKeys: String, CodingKey {
    case selection, favoriteOpenings, play, hapticFeedback, showCoordinates, onboarded, seenIntro
    case lichessUsername, chesscomUsername, growth
    case seenAutoplayNote, seenDeckTip, seenTips
    case middlegame
    case start
    case openingNames
  }

  /// A save missing a setting takes its default.
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.init()
    selection = try c.decodeIfPresent(Selection.self, forKey: .selection) ?? selection
    if selection.opening == LEGACY_ANY_FAVORITE { selection.opening = ANY_OPENING }
    favoriteOpenings = try c.decodeIfPresent([String].self, forKey: .favoriteOpenings) ?? favoriteOpenings
    play = try c.decodeIfPresent(PlayPrefs.self, forKey: .play) ?? play
    hapticFeedback = try c.decodeIfPresent(Bool.self, forKey: .hapticFeedback) ?? hapticFeedback
    showCoordinates = try c.decodeIfPresent(Bool.self, forKey: .showCoordinates) ?? showCoordinates
    onboarded = try c.decodeIfPresent(Bool.self, forKey: .onboarded) ?? onboarded
    seenIntro = try c.decodeIfPresent(Bool.self, forKey: .seenIntro) ?? seenIntro
    lichessUsername = try c.decodeIfPresent(String.self, forKey: .lichessUsername) ?? lichessUsername
    chesscomUsername = try c.decodeIfPresent(String.self, forKey: .chesscomUsername) ?? chesscomUsername
    growth = try c.decodeIfPresent(GrowthPrefs.self, forKey: .growth) ?? growth
    // How common and how deep are no longer settings.
    growth.minShare = DEFAULT_GROWTH.minShare
    growth.maxPly = DEFAULT_GROWTH.maxPly
    seenAutoplayNote = try c.decodeIfPresent(Bool.self, forKey: .seenAutoplayNote) ?? seenAutoplayNote
    seenDeckTip = try c.decodeIfPresent(Bool.self, forKey: .seenDeckTip) ?? seenDeckTip
    // Names this version doesn't know are dropped.
    seenTips = Set((try c.decodeIfPresent([String].self, forKey: .seenTips) ?? []).compactMap(GameTip.init(rawValue:)))
    middlegame = try c.decodeIfPresent(RunPrefs.self, forKey: .middlegame) ?? middlegame
    start = try c.decodeIfPresent(RunStart.self, forKey: .start) ?? start
    openingNames = try c.decodeIfPresent(OpeningNames.self, forKey: .openingNames) ?? openingNames
  }
}

/// A run's header names its opening's family (Sicilian Defense), or the book's
/// name for the line (Najdorf Variation, with the family over it).
public enum OpeningNames: String, Sendable, Codable, CaseIterable { case family, book }

/// How Play's runs start. Freeform: every run from move one, the opponent steering
/// toward what needs work. Drill: at the opening's position, deeper inside, or cold, by need.
public enum RunStart: String, Sendable, Codable, CaseIterable { case freeform, drill }

/// The board's colours.
public enum BoardTheme: String, Sendable, Codable, CaseIterable { case slate, walnut, ocean }

public struct AppState: Equatable, Sendable, Codable {
  public var playbooks: [String: Playbook] = [:]
  public var playbookOrder: [String] = []
  public var cards: [String: Card] = [:]
  public var score = ScoreState()
  public var runRecord = RunRecord()
  public var mistakes: [Mistake] = []
  /// Every review, oldest first.
  public var log: [ReviewLogEntry] = []
  public var events: [AppEvent] = []
  public var settings = Settings()
  /// Your playing strength, from the moves the judge weighed.
  public var strength = PlayerStrength()
  /// Endgame mode: its cards, family results and saved positions.
  public var endgames = EndgameRecord()
  /// Middlegame mode's moves survived, per opening and overall.
  public var middlegame = RunRecord()
  /// Each opening's form: its last prep answers.
  public var form = FormRecord()
  /// Pawns to spend in the Pawn Shop.
  public var pawns = 0
  /// The days in a row with a game, for streak pawns.
  public var pawnStreak = PawnStreak()
  /// What the Pawn Shop sold you, by item id.
  public var unlocked: Set<String> = []
  /// Opening families bought.
  public var families = FamilyRecord()
  /// App Store transactions already credited, by id: each one pays once.
  public var credited: Set<String> = []
  /// The feature items the App Store unlock gave, which a refund of it takes back.
  public var cashUnlocked: Set<String> = []
  /// The games you played here, newest first, at most GAMES_CAP.
  public var games: [GameRecord] = []
  /// Every Play game you have played, never capped; a save from before it counts its history's.
  public var playGamesPlayed = 0
  /// The growth levels that have opened: once open, a level stays open.
  public var levelsOpened: Set<Int> = []
  /// The version the save was written at: one older than SAVE_VERSION is wiped on load.
  public var version = SAVE_VERSION
  public init() {}

  enum CodingKeys: String, CodingKey {
    case playbooks, playbookOrder, cards, score, runRecord, mistakes, log, events, settings, strength, endgames, middlegame
    case games, version, pawns, pawnStreak, form, unlocked, families, credited, cashUnlocked, playGamesPlayed, levelsOpened
  }

  /// A save from before a field existed takes its default.
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.init()
    playbooks = try c.decodeIfPresent([String: Playbook].self, forKey: .playbooks) ?? playbooks
    playbookOrder = try c.decodeIfPresent([String].self, forKey: .playbookOrder) ?? playbookOrder
    cards = try c.decodeIfPresent([String: Card].self, forKey: .cards) ?? cards
    score = try c.decodeIfPresent(ScoreState.self, forKey: .score) ?? score
    runRecord = try c.decodeIfPresent(RunRecord.self, forKey: .runRecord) ?? runRecord
    mistakes = try c.decodeIfPresent([Mistake].self, forKey: .mistakes) ?? mistakes
    log = try c.decodeIfPresent([ReviewLogEntry].self, forKey: .log) ?? log
    events = normalizeEvents(try c.decodeIfPresent([AppEvent].self, forKey: .events))
    settings = try c.decodeIfPresent(Settings.self, forKey: .settings) ?? settings
    strength = try c.decodeIfPresent(PlayerStrength.self, forKey: .strength) ?? strength
    endgames = try c.decodeIfPresent(EndgameRecord.self, forKey: .endgames) ?? endgames
    middlegame = try c.decodeIfPresent(RunRecord.self, forKey: .middlegame) ?? middlegame
    games = try c.decodeIfPresent([GameRecord].self, forKey: .games) ?? games
    form = try c.decodeIfPresent(FormRecord.self, forKey: .form) ?? form
    pawns = try c.decodeIfPresent(Int.self, forKey: .pawns) ?? pawns
    pawnStreak = try c.decodeIfPresent(PawnStreak.self, forKey: .pawnStreak) ?? pawnStreak
    unlocked = try c.decodeIfPresent(Set<String>.self, forKey: .unlocked) ?? unlocked
    families = try c.decodeIfPresent(FamilyRecord.self, forKey: .families) ?? families
    credited = try c.decodeIfPresent(Set<String>.self, forKey: .credited) ?? credited
    cashUnlocked = try c.decodeIfPresent(Set<String>.self, forKey: .cashUnlocked) ?? cashUnlocked
    playGamesPlayed = try c.decodeIfPresent(Int.self, forKey: .playGamesPlayed) ?? games.filter { $0.mode == .play }.count
    levelsOpened = try c.decodeIfPresent(Set<Int>.self, forKey: .levelsOpened) ?? levelsOpened
    version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 0
  }

  public var playbookList: [Playbook] { playbookOrder.compactMap { playbooks[$0] } }
}

extension AppState {
  /// An answer: activity for its openings and, for a prep answer in a run, their form.
  public mutating func recordMove(_ tree: OpeningTree, _ result: MoveResult) {
    if result.rated { form.add(tree, result) }
    score = applyResult(score, tree, result)
  }

  public mutating func endRound(_ tree: OpeningTree, _ round: RoundRecord) {
    score = recordRound(score, tree, round)
  }

  public mutating func recordRunEnd(_ tree: OpeningTree, _ line: [String], _ moves: Int) {
    runRecord = recordRun(runRecord, tree, line, moves)
  }

  public mutating func endRunEarly(_ tree: OpeningTree, _ line: [String]) {
    runRecord = recordEndedRun(runRecord, tree, line)
  }

  /// A Middlegame run, logged in moves survived against every opening your line went through.
  public mutating func endMiddlegame(_ tree: OpeningTree, _ line: [String], _ moves: Int) {
    middlegame = recordRun(middlegame, tree, line, moves)
  }

  public mutating func endMiddlegameEarly(_ tree: OpeningTree, _ line: [String]) {
    middlegame = recordEndedRun(middlegame, tree, line)
  }

  /// A prepared position answered in a run: its card reviewed, and marked with the run that asked it.
  public mutating func answered(_ playbookId: String, _ fen: String, _ played: String, _ grade: Grade, now: Double = Env.now()) {
    let key = positionKey(fen)
    let id = cardId(playbookId, key)
    let existing = cards[id]
    cards[id] = review(existing ?? createCard(id, playbookId, key, fen, now), existing != nil ? grade : .good, round: score.lineRounds, now: now)
    // A logged mistake retires once the position is answered right.
    mistakes.removeAll { $0.id == "\(playbookId)#\(key)" }
  }

  /// A prepared position missed in a run: its card failed, and the miss logged.
  public mutating func missed(_ playbookId: String, _ fen: String, _ played: String, _ expected: String, now: Double = Env.now()) {
    let key = positionKey(fen)
    let id = cardId(playbookId, key)
    cards[id] = review(cards[id] ?? createCard(id, playbookId, key, fen, now), .again, round: score.lineRounds, now: now)
    mistakes = Env.at(now) {
      addMistake(mistakes, Mistake(source: .openingRun, playbookId: playbookId, key: key, fen: fen, played: played, expected: expected))
    }
  }

  /// Finishing onboarding: `useStore.onboarded`. Picked openings go in as
  /// their own moves. A move order that is not legal is not an opening, and is left
  /// out. Skipping puts nothing in but is still an answer.
  public mutating func onboarded(_ tree: OpeningTree, _ openings: [SeedOpening]) {
    let legal = { (sans: [String]) in walkSan(sans).fens.count == sans.count + 1 }
    for opening in openings where legal(opening.sans) {
      let repId = ensurePlaybook(opening.color)
      addLine(repId, opening.sans, .fixed(.picker), via: .onboarding)
    }
    // The selection follows the picks the book names.
    let picks = openings.compactMap { opening -> (id: String, color: Color)? in
      guard let node = tree.byId[opening.sans.joined(separator: " ")], node.depth > 0 else { return nil }
      return (node.id, opening.color)
    }
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

/// Whose an opening is, read from its move order, unless a side is given.
public func seedFor(_ sans: [String], _ color: Color? = nil) -> SeedOpening {
  SeedOpening(sans: sans, color: color ?? playerOf(sans))
}

/// The global selection picks imply: `onboarding.selectionFor`.
public func selectionFor(_ picks: [(id: String, color: Color)]) -> Selection {
  guard let first = picks.first else { return DEFAULT_SELECTION }
  let colors = Set(picks.map(\.color))
  let color: ColorChoice = colors.count == 1 ? (first.color == .w ? .w : .b) : .either
  return Selection(color: color, opening: picks.count == 1 ? first.id : ANY_OPENING)
}
