import SwiftUI

/// What a move cost, floating up from its square: `moveScore`, 1.4s ease-out.
/// In from 6pt below over the first 15%, held while it rises 10pt, then up
/// another 8pt as it fades.
struct MoveScoreFloat: ViewModifier {
  @Environment(\.accessibilityReduceMotion) private var reduce
  @State private var played = false

  struct Frame {
    var opacity = 0.0
    var y: CGFloat = 6
  }

  func body(content: Content) -> some View {
    if reduce {
      content
    } else {
      content.keyframeAnimator(initialValue: Frame(), trigger: played) { view, f in
        view.opacity(f.opacity).offset(y: f.y)
      } keyframes: { _ in
        KeyframeTrack(\.opacity) {
          LinearKeyframe(1, duration: 0.21, timingCurve: .easeOut)
          LinearKeyframe(1, duration: 0.77)
          LinearKeyframe(0, duration: 0.42, timingCurve: .easeOut)
        }
        KeyframeTrack(\.y) {
          LinearKeyframe(0, duration: 0.21, timingCurve: .easeOut)
          LinearKeyframe(-10, duration: 0.77, timingCurve: .easeOut)
          LinearKeyframe(-18, duration: 0.42, timingCurve: .easeOut)
        }
      }
      .onAppear { played = true }
    }
  }
}
