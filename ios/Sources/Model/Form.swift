import Foundation
import Shared

/// Form: how you are doing in an opening right now, from its last few prep
/// answers, shown as signal bars. Endgames families have the same from their
/// last few rounds.

/// The answers an opening's form reads.
public let FORM_ANSWERS = 10
/// Fewer answers than this, and an opening has no form yet.
public let FORM_MIN_ANSWERS = 5
/// The rounds an Endgames family's form reads, and the fewest it needs.
public let FORM_ROUNDS = 5
public let FORM_MIN_ROUNDS = 3

/// What one prep answer is worth to form: right and quick 1, right in 3 to 8 seconds 0.8,
/// right but slower 0.5, a miss 0.
public func formScore(correct: Bool, seconds: Double?) -> Double {
  guard correct else { return 0 }
  guard let seconds else { return 1 }
  return seconds < 3 ? 1 : seconds < 8 ? 0.8 : 0.5
}

/// Signal bars, 1 to 3, from the average of recent scores; nil without enough of them.
public func formBars(_ scores: [Double], least: Int = FORM_MIN_ANSWERS) -> Int? {
  guard scores.count >= least, !scores.isEmpty else { return nil }
  let average = scores.reduce(0, +) / Double(scores.count)
  return average >= 0.8 ? 3 : average >= 0.5 ? 2 : 1
}

/// Each opening's last answers, newest last.
public struct FormRecord: Equatable, Sendable, Codable {
  public var openings: [String: [Double]] = [:]
  public init() {}

  /// An answer counts for the opening its position is in and every one above it.
  public mutating func add(_ tree: OpeningTree, _ result: MoveResult) {
    let score = formScore(correct: result.correct, seconds: result.seconds)
    for id in creditedNodes(tree, result.line) {
      openings[id] = Array(((openings[id] ?? []) + [score]).suffix(FORM_ANSWERS))
    }
  }

  /// An opening's bars, or nil before it has enough answers.
  public func bars(_ id: String) -> Int? { formBars(openings[id] ?? []) }
}

/// An Endgames family's bars from its last rounds: goals met out of them.
public func endgameFormBars(_ results: [Bool]) -> Int? {
  formBars(results.suffix(FORM_ROUNDS).map { $0 ? 1 : 0 }, least: FORM_MIN_ROUNDS)
}
