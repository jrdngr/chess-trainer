import ChessCore

/// Freshness: what the last few rounds were about, so the next one is not.
/// `src/model/freshness.ts`.

/// Rounds until a position seen counts as not seen.
public let HORIZON = 3

/// How much of a line's freshness its head carries, against its tail.
public let HEAD_WEIGHT = 0.5

/// What the rounds so far have been about: position key → the round that last saw it.
public struct Seen: Equatable, Sendable {
  public var at: [String: Int]
  /// The number of the last round played.
  public var round: Int
  public init(at: [String: Int], round: Int) {
    self.at = at
    self.round = round
  }
}

public let NOTHING_SEEN = Seen(at: [:], round: 0)

/// How long ago a position was last seen, 0 (this round) to 1 (the horizon or never).
public func staleness(_ seen: Seen, _ key: String) -> Double {
  guard let last = seen.at[key] else { return 1 }
  return max(0, min(1, Double(seen.round - last) / Double(HORIZON)))
}

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

/// A line's positions, split where it last parts from the rest of the prep.
public func lineParts(_ rep: Repertoire, _ tipId: String) -> (head: [String], tail: [String]) {
  let path = pathTo(rep, tipId)
  var split = 0
  for (i, node) in path.enumerated() where childrenOf(rep, node.parentId).count > 1 { split = i }
  let key = { (n: RepMove) in positionKey(n.fenAfter) }
  return (path[..<split].map(key), path[split...].map(key))
}

private func mean(_ values: [Double]) -> Double {
  values.isEmpty ? 1 : values.reduce(0, +) / Double(values.count)
}

/// How long a line has been left, 0...1: its tail's, tempered by its head's.
public func lineStaleness(_ seen: Seen, _ rep: Repertoire, _ tipId: String) -> Double {
  let (head, tail) = lineParts(rep, tipId)
  let tailStale = mean(tail.map { staleness(seen, $0) })
  let headStale = mean(head.map { staleness(seen, $0) })
  return tailStale * (1 - HEAD_WEIGHT + HEAD_WEIGHT * headStale)
}

/// True when the line's own moves were what the round being decided came after.
public func justRun(_ seen: Seen, _ rep: Repertoire, _ tipId: String) -> Bool {
  let tail = lineParts(rep, tipId).tail
  return !tail.isEmpty && tail.allSatisfy { seen.at[$0] == seen.round }
}
