import SwiftUI

/// The board's edge flaring once and fading: green when you found a moment, red when you missed it.
struct EdgePulse: View {
  var color: Color
  @Environment(\.accessibilityReduceMotion) private var reduce
  @State private var played = false

  var body: some View {
    if reduce {
      RoundedRectangle(cornerRadius: 4).strokeBorder(color.opacity(0.8), lineWidth: 3).allowsHitTesting(false)
    } else {
      Color.clear.keyframeAnimator(initialValue: (glow: 0.0, spread: 0.0), trigger: played) { view, v in
        view.overlay {
          RoundedRectangle(cornerRadius: 4)
            .stroke(color.opacity(v.glow), lineWidth: 3)
            .shadow(color: color.opacity(0.85 * v.glow), radius: 8 + 22 * v.spread)
            .shadow(color: color.opacity(0.4 * v.glow), radius: 20 + 30 * v.spread)
        }
      } keyframes: { _ in
        KeyframeTrack(\.glow) {
          LinearKeyframe(1, duration: 0.2, timingCurve: .easeOut)
          LinearKeyframe(0, duration: 1.25, timingCurve: .easeOut)
        }
        KeyframeTrack(\.spread) {
          LinearKeyframe(1, duration: 1.45, timingCurve: .easeOut)
        }
      }
      .onAppear { played = true }
      .allowsHitTesting(false)
    }
  }
}
