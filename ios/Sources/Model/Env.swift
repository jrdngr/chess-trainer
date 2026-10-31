import Foundation

/// Time and chance: the two inputs, besides the engine and the book, a replay
/// has to fix. `src/model/env.ts`. Everything reads them from here, so a test
/// or a scripted replay can pin both.
public enum Env {
  nonisolated(unsafe) public static var now: () -> Double = { Date().timeIntervalSince1970 * 1000 }
  /// A number in [0, 1).
  nonisolated(unsafe) public static var random: () -> Double = { Double.random(in: 0..<1) }
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
