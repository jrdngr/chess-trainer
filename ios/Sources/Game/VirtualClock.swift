import Foundation

/// A clock that only moves when told to: a headless game's beats (the opponent's
/// pause, a popup's life) pass in no real time, and in a fixed order.
@MainActor public final class VirtualClock: GameClock {
  private struct Sleeper {
    var id: Int
    var at: Double
    var wake: CheckedContinuation<Void, Never>
  }

  public private(set) var now: Double
  private var sleepers: [Sleeper] = []
  private var nextId = 0
  /// Read off the main actor by `Env`'s clock: milliseconds, as `Env.now()` gives them.
  nonisolated let millis: LockedValue<Double>

  public init(start: Double = 1_790_845_200) {
    now = start
    millis = LockedValue(start * 1000)
  }

  /// Beats waiting to end.
  public var sleeping: Int { sleepers.count }
  /// When the next beat ends.
  public var nextWake: Double? { sleepers.map(\.at).min() }

  public func sleep(_ seconds: Double) async {
    if Task.isCancelled { return }
    nextId += 1
    let id = nextId
    let at = now + max(0, seconds)
    await withTaskCancellationHandler {
      await withCheckedContinuation { wake in sleepers.append(Sleeper(id: id, at: at, wake: wake)) }
    } onCancel: {
      Task { @MainActor in self.release(id) }
    }
  }

  /// A cancelled beat ends at once.
  private func release(_ id: Int) {
    guard let i = sleepers.firstIndex(where: { $0.id == id }) else { return }
    sleepers.remove(at: i).wake.resume()
  }

  /// Move the clock on to the next beat's end and end it, and any due with it. False when nothing waits.
  @discardableResult
  public func wakeNext() -> Bool {
    guard let at = nextWake else { return false }
    set(max(now, at))
    let due = sleepers.filter { $0.at <= now }.sorted { ($0.at, $0.id) < ($1.at, $1.id) }
    sleepers.removeAll { $0.at <= now }
    for sleeper in due { sleeper.wake.resume() }
    return true
  }

  /// Time passing with nothing woken: a player thinking over a move.
  public func pass(_ seconds: Double) {
    set(now + seconds)
  }

  private func set(_ value: Double) {
    now = value
    millis.set(value * 1000)
  }
}

/// A value shared across threads behind a lock.
public final class LockedValue<Value: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Value
  public init(_ value: Value) { self.value = value }
  public func get() -> Value { lock.withLock { value } }
  public func set(_ new: Value) { lock.withLock { value = new } }
  public func update<T>(_ change: (inout Value) -> T) -> T { lock.withLock { change(&value) } }
}
