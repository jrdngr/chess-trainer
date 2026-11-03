import ChessCore

/// Endgame mode: a library of must-know endings, each played out against the
/// engine with one goal. Win: a known win to convert. Hold Draw: a known draw
/// to hold. Each position is a card on its own schedule, and each family of
/// endings has its own tier.

public enum EndgameGoal: String, Sendable, Codable {
  case win, hold
  /// "Win" or "Hold Draw".
  public var label: String { self == .win ? "Win" : "Hold Draw" }
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

/// The material a basic-mate setup is drawn with, beside the two kings.
public enum BasicMate: String, Sendable, Codable, CaseIterable {
  case queen, rook, bishops
}

/// How a library entry's positions are set up. Each round draws a fresh
/// position from its setup: the colors swapped at random, the board mirrored
/// left to right at random, and the result for you checked before you see it.
public enum EndgameSetup: Equatable, Sendable {
  case mate(BasicMate)
  /// A lone pawn racing their king. Win: run with it. Hold Draw: catch it.
  case square
  /// Your king near the key squares in front of your pawn. Hold Draw: keep their king off them.
  case keySquares
  /// The kings face each other in front of the pawn.
  case opposition
  case lucena
  case philidor
}

public struct EndgameFamily: Equatable, Sendable {
  public var id: String
  public var name: String
}

public struct EndgameEntry: Equatable, Sendable {
  public var id: String
  public var family: String
  public var name: String
  /// The one position to play, you to move; nil for a library entry, set up fresh each round.
  public var fen: String?
  public var setup: EndgameSetup?
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
    id: "mate-queen", family: "mates", name: "Queen mate", fen: nil, setup: .mate(.queen), goal: .win, mission: .mateIn(10),
    intro: QUEEN_MATE_CARD),
  EndgameEntry(
    id: "mate-rook", family: "mates", name: "Rook mate", fen: nil, setup: .mate(.rook), goal: .win, mission: .mateIn(16),
    intro: ROOK_MATE_CARD),
  EndgameEntry(
    id: "mate-bishops", family: "mates", name: "Two bishops", fen: nil, setup: .mate(.bishops), goal: .win, mission: .mateIn(19),
    intro: BISHOPS_MATE_CARD),
  EndgameEntry(
    id: "kp-key-squares", family: "pawn", name: "Key squares", fen: nil, setup: .keySquares, goal: .win,
    mission: .queenPawn,
    intro: KEY_SQUARES_WIN_CARD),
  EndgameEntry(
    id: "kp-key-squares-hold", family: "pawn", name: "Key squares", fen: nil, setup: .keySquares, goal: .hold,
    mission: .holdFor(15),
    intro: KEY_SQUARES_HOLD_CARD),
  EndgameEntry(
    id: "kp-opposition-win", family: "pawn", name: "Opposition", fen: nil, setup: .opposition, goal: .win,
    mission: .queenPawn,
    intro: OPPOSITION_WIN_CARD),
  EndgameEntry(
    id: "kp-opposition", family: "pawn", name: "Opposition", fen: nil, setup: .opposition, goal: .hold,
    mission: .holdFor(15),
    intro: OPPOSITION_HOLD_CARD),
  EndgameEntry(
    id: "kp-square", family: "pawn", name: "Square rule", fen: nil, setup: .square, goal: .win,
    mission: .queenPawn,
    intro: SQUARE_WIN_CARD),
  EndgameEntry(
    id: "kp-square-hold", family: "pawn", name: "Square rule", fen: nil, setup: .square, goal: .hold,
    mission: .holdFor(12),
    intro: SQUARE_HOLD_CARD),
  EndgameEntry(
    id: "rook-lucena", family: "rook", name: "Lucena", fen: nil, setup: .lucena, goal: .win,
    mission: .queenPawn,
    intro: LUCENA_CARD),
  EndgameEntry(
    id: "rook-philidor", family: "rook", name: "Philidor", fen: nil, setup: .philidor, goal: .hold,
    mission: .holdFor(20),
    intro: PHILIDOR_CARD),
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
  /// The position with fresh move counters, so the fifty-move count starts with the round.
  /// A win with a pawn of yours is to be queened; a win without one, mated.
  var entry: EndgameEntry {
    let you = fenTurn(fen)
    let pawn = piecesFromFen(fen).contains { $0.type == .p && $0.color == you }
    return EndgameEntry(
      id: id, family: "games", name: name, fen: "\(positionKey(fen)) 0 1", setup: nil, goal: goal,
      mission: goal == .hold ? .holdFor(15) : pawn ? .queenPawn : .mateIn(50), intro: nil)
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
    let placement = placementOf(cells)
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

/* ── fresh positions for each round ── */

/// A board as 64 cells, a1 first, holding FEN piece letters.
typealias Cells = [Character?]

private func placementOf(_ cells: Cells) -> String {
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
  return rows.joined(separator: "/")
}

private func fenOf(_ cells: Cells, _ turn: Color) -> String {
  "\(placementOf(cells)) \(turn == .w ? "w" : "b") - - 0 1"
}

private func cellsOf(_ fen: String) -> Cells {
  var cells = Cells(repeating: nil, count: 64)
  for piece in piecesFromFen(fen) {
    let (f, r) = coords(piece.square)
    let letter = Character(piece.type.rawValue)
    cells[r * 8 + f] = piece.color == .w ? Character(letter.uppercased()) : letter
  }
  return cells
}

/// The same board with the colors swapped (ranks turned round), mirrored left to right, or both.
private func turned(_ cells: Cells, swap: Bool, mirror: Bool) -> Cells {
  var out = Cells(repeating: nil, count: 64)
  for r in 0..<8 {
    for f in 0..<8 {
      guard let p = cells[r * 8 + f] else { continue }
      let piece = swap ? Character(p.isUppercase ? p.lowercased() : p.uppercased()) : p
      out[(swap ? 7 - r : r) * 8 + (mirror ? 7 - f : f)] = piece
    }
  }
  return out
}

/// The position as a start: kings apart, the side not to move not in check, the game not over.
private func legalStart(_ cells: Cells, _ turn: Color) -> String? {
  guard let wk = cells.firstIndex(of: Character("K")), let bk = cells.firstIndex(of: Character("k")),
    max(abs(wk % 8 - bk % 8), abs(wk / 8 - bk / 8)) >= 2
  else { return nil }
  let fen = fenOf(cells, turn)
  guard !positionStatus(fenOf(cells, turn.other)).check, !positionStatus(fen).gameOver else { return nil }
  return fen
}

private func dist(_ a: (Int, Int), _ b: (Int, Int)) -> Int { max(abs(a.0 - b.0), abs(a.1 - b.1)) }

/// A position drawn from a setup, White the side with the pawn and pawns moving up the board.
/// `attacking` is whether you play that side; you are to move.
private func candidate(_ setup: EndgameSetup, attacking: Bool, _ rand: @escaping () -> Double) -> Cells? {
  func pick(_ range: ClosedRange<Int>) -> Int { range.lowerBound + min(range.count - 1, Int(rand() * Double(range.count))) }
  var cells = Cells(repeating: nil, count: 64)
  func put(_ piece: Character, _ at: (Int, Int)) -> Bool {
    guard (0...7).contains(at.0), (0...7).contains(at.1), cells[at.1 * 8 + at.0] == nil else { return false }
    cells[at.1 * 8 + at.0] = piece
    return true
  }
  switch setup {
  case .mate:
    return nil
  case .square:
    let pawn = (pick(0...7), pick(2...4))
    let steps = 7 - pawn.1
    let them = (pick(0...7), pick(0...7))
    let d = dist(them, (pawn.0, 7))
    // Runner to move: their king just outside the pawn's square. Chaser to move: just inside it.
    guard attacking ? (d == steps + 1 || d == steps + 2) : (d == steps || d == steps + 1) else { return nil }
    // Your king too far off to help, and not in the pawn's way.
    let king = (pick(0...7), pick(0...7))
    guard dist(king, pawn) >= 4, king.0 != pawn.0 || king.1 < pawn.1 else { return nil }
    guard put("P", pawn), put("k", them), put("K", king) else { return nil }
  case .keySquares:
    let pawn = (pick(1...6), pick(1...3))
    let keys = (pawn.0 - 1...pawn.0 + 1).map { ($0, pawn.1 + 2) }
    // The pawn's king beside it, a step or two from the key squares but not on one.
    let king = (pick(0...7), pick(0...7))
    let toKey = keys.map { dist(king, $0) }.min()!
    guard (1...2).contains(toKey), dist(king, pawn) <= 2 else { return nil }
    let them = (pick(0...7), pick(pawn.1 + 1...7))
    guard dist(them, pawn) <= 4 else { return nil }
    guard put("P", pawn), put("K", king), put("k", them) else { return nil }
  case .opposition:
    let pawn = (pick(1...6), pick(1...3))
    // The pawn's king just ahead of it, their king two or three ranks beyond, near its file.
    let king = (pawn.0 + pick(-1...1), pawn.1 + 1)
    let them = (king.0 + pick(-1...1), king.1 + pick(2...3))
    guard put("P", pawn), put("K", king), put("k", them) else { return nil }
  case .lucena:
    let pawn = (pick(1...6), 6)
    let side = rand() < 0.5 ? -1 : 1
    // Their king cut off two or three files away, the cutting rook between.
    let them = (pawn.0 + side * pick(2...3), pick(4...7))
    let rook = (pawn.0 + side * pick(1...(abs(them.0 - pawn.0) - 1)), pick(0...4))
    // Their rook on the other side of the pawn, ready to check.
    let theirRook = (pick(0...7), pick(0...3))
    guard (theirRook.0 - pawn.0) * side < 0 else { return nil }
    guard put("P", pawn), put("K", (pawn.0, 7)), put("k", them), put("R", rook), put("r", theirRook) else { return nil }
  case .philidor:
    let pawn = (pick(1...6), pick(2...4))
    let king = (pawn.0 + pick(-2...2), pick(max(0, pawn.1 - 1)...4))
    // Their king in front of the pawn, their rook holding the sixth.
    let them = (pawn.0 + pick(-1...1), pick(6...7))
    let theirRook = (pick(0...7), 5)
    let rook = (pick(0...7), pick(0...4))
    guard put("P", pawn), put("K", king), put("k", them), put("r", theirRook), put("R", rook) else { return nil }
  }
  return cells
}

/// The setup's textbook position, for when no fresh one turns up.
private func fallback(_ setup: EndgameSetup, _ goal: EndgameGoal) -> String {
  switch setup {
  case .mate(let kind): basicMateSetup(kind, { 0.5 })
  case .square: goal == .win ? "8/8/8/8/P7/8/8/5k1K w - - 0 1" : "8/8/8/8/P2k4/8/8/7K b - - 0 1"
  case .keySquares, .opposition: "8/8/4k3/8/8/4K3/4P3/8 \(goal == .win ? "w" : "b") - - 0 1"
  case .lucena: "3K4/3P1k2/8/8/8/8/2r5/4R3 w - - 0 1"
  case .philidor: "8/8/8/8/4pk2/R7/1r6/4K3 w - - 0 1"
  }
}

/// The position a round of this entry starts from, you to move: a saved one
/// as it was, a library one fresh from its setup. `result` gives the result
/// with best play for a side where it is known (the tablebases); a fresh
/// position is kept only when it gives you the entry's goal.
public func endgameStart(
  _ entry: EndgameEntry, _ rand: @escaping () -> Double, result: (String, Color) -> EndResult?
) -> String {
  if let fen = entry.fen { return fen }
  let setup = entry.setup ?? .mate(.queen)
  let swap = rand() < 0.5, mirror = rand() < 0.5
  if case .mate(let kind) = setup {
    let fen = basicMateSetup(kind, rand)
    return swap ? fenOf(turned(cellsOf(fen), swap: true, mirror: false), .b) : fen
  }
  let attacking = entry.goal == .win
  // In the setup's frame White has the pawn; you are White when you attack.
  let you: Color = attacking != swap ? .w : .b
  for _ in 0..<3000 {
    guard let cells = candidate(setup, attacking: attacking, rand),
      let fen = legalStart(turned(cells, swap: swap, mirror: mirror), you)
    else { continue }
    switch setup {
    case .lucena, .philidor:
      guard let known = knownEnding(fen), known.name == (setup == .lucena ? "Lucena" : "Philidor"),
        known.result(for: you) == (attacking ? .win : .draw)
      else { continue }
    default:
      guard result(fen, you) == (attacking ? .win : .draw) else { continue }
    }
    return fen
  }
  return fallback(setup, entry.goal)
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
