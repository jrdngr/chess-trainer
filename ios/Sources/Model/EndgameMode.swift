import ChessCore

/// Endgame mode: a library of must-know endings, each played out against the
/// engine with one goal. Win it: a known win to convert. Hold it: a known draw
/// to hold. Each position is a card on its own schedule, and each family of
/// endings has its own tier.

public enum EndgameGoal: String, Sendable, Codable {
  case win, hold
  /// "Win it" or "Hold it".
  public var label: String { self == .win ? "Win it" : "Hold it" }
}

/// What a round asks of you on top of its goal.
public enum EndgameMission: Equatable, Sendable, Codable {
  /// Checkmate within this many of your moves.
  case mateIn(Int)
  /// Promote a pawn and keep the win.
  case queenPawn
  /// Keep the result for this many of your moves.
  case holdFor(Int)

  /// The goal card's heading.
  public var title: String {
    switch self {
    case .mateIn: "MATE IT"
    case .queenPawn: "QUEEN IT"
    case .holdFor: "HOLD IT"
    }
  }

  public var text: String {
    switch self {
    case .mateIn(let n): "Mate in \(n) or fewer"
    case .queenPawn: "Queen a pawn"
    case .holdFor(let n): "Hold for \(n) moves"
    }
  }
}

/// The card shown before a position is played the first time, and on asking.
public struct EndgameIntro: Equatable, Sendable {
  public var title: String
  public var lines: [String]
}

/// The material a basic-mate setup is drawn with, beside the two kings.
public enum BasicMate: String, Sendable, Codable, CaseIterable {
  case queen, rook, bishops
}

public struct EndgameFamily: Equatable, Sendable {
  public var id: String
  public var name: String
}

public struct EndgameEntry: Equatable, Sendable {
  public var id: String
  public var family: String
  public var name: String
  /// The position, you to move; nil for a basic mate, set up fresh each time.
  public var fen: String?
  public var setup: BasicMate?
  public var goal: EndgameGoal
  public var mission: EndgameMission
  public var intro: EndgameIntro?
}

public let ENDGAME_FAMILIES: [EndgameFamily] = [
  EndgameFamily(id: "mates", name: "Basic mates"),
  EndgameFamily(id: "pawn", name: "King and pawn"),
  EndgameFamily(id: "rook", name: "Rook endings"),
  EndgameFamily(id: "games", name: "From your games"),
]

public let ENDGAME_LIBRARY: [EndgameEntry] = [
  EndgameEntry(
    id: "mate-queen", family: "mates", name: "Queen mate", fen: nil, setup: .queen, goal: .win, mission: .mateIn(10),
    intro: EndgameIntro(title: "Box the king in", lines: [
      "Take squares away with the queen, a knight\u{2019}s move from the king.",
      "Bring your king up, then mate on the edge.",
    ])),
  EndgameEntry(
    id: "mate-rook", family: "mates", name: "Rook mate", fen: nil, setup: .rook, goal: .win, mission: .mateIn(16),
    intro: EndgameIntro(title: "Shrink the box", lines: [
      "Cut the king off with the rook.",
      "Take the opposition with your king, then push it back a rank with a check.",
    ])),
  EndgameEntry(
    id: "mate-bishops", family: "mates", name: "Two bishops", fen: nil, setup: .bishops, goal: .win, mission: .mateIn(19),
    intro: EndgameIntro(title: "Bishops side by side", lines: [
      "Let the bishops wall the king off together.",
      "Drive it to a corner with your king\u{2019}s help, and watch for stalemate.",
    ])),
  EndgameEntry(
    id: "kp-key-squares", family: "pawn", name: "Key squares", fen: "8/8/4k3/8/4K3/8/4P3/8 w - - 0 1", setup: nil, goal: .win,
    mission: .queenPawn,
    intro: EndgameIntro(title: "Your king on a key square", lines: [
      "Your king already stands on a key square: the pawn queens.",
      "Lead with the king, and push the pawn only when it is safe.",
    ])),
  EndgameEntry(
    id: "kp-opposition", family: "pawn", name: "Opposition", fen: "8/8/4k3/8/8/4K3/4P3/8 b - - 0 1", setup: nil, goal: .hold,
    mission: .holdFor(15),
    intro: EndgameIntro(title: "Take the opposition", lines: [
      "Stand in front of the pawn, facing their king with one square between.",
      "When the pawn steps up, step back in front of it.",
    ])),
  EndgameEntry(
    id: "kp-square", family: "pawn", name: "Square rule", fen: "8/8/8/8/P7/8/8/5k1K w - - 0 1", setup: nil, goal: .win,
    mission: .queenPawn,
    intro: EndgameIntro(title: "Outrun the king", lines: [
      "Their king is outside the pawn\u{2019}s square: it can\u{2019}t catch the pawn.",
      "Run with the pawn.",
    ])),
  EndgameEntry(
    id: "rook-lucena", family: "rook", name: "Lucena", fen: "3K4/3P1k2/8/8/8/8/2r5/4R3 w - - 0 1", setup: nil, goal: .win,
    mission: .queenPawn,
    intro: EndgameIntro(title: "Build a bridge", lines: [
      "Lift your rook to the 4th rank.",
      "Walk your king out, then block the checks with the rook.",
    ])),
  EndgameEntry(
    id: "rook-philidor", family: "rook", name: "Philidor", fen: "8/8/8/8/4pk2/R7/1r6/4K3 w - - 0 1", setup: nil, goal: .hold,
    mission: .holdFor(20),
    intro: EndgameIntro(title: "Hold the third rank", lines: [
      "Keep your rook on your third rank while their king can\u{2019}t get in front.",
      "Once the pawn steps onto it, check from behind.",
    ])),
]

/// A position from one of your games where an endgame result slipped away,
/// kept to play again.
public struct SavedEndgame: Equatable, Sendable, Codable {
  public var id: String
  public var fen: String
  public var goal: EndgameGoal
  /// The game it came from: its opening's name.
  public var name: String
  public var at: Double
  public init(id: String, fen: String, goal: EndgameGoal, name: String, at: Double) {
    self.id = id
    self.fen = fen
    self.goal = goal
    self.name = name
    self.at = at
  }
}

/// How many saved endgames are kept. Older ones fall off the end.
public let SAVED_ENDGAMES_CAP = 30

public extension SavedEndgame {
  var entry: EndgameEntry {
    EndgameEntry(
      id: id, family: "games", name: name, fen: fen, setup: nil, goal: goal,
      mission: goal == .win ? .queenPawn : .holdFor(15), intro: nil)
  }
}

/// One position's schedule: when it is due, and how far apart its reviews have grown.
public struct EndgameCard: Equatable, Sendable, Codable {
  public var due: Double
  /// Days to the next review after a success.
  public var interval: Double
  public var reps: Int
  public var lapses: Int
  public init(due: Double, interval: Double, reps: Int, lapses: Int) {
    self.due = due
    self.interval = interval
    self.reps = reps
    self.lapses = lapses
  }
}

public struct EndgameRecord: Equatable, Sendable, Codable {
  public var cards: [String: EndgameCard] = [:]
  /// One rating per family.
  public var ratings: [String: Double] = [:]
  public var rated: [String: Int] = [:]
  /// The positions whose intro card has been shown.
  public var seenIntros: [String] = []
  /// Newest first.
  public var saved: [SavedEndgame] = []
  public init() {}

  enum CodingKeys: String, CodingKey { case cards, ratings, rated, seenIntros, saved }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    cards = try c.decodeIfPresent([String: EndgameCard].self, forKey: .cards) ?? [:]
    ratings = try c.decodeIfPresent([String: Double].self, forKey: .ratings) ?? [:]
    rated = try c.decodeIfPresent([String: Int].self, forKey: .rated) ?? [:]
    seenIntros = try c.decodeIfPresent([String].self, forKey: .seenIntros) ?? []
    saved = try c.decodeIfPresent([SavedEndgame].self, forKey: .saved) ?? []
  }

  /// Every position to play: the library, then your saved ones.
  public var entries: [EndgameEntry] { ENDGAME_LIBRARY + saved.map(\.entry) }

  /// The family's place on the tier ladder.
  public func rank(_ family: String) -> Rank { rankOf(ratings[family] ?? 0, rated[family] ?? 0) }

  /// Positions due now, oldest due first. A position never played is not due: it waits to be started.
  public func due(_ now: Double) -> [EndgameEntry] {
    entries.filter { e in cards[e.id].map { $0.due <= now } ?? false }
      .sorted { cards[$0.id]!.due < cards[$1.id]!.due }
  }

  /// The next position to play: the first due, else the first never played.
  public func next(_ now: Double) -> EndgameEntry? {
    due(now).first ?? entries.first { cards[$0.id] == nil }
  }
}

public let DAY_MS: Double = 86_400_000
/// What a round is worth to its family's rating.
public let ENDGAME_SUCCESS_POINTS: Double = 40
public let ENDGAME_MISSION_POINTS: Double = 20
public let ENDGAME_FAIL_POINTS: Double = 30

extension EndgameRecord {
  /// A round played: the card moves on its schedule and the family's rating moves.
  /// A success pushes the card out (1 day, then 2.5 times as far each time); a
  /// failure brings it back due now.
  public mutating func review(_ entry: EndgameEntry, success: Bool, mission: Bool, now: Double) {
    var card = cards[entry.id] ?? EndgameCard(due: now, interval: 0, reps: 0, lapses: 0)
    card.reps += 1
    if success {
      card.interval = card.interval == 0 ? 1 : card.interval * 2.5
      card.due = now + card.interval * DAY_MS
    } else {
      card.lapses += 1
      card.interval = 0
      card.due = now
    }
    cards[entry.id] = card
    let delta = success ? ENDGAME_SUCCESS_POINTS + (mission ? ENDGAME_MISSION_POINTS : 0) : -ENDGAME_FAIL_POINTS
    ratings[entry.family] = max(0, (ratings[entry.family] ?? 0) + delta)
    rated[entry.family, default: 0] += 1
  }

  public mutating func sawIntro(_ id: String) {
    if !seenIntros.contains(id) { seenIntros.append(id) }
  }

  /// Keep a position where your game's result slipped, once per position.
  public mutating func save(_ game: SavedEndgame) {
    guard !saved.contains(where: { positionKey($0.fen) == positionKey(game.fen) }) else { return }
    saved.insert(game, at: 0)
    if saved.count > SAVED_ENDGAMES_CAP { saved.removeLast(saved.count - SAVED_ENDGAMES_CAP) }
  }
}

/* ── basic-mate setups ── */

/// A fresh basic-mate position, White to move: their king somewhere in the
/// middle, your king and pieces anywhere it is legal, nothing hanging, no check.
public func basicMateSetup(_ kind: BasicMate, _ rand: @escaping () -> Double) -> String {
  func pick(_ range: ClosedRange<Int>) -> Int { range.lowerBound + min(range.count - 1, Int(rand() * Double(range.count))) }
  for _ in 0..<500 {
    var cells = [Character?](repeating: nil, count: 64)
    let them = (file: pick(1...6), rank: pick(2...5))
    cells[them.rank * 8 + them.file] = "k"
    func place(_ piece: Character, light: Bool? = nil) -> (file: Int, rank: Int)? {
      for _ in 0..<50 {
        let f = pick(0...7), r = pick(0...7)
        guard cells[r * 8 + f] == nil, max(abs(f - them.file), abs(r - them.rank)) >= 2 else { continue }
        if let light, ((f + r) % 2 == 1) != light { continue }
        cells[r * 8 + f] = piece
        return (f, r)
      }
      return nil
    }
    guard place("K") != nil else { continue }
    switch kind {
    case .queen: guard place("Q") != nil else { continue }
    case .rook: guard place("R") != nil else { continue }
    case .bishops: guard place("B", light: true) != nil, place("B", light: false) != nil else { continue }
    }
    var rows: [String] = []
    for r in stride(from: 7, through: 0, by: -1) {
      var row = "", empty = 0
      for f in 0..<8 {
        if let p = cells[r * 8 + f] {
          if empty > 0 { row += String(empty) }
          empty = 0
          row.append(p)
        } else {
          empty += 1
        }
      }
      if empty > 0 { row += String(empty) }
      rows.append(row)
    }
    let placement = rows.joined(separator: "/")
    // Their king must not stand in check with White to move.
    guard !positionStatus("\(placement) b - - 0 1").check else { continue }
    let fen = "\(placement) w - - 0 1"
    if positionStatus(fen).gameOver { continue }
    return fen
  }
  switch kind {
  case .queen: return "8/8/3k4/8/8/8/8/4K2Q w - - 0 1"
  case .rook: return "8/8/3k4/8/8/8/8/4K2R w - - 0 1"
  case .bishops: return "8/8/3k4/8/8/8/8/2B1KB2 w - - 0 1"
  }
}

/// The position a round of this entry starts from.
public func endgameStart(_ entry: EndgameEntry, _ rand: @escaping () -> Double) -> String {
  entry.fen ?? basicMateSetup(entry.setup ?? .queen, rand)
}

/* ── how a round ends ── */

public enum EndgameOutcome: Equatable, Sendable {
  /// The goal met. `mission` when the mission was met too.
  case success(text: String, mission: Bool)
  case failure(text: String)
}

/// Where a round stands after a move, or nil while it goes on. `yourMoves`
/// counts the moves you have played; `promoted` is whether a move of yours queened.
public func endgameOutcome(
  _ entry: EndgameEntry, _ fen: String, you: Color, yourMoves: Int, promoted: Bool, stillWon: Bool
) -> EndgameOutcome? {
  let status = positionStatus(fen)
  if status.checkmate {
    if fenTurn(fen) == you { return .failure(text: "Checkmated") }
    if case .mateIn(let n) = entry.mission { return .success(text: "Checkmate", mission: yourMoves <= n) }
    return .success(text: "Checkmate", mission: true)
  }
  if status.draw {
    if entry.goal == .hold { return .success(text: "Draw held", mission: true) }
    return .failure(text: status.stalemate ? "Stalemate" : "Drawn")
  }
  switch entry.mission {
  case .queenPawn:
    if promoted && stillWon { return .success(text: "Queened", mission: true) }
  case .holdFor(let n):
    if yourMoves >= n { return .success(text: "Draw held", mission: true) }
  case .mateIn:
    // Past the fifty-move rule's worth of moves, the win is gone.
    if yourMoves >= 50 { return .failure(text: "Out of moves") }
  }
  return nil
}
