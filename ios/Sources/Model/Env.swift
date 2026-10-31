import Foundation

/// Time and chance: the two inputs, besides the engine and the book, a replay
/// has to fix. `src/model/env.ts`. Everything reads them from here; a test or
/// a scripted replay pins them for one task with `Env.$clock.withValue`.
public enum Env {
  @TaskLocal public static var clock: (@Sendable () -> Double)?
  @TaskLocal public static var chance: (@Sendable () -> Double)?

  /// Milliseconds since the epoch.
  public static func now() -> Double { clock?() ?? Date().timeIntervalSince1970 * 1000 }
  /// A number in [0, 1).
  public static func random() -> Double { chance?() ?? Double.random(in: 0..<1) }

  /// Run `body` with the clock pinned to `now`.
  public static func at<T>(_ now: Double, _ body: () throws -> T) rethrows -> T {
    try $clock.withValue({ now }, operation: body)
  }
}

/// The prototype's seeded generator, bit for bit: `mulberry32` in `session.ts`.
public func mulberry32(_ seed: UInt32) -> () -> Double {
  var a = seed
  return {
    a = a &+ 0x6d2b_79f5
    var t = a
    t = (t ^ (t >> 15)) &* (t | 1)
    t ^= t &+ ((t ^ (t >> 7)) &* (t | 61))
    return Double(t ^ (t >> 14)) / 4_294_967_296
  }
}

/// A JS number as `mulberry32` takes it: `seed >>> 0`.
public func mulberry32(seed: Double) -> () -> Double {
  mulberry32(UInt32(truncatingIfNeeded: Int64(seed)))
}
