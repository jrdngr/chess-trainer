import ChessCore

/// Before endgame rules, a costly move ends a run only when the engine's own line after it shows why:
/// you lose material soon, or you are mated. That line is played out on the finished run's board.

/// How many of your own moves after a blunder its line has to cost you material.
public let PUNISH_MOVES = 3
/// The least material, in pawns, the line has to cost you.
public let PUNISH_PAWNS = 1

/// The line that shows why your move is a blunder, as UCI moves after it; nil when the engine's line shows no reason.
/// `yours` is the engine's line with your move first, `best` its line with its own move first, both from `fen`, where
/// `color` is to move. A reason is a pawn or more lost by your `PUNISH_MOVES`th move after this one (or the line's
/// end, if sooner), against the position now and against the best line at the same point, and still lost where the
/// line ends. The line then runs up to the move that leaves you down that much. `mated` is how many moves from `fen` the line mates you in, if it
/// does; within `PUNISH_MOVES` + 1 that is a reason too, and the whole line is played.
public func punishment(_ fen: String, _ color: Color, yours: [String], best: [String], mated: Int?) -> [String]? {
  let line = walkUci(fen, yours, color), top = walkUci(fen, best, color)
  guard !line.balance.isEmpty else { return nil }
  if let mated, mated <= PUNISH_MOVES + 1 {
    return Array(line.moves.dropFirst())
  }
  guard line.moves.count > 1 else { return nil }
  let start = balance(fen, color)
  /// Where your `n`th move after this one leaves the line, or the line's last move when it ends sooner.
  func yourMove(_ count: Int, _ n: Int) -> Int { min(2 * n, count - 1) }
  let end = line.balance.count - 1
  for n in 0...PUNISH_MOVES {
    let i = yourMove(line.balance.count, n)
    let behind = top.balance.isEmpty ? start : top.balance[yourMove(top.balance.count, n)]
    let lost = start - line.balance[i]
    guard lost >= PUNISH_PAWNS, behind - line.balance[i] >= PUNISH_PAWNS, start - line.balance[end] >= lost else { continue }
    // Played up to the move that left you this far down.
    var j = i
    while j > 1 && line.balance[j - 1] == line.balance[i] { j -= 1 }
    return Array(line.moves[1...max(j, 1)])
  }
  return nil
}

/// Your material less the other side's, in pawns.
private func balance(_ fen: String, _ color: Color) -> Int {
  let lead = material(fen).lead
  return color == .w ? lead : -lead
}

/// A UCI line from `fen`, kept while its moves are legal, with your material balance after each of them.
private func walkUci(_ fen: String, _ uci: [String], _ color: Color) -> (moves: [String], balance: [Int]) {
  var at = fen
  var moves: [String] = [], balances: [Int] = []
  for u in uci {
    guard let move = applyUci(at, u) else { break }
    at = move.after
    moves.append(u)
    balances.append(balance(at, color))
  }
  return (moves, balances)
}
