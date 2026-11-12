import Model
import Observation

/// Endgame mode: the library, then one position at a time. Practice plays
/// what is due in a row; a single ending plays alone.
@MainActor @Observable
public final class EndgameSession {
  @ObservationIgnored private let store: AppStore
  /// The round on the board.
  public private(set) var game: EndgameGame?
  /// The positions left in a "Play due" sitting, after the one on the board.
  public private(set) var queue: [EndgameEntry] = []

  public init(store: AppStore) {
    self.store = store
  }

  /// Practice: what is due, else the next ending to learn. False when there is neither.
  @discardableResult
  public func practice() -> Bool {
    let record = store.state.endgames
    if !record.due.isEmpty {
      play(record.due)
    } else if let next = record.next {
      play([next])
    } else {
      return false
    }
    return true
  }

  /// Play these endings in order.
  public func play(_ entries: [EndgameEntry]) {
    guard let first = entries.first else { return }
    game?.stop()
    queue = Array(entries.dropFirst())
    game = EndgameGame(entry: first, store: store)
  }

  /// On to the next ending in the sitting, or back to the library after the last.
  public func next() {
    game?.stop()
    guard let first = queue.first else {
      game = nil
      return
    }
    queue.removeFirst()
    game = EndgameGame(entry: first, store: store)
  }

  /// Back to the library.
  public func close() {
    game?.stop()
    game = nil
    queue = []
  }
}
