import ChessCore
import Shared

/// How much a move moves the eval bar, from the side playing it. `src/model/evalDelta.ts`.

/// A mate, as a score.
private let MATE: Double = 10_000

/// One engine score as centipawns from White's side, mates folded in.
public func whiteCp(cp: Double?, mate: Double?) -> Double? {
  if let mate { return mate > 0 ? MATE - mate : -MATE - mate }
  return cp
}

/// The change a move makes to the position's eval, from the mover's side.
public func deltaFor(_ color: Color, _ position: Double, _ afterMove: Double) -> Double {
  let change = afterMove - position
  return color == .w ? change : -change
}

/// Below this the change is noise between two searches.
public let EVEN_CP: Double = 10

/// "+0.3", "−1.2", "0.0": pawns, capped where the number stops meaning anything.
public func formatDelta(_ cp: Double) -> String {
  if abs(cp) < EVEN_CP { return "0.0" }
  let pawns = min(abs(cp) / 100, 9.9)
  return (cp > 0 ? "+" : "\u{2212}") + JS.toFixed(pawns, 1)
}

public enum DeltaTone: String, Sendable {
  case good, bad, even
}

public func deltaTone(_ cp: Double) -> DeltaTone {
  if abs(cp) < EVEN_CP { return .even }
  return cp > 0 ? .good : .bad
}

/// A delta as the list shows it, so two answers that read the same tie.
private func shownCp(_ cp: Double) -> Double {
  abs(cp) < EVEN_CP ? 0 : (cp > 0 ? 1 : -1) * JS.round(min(abs(cp), 990) / 10)
}

private typealias Weighed = (at: Int, cp: Double?, share: Double)

private func engineOrder(_ a: Weighed, _ b: Weighed) -> Double {
  if a.cp == nil || b.cp == nil { return a.cp == nil ? (b.cp == nil ? Double(a.at - b.at) : 1) : -1 }
  let shown = shownCp(b.cp!) - shownCp(a.cp!)
  if shown != 0 { return shown }
  let share = b.share - a.share
  return share != 0 ? share : Double(a.at - b.at)
}

/// Moves in the engine's order: best delta first, unweighed moves last in the order they came.
public func byDelta<T>(_ moves: [T], san: (T) -> String, share: (T) -> Double?, _ deltaOf: (String) -> Double?) -> [T] {
  let weighed = moves.enumerated().map { (move: $0.element, w: Weighed($0.offset, deltaOf(san($0.element)), share($0.element) ?? 0)) }
  return weighed.jsSorted { engineOrder($0.w, $1.w) }.map(\.move)
}

/// Moves in strong players' order: most played first, the engine between equals.
public func byShare<T>(_ moves: [T], san: (T) -> String, share: (T) -> Double?, _ deltaOf: (String) -> Double?) -> [T] {
  let weighed = moves.enumerated().map { (move: $0.element, w: Weighed($0.offset, deltaOf(san($0.element)), share($0.element) ?? 0)) }
  return weighed.jsSorted { a, b in
    let s = b.w.share - a.w.share
    return s != 0 ? s : engineOrder(a.w, b.w)
  }.map(\.move)
}
