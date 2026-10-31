import ChessCore

/// Growth's arrows at a hole: who recommends each one. `src/model/answerArrows.ts`.
///
/// Blue is the reply strong players choose most. The other two are the
/// engine's best, purple and then a lighter purple. When strong players and the
/// engine agree, the move stays blue and the engine's next move takes its
/// place. Past the book nobody has a share, and all three are the engine's.

public enum AnswerRole: String, Sendable {
  case strong, engine
  case engineNext = "engine-next"
}

public struct RoleArrow: Equatable, Sendable {
  public var san: String
  public var from: String
  public var to: String
  public var role: AnswerRole
}

/// An answer on offer, with its share of games when the book has one.
public struct ListedAnswer: Equatable, Sendable {
  public var san: String
  public var share: Double?
  public init(san: String, share: Double? = nil) {
    self.san = san
    self.share = share
  }
}

/// How many arrows the roles fill, at most.
public let ROLE_ARROWS = 3

/// `listed` is every answer on offer, `deltaOf` what the engine makes of each
/// so far (nil until it has weighed it). Before the engine has weighed any,
/// only the blue arrow is drawn; past the book, `listed`'s order stands in.
public func roleArrows(_ fen: String, _ listed: [ListedAnswer], _ deltaOf: (String) -> Double?) -> [RoleArrow] {
  let strong = listed.reduce(nil as ListedAnswer?) { best, move in (move.share ?? 0) > (best?.share ?? 0) ? move : best }
  let weighed = listed.filter { deltaOf($0.san) != nil }
  let ordered = !weighed.isEmpty ? byDelta(weighed, san: \.san, share: \.share, deltaOf) : strong != nil ? [] : listed
  let engine = ordered.filter { $0.san != strong?.san }.prefix(ROLE_ARROWS - (strong != nil ? 1 : 0))

  var out: [RoleArrow] = []
  func add(_ san: String, _ role: AnswerRole) {
    if let move = applySan(fen, san) { out.append(RoleArrow(san: san, from: move.from, to: move.to, role: role)) }
  }
  if let strong { add(strong.san, .strong) }
  for (i, move) in engine.enumerated() { add(move.san, i == 0 ? .engine : .engineNext) }
  return out
}
