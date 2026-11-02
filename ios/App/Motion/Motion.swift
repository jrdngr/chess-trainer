import SwiftUI

/// The app's motion: its easing curves and keyframe animations, each
/// honoring Reduce Motion.
enum Motion {
  /// `cubic-bezier(0.22, 1, 0.36, 1)`: arrivals.
  static func arrive(_ seconds: Double) -> Animation { .timingCurve(0.22, 1, 0.36, 1, duration: seconds) }
  /// `cubic-bezier(0.3, 0.9, 0.4, 1)`: a piece sliding to its square.
  static func slide(_ seconds: Double) -> Animation { .timingCurve(0.3, 0.9, 0.4, 1, duration: seconds) }
  /// `cubic-bezier(0.2, 1.5, 0.4, 1)` and kin: an overshooting pop.
  static func pop(_ seconds: Double, overshoot: Double = 1.5) -> Animation { .timingCurve(0.2, overshoot, 0.4, 1, duration: seconds) }
}

/// `.board-flash`'s `boardFlash`: in over the first 8%, held, out over the last 20%.
struct BoardFlashFade: ViewModifier {
  var duration: Double = 2
  @Environment(\.accessibilityReduceMotion) private var reduce

  func body(content: Content) -> some View {
    if reduce {
      content
    } else {
      content.keyframeAnimator(initialValue: 0.0) { view, opacity in
        view.opacity(opacity)
      } keyframes: { _ in
        LinearKeyframe(1, duration: duration * 0.08, timingCurve: .easeInOut)
        LinearKeyframe(1, duration: duration * 0.72)
        LinearKeyframe(0, duration: duration * 0.2, timingCurve: .easeInOut)
      }
    }
  }
}

extension View {
  /// Fades in, holds and fades out over `duration`.
  func boardFlash(_ duration: Double = 2) -> some View { modifier(BoardFlashFade(duration: duration)) }

  /// Arrives from below and fades in: `riOpening` and `ratingArrive`.
  func arriving(offset: CGFloat = 14, scale: CGFloat = 1, duration: Double = 0.6, delay: Double = 0) -> some View {
    modifier(Arriving(offset: offset, scale: scale, duration: duration, delay: delay))
  }
}

struct Arriving: ViewModifier {
  var offset: CGFloat
  var scale: CGFloat
  var duration: Double
  var delay: Double
  @Environment(\.accessibilityReduceMotion) private var reduce
  @State private var shown = false

  func body(content: Content) -> some View {
    content
      .opacity(shown || reduce ? 1 : 0)
      .offset(y: shown || reduce ? 0 : offset)
      .scaleEffect(shown || reduce ? 1 : scale)
      .onAppear { withAnimation(Motion.arrive(duration).delay(delay)) { shown = true } }
  }
}

/// `shake`: a quick side-to-side when `on` turns true, 0.45s easing out. The clock running out.
struct Shake: ViewModifier {
  var on: Bool
  @Environment(\.accessibilityReduceMotion) private var reduce

  func body(content: Content) -> some View {
    content.keyframeAnimator(initialValue: 0.0, trigger: on) { view, x in
      view.offset(x: reduce || !on ? 0 : x)
    } keyframes: { _ in
      for x in [-4.0, 4, -3, 3, 0] { CubicKeyframe(x, duration: 0.09) }
    }
  }
}

extension View {
  func shake(on: Bool) -> some View { modifier(Shake(on: on)) }
}
