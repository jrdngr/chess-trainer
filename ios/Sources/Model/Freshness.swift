import ChessCore

/// Freshness: what the last few rounds were about. The part of
/// `src/model/freshness.ts` the record needs; the rest comes with the run.

/// Rounds until a position seen counts as not seen.
public let HORIZON = 3

/// The positions a line reaches, one per move, the start left out.
public func keysAlong(_ sans: [String]) -> [String] {
  var keys: [String] = []
  var fen = START_FEN
  for san in sans {
    guard let move = applySan(fen, san) else { break }
    fen = move.after
    keys.append(positionKey(fen))
  }
  return keys
}

/// Stamp every position along a line with the round that saw it.
public func markSeen(_ at: [String: Int], _ sans: [String], _ round: Int) -> [String: Int] {
  var out = at
  for key in keysAlong(sans) { out[key] = round }
  return out
}
