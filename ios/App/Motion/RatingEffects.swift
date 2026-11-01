import SwiftUI

/// The rating card's effects, each a web keyframe animation. Under Reduce
/// Motion each shows its end state, or nothing for the ones that only flash.

/// `ratingDelta`: the change dropping in from 1.6x, 0.5s with an overshoot.
struct DeltaPop: ViewModifier {
  @Environment(\.accessibilityReduceMotion) private var reduce
  @State private var shown = false
  func body(content: Content) -> some View {
    content.scaleEffect(shown || reduce ? 1 : 1.6).offset(y: shown || reduce ? 0 : 6).opacity(shown || reduce ? 1 : 0)
      .onAppear { withAnimation(Motion.pop(0.5)) { shown = true } }
  }
}

/// `tierPop`: a new tier's name slamming in from 2.4x, undershooting to 0.92, glowing.
struct TierPop: ViewModifier {
  var on: Bool
  var color: Color
  @Environment(\.accessibilityReduceMotion) private var reduce

  func body(content: Content) -> some View {
    if on && !reduce {
      content.shadow(color: color, radius: 6)
        .keyframeAnimator(initialValue: (scale: 2.4, opacity: 0.0)) { view, v in
          view.scaleEffect(v.scale, anchor: .leading).opacity(v.opacity)
        } keyframes: { _ in
          KeyframeTrack(\.scale) {
            CubicKeyframe(0.92, duration: 0.42)
            CubicKeyframe(1, duration: 0.28)
          }
          KeyframeTrack(\.opacity) {
            LinearKeyframe(1, duration: 0.42)
          }
        }
    } else {
      content
    }
  }
}

/// `ratingNumGlow`: the number glowing in the tier's color a quarter of the way through 1.6s.
struct NumberGlow: ViewModifier {
  var color: Color
  var on: Bool
  @Environment(\.accessibilityReduceMotion) private var reduce

  func body(content: Content) -> some View {
    if on && !reduce {
      content.keyframeAnimator(initialValue: 0.0) { view, k in
        view.foregroundStyle(Theme.text.mix(with: color, by: k)).shadow(color: color.opacity(k), radius: 7)
      } keyframes: { _ in
        LinearKeyframe(1, duration: 0.4, timingCurve: .easeOut)
        LinearKeyframe(0, duration: 1.2, timingCurve: .easeOut)
      }
    } else {
      content
    }
  }
}

/// `ratingRing`: the promoted card ringing in its tier's color, settling to a faint outline over 1.8s.
struct PromotionRing: ViewModifier {
  var on: Bool
  var color: Color
  @Environment(\.accessibilityReduceMotion) private var reduce

  func body(content: Content) -> some View {
    if on {
      content.overlay {
        if reduce {
          RoundedRectangle(cornerRadius: 18).strokeBorder(color.opacity(0.45), lineWidth: 1)
        } else {
          Color.clear.keyframeAnimator(initialValue: (ring: 0.0, glow: 0.0)) { view, v in
            view.overlay {
              RoundedRectangle(cornerRadius: 18).strokeBorder(color.opacity(max(v.ring, 0.45 * min(1, v.glow * 10))), lineWidth: v.ring > 0.5 ? 2 : 1)
                .shadow(color: color.opacity(v.glow), radius: 22)
            }
          } keyframes: { _ in
            KeyframeTrack(\.ring) {
              LinearKeyframe(1, duration: 0.32, timingCurve: .easeOut)
              LinearKeyframe(0.45, duration: 1.48, timingCurve: .easeOut)
            }
            KeyframeTrack(\.glow) {
              LinearKeyframe(1, duration: 0.32, timingCurve: .easeOut)
              LinearKeyframe(0, duration: 1.48, timingCurve: .easeOut)
            }
          }
          .allowsHitTesting(false)
        }
      }
    } else {
      content
    }
  }
}

/// `ratingShine`: a sheen sweeping across the promoted card, 1.1s after a 0.1s beat.
struct PromotionShine: View {
  @Environment(\.accessibilityReduceMotion) private var reduce
  @State private var swept = false

  var body: some View {
    if !reduce {
      GeometryReader { geo in
        LinearGradient(stops: [.init(color: .clear, location: 0.35), .init(color: .white.opacity(0.2), location: 0.5), .init(color: .clear, location: 0.65)],
                       startPoint: .leading, endPoint: .trailing)
          .frame(width: geo.size.width * 2.6)
          .rotationEffect(.degrees(15))
          .offset(x: swept ? -geo.size.width * 2.6 : geo.size.width * 0.4)
          .onAppear { withAnimation(.easeOut(duration: 1.1).delay(0.1)) { swept = true } }
      }
      .allowsHitTesting(false)
    }
  }
}

/// `stretchGlow`: the stretch a change added (white) or took (red), glowing up and fading over 1.3s.
struct StretchGlow: View {
  var gain: Bool
  @Environment(\.accessibilityReduceMotion) private var reduce

  var body: some View {
    let color: Color = gain ? .white : Theme.bad
    if !reduce {
      RoundedRectangle(cornerRadius: 5).fill(color).padding(.vertical, -1)
        .shadow(color: gain ? .white.opacity(0.6) : Theme.bad, radius: 6)
        .keyframeAnimator(initialValue: 0.0) { view, o in view.opacity(o) } keyframes: { _ in
          LinearKeyframe(0.9, duration: 0.2, timingCurve: .easeOut)
          LinearKeyframe(0, duration: 1.1, timingCurve: .easeOut)
        }
        .allowsHitTesting(false)
    }
  }
}

/// `ratingFlash`: the bar flashing twice in a tier's color (or red on a drop) over 0.76s.
struct RatingFlash: View {
  var color: Color
  @Environment(\.accessibilityReduceMotion) private var reduce

  var body: some View {
    RoundedRectangle(cornerRadius: 5).fill(color).padding(.vertical, -2)
      .shadow(color: color, radius: 11)
      .keyframeAnimator(initialValue: (bright: 1.0, opacity: 1.0)) { view, v in
        view.brightness(reduce ? 0 : (v.bright - 1) * 0.5).opacity(reduce ? 1 : v.opacity)
      } keyframes: { _ in
        KeyframeTrack(\.bright) {
          LinearKeyframe(1.9, duration: 0.19, timingCurve: .easeOut)
          LinearKeyframe(1, duration: 0.19, timingCurve: .easeOut)
          LinearKeyframe(1.9, duration: 0.19, timingCurve: .easeOut)
          LinearKeyframe(1, duration: 0.19, timingCurve: .easeOut)
        }
        KeyframeTrack(\.opacity) {
          LinearKeyframe(0.85, duration: 0.19)
          LinearKeyframe(1, duration: 0.19)
          LinearKeyframe(0.85, duration: 0.19)
          LinearKeyframe(1, duration: 0.19)
        }
      }
      .allowsHitTesting(false)
  }
}

/// `ratingSpark`: sixteen sparks thrown off the bar's end on a promotion.
struct SparkBurst: View {
  var color: Color
  @Environment(\.accessibilityReduceMotion) private var reduce
  @State private var thrown = false

  /// Angle, distance and flight time of each, as the web spreads them.
  static let sparks: [(a: Double, d: CGFloat, t: Double)] = (0..<16).map { i in
    let tilt: Double = i % 2 == 1 ? 9 : -5
    let a: Double = (Double(i) * 22.5 + tilt).rounded()
    let d = CGFloat(40 + (i * 17) % 38)
    let t: Double = 0.55 + Double((i * 7) % 5) / 10
    return (a, d, t)
  }

  var body: some View {
    if !reduce {
      ZStack {
        ForEach(Array(Self.sparks.enumerated()), id: \.offset) { _, s in
          Capsule().fill(color).frame(width: 9, height: 3).shadow(color: color, radius: 4)
            .scaleEffect(x: thrown ? 0.4 : 1.6, y: 1, anchor: .leading)
            .offset(x: thrown ? s.d : 0)
            .opacity(thrown ? 0 : 1)
            .rotationEffect(.degrees(s.a), anchor: .leading)
            .animation(.timingCurve(0.1, 0.8, 0.3, 1, duration: s.t), value: thrown)
            .frame(width: 9, height: 3, alignment: .leading)
            .offset(x: 4.5)
        }
      }
      .frame(width: 0, height: 0)
      .onAppear { thrown = true }
      .allowsHitTesting(false)
    }
  }
}

extension View {
  func deltaPop() -> some View { modifier(DeltaPop()) }
  func tierPop(on: Bool, color: Color) -> some View { modifier(TierPop(on: on, color: color)) }
  func numberGlow(_ color: Color, on: Bool) -> some View { modifier(NumberGlow(color: color, on: on)) }
  func promotionRing(on: Bool, color: Color) -> some View { modifier(PromotionRing(on: on, color: color)) }
}
