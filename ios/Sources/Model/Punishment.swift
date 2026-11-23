import ChessCore

/// Before endgame rules, a costly move ends a run only when the engine's own line after it shows why:
/// it leaves you material down against the engine's best move, or you are mated. That line is played out on
/// the finished run's board.

/// By how many of your own moves after a blunder its line has to leave you behind.
public let PUNISH_MOVES = 3
/// At which of your own moves after a blunder you must still be behind.
public let PUNISH_HOLD_MOVES = 5
/// The least material, in pawns, you have to be behind.
public let PUNISH_PAWNS = 1

/// The line that shows why your move is a blunder, as UCI moves after it; nil when the engine's line shows no reason.
/// `yours` is the engine's line with your move first, `best` its line with its own move first, both from `fen`, where
/// `color` is to move. Material is counted after each move with any trade on that move's square finished
/// (`settledBalance`). A reason is being `PUNISH_PAWNS` or more behind the best line by your `PUNISH_MOVES`th move
/// after this one, and still that far behind it at your `PUNISH_HOLD_MOVES`th (each at the line's end, if sooner).
/// The line then runs up to the move that leaves you behind, and on through the trade on its square, if any. `mated` is how many moves from `fen` the line mates you
/// in, if it does; within `PUNISH_MOVES` + 1 that is a reason too, and the whole line is played.
public func punishment(_ fen: String, _ color: Color, yours: [String], best: [String], mated: Int?) -> [String]? {
  let line = walkSettled(fen, yours, color), top = walkSettled(fen, best, color)
  guard !line.balance.isEmpty else { return nil }
  if let mated, mated <= PUNISH_MOVES + 1 {
    return Array(line.moves.dropFirst())
  }
  guard line.moves.count > 1 else { return nil }
  let start = balance(fen, color)
  /// Your material after your `n`th move after this one in a line, or at the line's end when it ends sooner.
  func after(_ balance: [Int], _ n: Int) -> Int { balance.isEmpty ? start : balance[min(2 * n, balance.count - 1)] }
  let held = after(top.balance, PUNISH_HOLD_MOVES) - after(line.balance, PUNISH_HOLD_MOVES)
  guard held >= PUNISH_PAWNS else { return nil }
  for n in 0...PUNISH_MOVES where after(top.balance, n) - after(line.balance, n) >= PUNISH_PAWNS {
    // Played up to the move that left you this far behind.
    let i = min(2 * n, line.balance.count - 1)
    var j = i
    while j > 1 && line.balance[j - 1] == line.balance[i] { j -= 1 }
    // The trade counted on that move's square is played out too, so the line shows the material taken.
    let end = max(j, 1)
    return Array(line.moves[1...end]) + tradeLine(line.fens[end + 1], on: line.landed[end])
  }
  return nil
}

/// Your material less the other side's, in pawns.
private func balance(_ fen: String, _ color: Color) -> Int {
  let lead = material(fen).lead
  return color == .w ? lead : -lead
}

/// What the side to move wins by finishing the trade on `square`: each side takes back only while that gains.
func exchangeGain(_ fen: String, on square: String) -> Int {
  var best = 0
  for move in legalMoves(fen) where move.to == square {
    guard let captured = move.captured else { continue }
    let won = PIECE_VALUES[captured]! + (move.promotion.map { PIECE_VALUES[$0]! - 1 } ?? 0)
    best = max(best, won - exchangeGain(move.after, on: square))
  }
  return best
}

/// The trade on `square` as `exchangeGain` counts it, as UCI moves: each side takes back only while that gains.
func tradeLine(_ fen: String, on square: String) -> [String] {
  var best: (gain: Int, move: LegalMove)?
  for move in legalMoves(fen) where move.to == square {
    guard let captured = move.captured else { continue }
    let won = PIECE_VALUES[captured]! + (move.promotion.map { PIECE_VALUES[$0]! - 1 } ?? 0)
    let gain = won - exchangeGain(move.after, on: square)
    if gain > (best?.gain ?? 0) { best = (gain, move) }
  }
  guard let best else { return [] }
  return [best.move.uci] + tradeLine(best.move.after, on: square)
}

/// Your material balance in `fen` once the trade on `square`, where the last move landed, is finished.
public func settledBalance(_ fen: String, on square: String, _ color: Color) -> Int {
  let gain = exchangeGain(fen, on: square)
  return balance(fen, color) + (fenTurn(fen) == color ? gain : -gain)
}

/// A UCI line from `fen`, kept while its moves are legal, with your settled material balance after each of them,
/// the positions along it (`fen` first) and the square each move landed on.
private func walkSettled(_ fen: String, _ uci: [String], _ color: Color) -> (
  moves: [String], balance: [Int], fens: [String], landed: [String]
) {
  var at = fen
  var moves: [String] = [], balances: [Int] = [], fens = [fen], landed: [String] = []
  for u in uci {
    guard let move = applyUci(at, u) else { break }
    at = move.after
    moves.append(u)
    fens.append(at)
    landed.append(move.to)
    balances.append(settledBalance(at, on: move.to, color))
  }
  return (moves, balances, fens, landed)
}
