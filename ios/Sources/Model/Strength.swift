import Foundation

/* Your playing strength, as the judge sees it: a rating estimated from what
 * your moves cost once you're past your prep. The opponent in Autopilot plays
 * at it, and Survival can too. It's kept apart from the openings' ratings,
 * which measure how well you know your prep. */

/// The estimate and how many moves it rests on.
public struct PlayerStrength: Equatable, Sendable, Codable {
  public var rating: Double
  public var moves: Int
  public init(rating: Double = Double(STARTING_STRENGTH), moves: Int = 0) {
    self.rating = rating
    self.moves = moves
  }
}

public let STARTING_STRENGTH = 1200

/// What a move costs a player of each rating on average, in centipawns:
/// rating and expected loss.
private let EXPECTED_LOSS: [(rating: Double, loss: Double)] = [
  (600, 110), (800, 95), (1200, 70), (1600, 50), (2000, 35), (2200, 28),
]

/// Losses past this count as this: one blunder says less than its size.
public let STRENGTH_LOSS_CAP: Double = 300
/// Rating points per centipawn a move beats or misses the expected loss.
/// Small enough that the estimate follows your last few dozen moves.
public let STRENGTH_STEP = 0.3
/// The most one move can move the estimate.
public let STRENGTH_MAX_CHANGE: Double = 40

/// What a move costs a player of this rating on average.
public func expectedLoss(_ rating: Double) -> Double {
  let points = EXPECTED_LOSS
  if rating <= points.first!.rating { return points.first!.loss }
  if rating >= points.last!.rating { return points.last!.loss }
  let upper = points.firstIndex { $0.rating >= rating }!
  let a = points[upper - 1], b = points[upper]
  return a.loss + (rating - a.rating) / (b.rating - a.rating) * (b.loss - a.loss)
}

/// The estimate after one judged move that cost `lost` centipawns.
public func updatedStrength(_ s: PlayerStrength, lost: Double) -> PlayerStrength {
  let change = STRENGTH_STEP * (expectedLoss(s.rating) - min(max(lost, 0), STRENGTH_LOSS_CAP))
  let rating = s.rating + max(-STRENGTH_MAX_CHANGE, min(STRENGTH_MAX_CHANGE, change))
  return PlayerStrength(rating: max(Double(MIN_RATING), min(Double(MAX_RATING), rating)), moves: s.moves + 1)
}

/// The level that plays like you.
public func levelMatching(_ s: PlayerStrength) -> Level {
  // Rounded to 50, so the level reads as a plain number.
  levelFor(rating: Int((s.rating / 50).rounded()) * 50)
}

extension AppState {
  /// A move the judge weighed: the estimate follows it.
  public mutating func judgedMove(lost: Double) {
    strength = updatedStrength(strength, lost: lost)
  }
}
