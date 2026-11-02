import UIKit

/// Buzz patterns, as taps of the feedback generator.
@MainActor
enum Haptics {
  private static let light = UIImpactFeedbackGenerator(style: .light)
  private static let heavy = UIImpactFeedbackGenerator(style: .heavy)

  /// A pattern's first pulse, in milliseconds: longer reads heavier.
  static func buzz(_ ms: Int, on: Bool) {
    guard on else { return }
    (ms >= 20 ? heavy : light).impactOccurred()
  }

  /// A whole pattern, buzz and pause alternating, in milliseconds: `haptic([20, 40, 20])`.
  static func pattern(_ ms: [Int], on: Bool) {
    guard on else { return }
    var at = 0
    for (i, step) in ms.enumerated() {
      if i % 2 == 0 {
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(at)) { buzz(step, on: true) }
      }
      at += step
    }
  }
}
