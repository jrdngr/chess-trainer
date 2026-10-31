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
  public var showCoordinates = false
  /// Whether the opening question has been put to this player.
  public var onboarded = false
  public init() {}
}

public struct AppState: Equatable, Sendable, Codable {
  public var repertoires: [String: Repertoire] = [:]
  public var repertoireOrder: [String] = []
  public var cards: [String: Card] = [:]
  public var score = ScoreState()
  public var survival = SurvivalRecord()
  public var mistakes: [Mistake] = []
  public var settings = Settings()
  public init() {}

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

  /// A starter set as a first Playbook: each opening exactly its own moves,
  /// starred where the book names it, with the selection it implies.
  public mutating func seed(_ tree: OpeningTree, _ set: StarterSet) {
    var picks: [(id: String, color: Color)] = []
    for opening in setOpenings(set) {
      let sans = opening.id.split(separator: " ").map(String.init)
      guard walkSan(sans).moves.count == sans.count else { continue }
      let repId: String
      if let found = repertoireList.first(where: { $0.color == opening.color }) {
        repId = found.id
      } else {
        let rep = createRepertoire(repertoireName(opening.color), opening.color)
        repertoires[rep.id] = rep
        repertoireOrder.append(rep.id)
        repId = rep.id
      }
      repertoires[repId] = addLine(repertoires[repId]!, sans, .fixed(.picker)).rep
      if let node = tree.byId[opening.id], node.depth > 0 {
        if !settings.favoriteOpenings.contains(node.id) { settings.favoriteOpenings.append(node.id) }
        picks.append((node.id, opening.color))
      }
    }
    settings.selection = selectionFor(picks)
    settings.onboarded = true
  }
}

/// The global selection picks imply: `onboarding.selectionFor`.
public func selectionFor(_ picks: [(id: String, color: Color)]) -> Selection {
  guard let first = picks.first else { return DEFAULT_SELECTION }
  let colors = Set(picks.map(\.color))
  let color: ColorChoice = colors.count == 1 ? (first.color == .w ? .w : .b) : .random
  return Selection(color: color, opening: picks.count == 1 ? first.id : ANY_FAVORITE)
}
