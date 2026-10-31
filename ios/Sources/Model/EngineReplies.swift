import ChessCore
import Foundation

/// What the engine would play where the book knows nothing, as worked out so
/// far. `src/model/engineReplies.ts`: the model reads it synchronously and
/// the screens fill it in as the engine answers.

/// How many moves the engine is asked for past the book.
public let ENGINE_REPLIES = 4
/// How many of them the opponent is prepared for.
public let ENGINE_THEIR_REPLIES = 2
/// How close to the best a move of yours must be to be offered past the book.
public let NEAR_BEST: Double = 20

private final class Known: @unchecked Sendable {
  let lock = NSLock()
  var replies: [String: [String]] = [:]
  var losses: [String: [String: Double]] = [:]
}

private let known = Known()

/// The engine's moves here, best first; nil when it has not been asked yet.
public func engineReplies(_ fen: String) -> [String]? {
  known.lock.withLock { known.replies[positionKey(fen)] }
}

/// What a remembered move gives away against the engine's best.
public func engineLoss(_ fen: String, _ san: String) -> Double? {
  known.lock.withLock { known.losses[positionKey(fen)]?[san] }
}

/// Record the engine's moves for a position, best first.
public func rememberEngineReplies(_ fen: String, _ sans: [String], _ lost: [Double]? = nil) {
  let kept = Array(sans.prefix(ENGINE_REPLIES))
  known.lock.withLock {
    known.replies[positionKey(fen)] = kept
    if let lost {
      known.losses[positionKey(fen)] = Dictionary(kept.enumerated().map { ($0.element, $0.offset < lost.count ? lost[$0.offset] : 0) }, uniquingKeysWith: { a, _ in a })
    }
  }
}
