import UIKit

/// The prototype's `haptic` buzz patterns, as taps of the feedback generator.
@MainActor
enum Haptics {
  private static let light = UIImpactFeedbackGenerator(style: .light)
  private static let heavy = UIImpactFeedbackGenerator(style: .heavy)

  /// A pattern's first pulse, in milliseconds: longer reads heavier.
  static func buzz(_ ms: Int, on: Bool) {
    guard on else { return }
    (ms >= 20 ? heavy : light).impactOccurred()
  }
}
