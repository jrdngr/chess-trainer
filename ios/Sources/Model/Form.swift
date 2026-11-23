import ChessCore
import Foundation
import Shared

/// Form: how you are doing in an opening right now, from its last few prep
/// answers, 0 to 1, shown as a ring that fills from red to green. Endgames
/// families have the same from their last few rounds.

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

/// Form, 0 to 1: the average of recent scores; nil without enough of them.
public func formOf(_ scores: [Double], least: Int = FORM_MIN_ANSWERS) -> Double? {
  guard scores.count >= least, !scores.isEmpty else { return nil }
  return scores.reduce(0, +) / Double(scores.count)
}

/// Each opening's last answers, newest last, apart for each side: White's
/// 1.e4 e5 is a different job from Black's.
public struct FormRecord: Equatable, Sendable, Codable {
  public var openings: [String: [Double]] = [:]
  public var black: [String: [Double]] = [:]
  public init() {}

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    openings = try c.decodeIfPresent([String: [Double]].self, forKey: .openings) ?? [:]
    black = try c.decodeIfPresent([String: [Double]].self, forKey: .black) ?? [:]
  }

  /// One side's answers by opening.
  public subscript(_ color: Color) -> [String: [Double]] {
    get { color == .w ? openings : black }
    set { if color == .w { openings = newValue } else { black = newValue } }
  }

  /// An opening's last answers on one side.
  public func scores(_ id: String, _ color: Color) -> [Double] { self[color][id] ?? [] }

  /// An answer counts for the opening its position is in and every one above it, on its side.
  public mutating func add(_ tree: OpeningTree, _ result: MoveResult) {
    let score = formScore(correct: result.correct, seconds: result.seconds)
    for id in creditedNodes(tree, result.line) {
      self[result.color][id] = Array((scores(id, result.color) + [score]).suffix(FORM_ANSWERS))
    }
  }

  /// An opening's form on one side, or nil before it has enough answers.
  public func value(_ id: String, _ color: Color) -> Double? { formOf(scores(id, color)) }

  /// The sum of every answer: changes whenever form does.
  public var stamp: Double { (Array(openings.values) + Array(black.values)).reduce(0) { $0 + $1.reduce(0, +) } }
}

/// What the Playbook shows at each position: the last answers to your move there, by side,
/// from each prep answer and miss as it is logged. An answer counts for the position it
/// was asked at and the position the prepared move reaches, so an opening shows the answers
/// to your move there however its name falls. Kept in the save, apart from the capped event log.
public struct FormAtMove: Equatable, Sendable, Codable {
  public var white: [String: [Double]] = [:]
  public var black: [String: [Double]] = [:]

  public init() {}

  /// Built from a log, for a save from before the record was kept.
  public init(_ events: [AppEvent]) {
    for event in events { add(event) }
  }

  /// A logged prep answer or miss, counted; any other event changes nothing.
  public mutating func add(_ event: AppEvent) {
    guard let color = event.color, let fen = event.fen else { return }
    let score: Double
    let move: String?
    switch event.kind {
    case "prep-answer":
      score = event.text.flatMap(Grade.init(rawValue:)).map { formScore($0) } ?? 1
      move = event.san
    case "prep-miss":
      score = 0
      move = event.best
    default: return
    }
    var keys = [positionKey(fen)]
    if let move, let after = applySan(fen, move) { keys.append(positionKey(after.after)) }
    for key in Set(keys) {
      if color == .w {
        white[key] = Array((white[key, default: []] + [score]).suffix(FORM_ANSWERS))
      } else {
        black[key] = Array((black[key, default: []] + [score]).suffix(FORM_ANSWERS))
      }
    }
  }

  /// The sum of every answer and their count: changes whenever an answer is added.
  public var stamp: String {
    let all = Array(white.values) + Array(black.values)
    return "\(all.reduce(0) { $0 + $1.count }):\(all.reduce(0) { $0 + $1.reduce(0, +) })"
  }

  /// The last answers to your move at a position, oldest first.
  public func scores(_ key: String, _ color: Color) -> [Double] { (color == .w ? white : black)[key] ?? [] }
  public func value(_ key: String, _ color: Color) -> Double? { formOf(scores(key, color)) }
}

/// A prep answer's grade as an answer score: quick 1, 3 to 8 seconds 0.8, slower 0.5.
private func formScore(_ grade: Grade) -> Double {
  switch grade {
  case .easy: 1
  case .good: 0.8
  case .hard: 0.5
  case .again: 0
  }
}

/// An Endgames family's form from its last rounds: the share of them with the goal met.
public func endgameForm(_ results: [Bool]) -> Double? {
  formOf(results.suffix(FORM_ROUNDS).map { $0 ? 1 : 0 }, least: FORM_MIN_ROUNDS)
}

extension AppState {
  /// The side an opening's form is shown for where no side is given: the one
  /// whose Playbook holds it, else the side whose move names it.
  public func formSide(_ node: OpeningNode) -> Color {
    let holding = playbookList.filter { nodeAtLine($0, node.sans) != nil }.map(\.color)
    return holding.count == 1 ? holding[0] : playerOf(node.sans)
  }

  /// An opening's form on the side it is shown for.
  public func formValue(_ node: OpeningNode) -> Double? { form.value(node.id, formSide(node)) }
}
