import Book
import ChessCore

/// A stand-in game archive for the import flow.
/// Walked from the book with a fixed seed. Everything here is synthetic, and
/// opponent names are deliberately generic.

private let OPPONENTS = [
  "kn1ghtrider", "pawnstorm88", "Bishop_Takes", "rookandroll", "endgame_enjoyer",
  "zugzwangie", "TheQueensGambit", "fianchetto_fan", "blunder_buss", "TempoLoss",
  "PassedPawnPete", "perpetual_check", "OpenFile", "luft_or_bust", "Prophylaxis",
  "timescramble", "ZwischenZug", "flagfall", "DoubledPawns", "MinorPiece",
]

private let TIME_CONTROLS = ["180+0", "300+0", "300+3", "600+0", "600+5", "900+10"]

/// Moves this fictional player reaches for, with a multiplier on their weight.
private let PLAYER_BIAS: [String: Double] = [
  // As White: a committed 1.e4 player who mostly plays the Open Sicilian.
  "e4": 14, "Nf3": 0.5, "c4": 0.4, "d4": 0.6,
  "Bb5": 0.8, "Be3": 3, "Bg5": 1.4, "Bc4": 0.6,
  // As Black: Najdorf against 1.e4, Nimzo/QID against 1.d4.
  "c5": 10, "a6": 8, "Nf6": 3, "e6": 2.5, "Bb4": 6, "d6": 4,
  // Moves this player drifts into despite their prep.
  "Nc6": 1.4, "g6": 1.2, "e5": 2,
]

public func generateSampleArchive(
  _ index: ReferenceIndex, username: String, count: Int = 60, seed: UInt32 = 20240611,
  source: ImportedGame.Source = .lichess, whiteShare: Double = 0.5
) -> [ImportedGame] {
  let rand = mulberry32(seed)
  var games: [ImportedGame] = []
  for i in 0..<count {
    let userIsWhite = rand() < whiteShare
    let userColor: Color = userIsWhite ? .w : .b
    var moves: [String] = []
    var fen = START_FEN
    let maxPlies = 12 + Int(rand() * 12)
    while moves.count < maxPlies {
      guard let entry = lookup(index, fen), !entry.moves.isEmpty else { break }
      let isUserMove = fenTurn(fen) == userColor
      var choices: [(san: String, weight: Double)] = []
      for row in entry.moves {
        guard let move = applySan(fen, row.san) else { continue }
        let bias = isUserMove ? PLAYER_BIAS[row.san] ?? 1 : 1
        choices.append((move.san, max(0.01, row.games * bias)))
      }
      guard var picked = choices.last else { break }
      var roll = rand() * choices.reduce(0) { $0 + $1.weight }
      for c in choices {
        roll -= c.weight
        if roll <= 0 {
          picked = c
          break
        }
      }
      let move = applySan(fen, picked.san)!
      moves.append(move.san)
      fen = move.after
    }
    let opponent = OPPONENTS[Int(rand() * Double(OPPONENTS.count))]
    let roll = rand()
    let userWon = roll < 0.47
    let drawn = roll >= 0.47 && roll < 0.58
    let result = drawn ? "1/2-1/2" : userWon == userIsWhite ? "1-0" : "0-1"
    let daysAgo = Int(Double(i) / Double(count) * 120) + Int(rand() * 3)
    games.append(ImportedGame(
      id: "sample_\(i)", source: source, white: userIsWhite ? username : opponent, black: userIsWhite ? opponent : username,
      result: result, userColor: userColor, timeControl: TIME_CONTROLS[Int(rand() * Double(TIME_CONTROLS.count))],
      date: utcDay(Env.now() - Double(daysAgo) * 86_400_000), moves: moves))
  }
  return newestFirst(games)
}

/// `games.sort((a, b) => (a.date < b.date ? 1 : -1))` as V8 runs it on a short array
/// (a run, then binary insertion), so equal dates keep the order the golden cases recorded.
private func newestFirst(_ input: [ImportedGame]) -> [ImportedGame] {
  var a = input
  let compare = { (x: ImportedGame, y: ImportedGame) -> Int in x.date! < y.date! ? 1 : -1 }
  guard a.count > 1 else { return a }
  var run = 2
  let descending = compare(a[1], a[0]) < 0
  while run < a.count, (compare(a[run], a[run - 1]) < 0) == descending { run += 1 }
  if descending { a[0..<run].reverse() }
  for start in run..<a.count {
    let pivot = a[start]
    var left = 0
    var right = start
    while left < right {
      let mid = left + (right - left) / 2
      if compare(pivot, a[mid]) < 0 { right = mid } else { left = mid + 1 }
    }
    a.remove(at: start)
    a.insert(pivot, at: left)
  }
  return a
}
