import SwiftUI

/// The announcement's cover: opaque from the first frame, so the board never
/// shows through; its words come in, and it fades out to the board over the
/// last 12% of its 2.5s. `.round-intro` and `roundIntro`.
struct IntroCoverFade: ViewModifier {
  @Environment(\.accessibilityReduceMotion) private var reduce
  @State private var leaving = false

  func body(content: Content) -> some View {
    content
      .opacity(leaving ? 0 : 1)
      .task {
        guard !reduce else { return }
        try? await Task.sleep(for: .milliseconds(2200))
        withAnimation(.easeInOut(duration: 0.3)) { leaving = true }
      }
  }
}

/// The mode's name arriving: `riMode`, from 0.8 scale and clear.
struct IntroModeIn: ViewModifier {
  @Environment(\.accessibilityReduceMotion) private var reduce
  @State private var shown = false

  func body(content: Content) -> some View {
    content
      .scaleEffect(shown || reduce ? 1 : 0.8).opacity(shown || reduce ? 1 : 0)
      .onAppear { withAnimation(Motion.arrive(0.6)) { shown = true } }
  }
}

/// The opening pill over the board: `introPill`, dropping 6pt into place over 0.3s.
struct IntroPillIn: ViewModifier {
  @Environment(\.accessibilityReduceMotion) private var reduce
  @State private var shown = false

  func body(content: Content) -> some View {
    content
      .offset(y: shown || reduce ? 0 : -6).opacity(shown || reduce ? 1 : 0)
      .onAppear { withAnimation(.easeInOut(duration: 0.3)) { shown = true } }
  }
}

/// The board's edge pulsing once the replay hands you the move: `introPulse`, 0.9s.
struct IntroPulse: View {
  var cornerRadius: CGFloat = 14
  @Environment(\.accessibilityReduceMotion) private var reduce
  @State private var played = false

  struct Ring {
    var inner: CGFloat = 3
    var outer: CGFloat = 0
    var outerAlpha: Double = 0
  }

  var body: some View {
    if !reduce {
      Color.clear.keyframeAnimator(initialValue: Ring(), trigger: played) { view, ring in
        view.overlay {
          RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Theme.accent.opacity(ring.inner > 0 ? 1 : 0), lineWidth: max(ring.inner, 0.01))
          RoundedRectangle(cornerRadius: cornerRadius + ring.outer)
            .stroke(Theme.accent.opacity(ring.outerAlpha), lineWidth: max(ring.outer, 0.01))
            .padding(-ring.outer / 2)
        }
      } keyframes: { _ in
        KeyframeTrack(\.outer) {
          LinearKeyframe(6, duration: 0.36, timingCurve: .easeOut)
          LinearKeyframe(14, duration: 0.54, timingCurve: .easeOut)
        }
        KeyframeTrack(\.outerAlpha) {
          LinearKeyframe(1, duration: 0.36, timingCurve: .easeOut)
          LinearKeyframe(0, duration: 0.54, timingCurve: .easeOut)
        }
        KeyframeTrack(\.inner) {
          LinearKeyframe(3, duration: 0.36)
          LinearKeyframe(0, duration: 0.54, timingCurve: .easeOut)
        }
      }
      .onAppear { played = true }
      .allowsHitTesting(false)
    }
  }
}

extension View {
  func introCoverFade() -> some View { modifier(IntroCoverFade()) }
  func introModeIn() -> some View { modifier(IntroModeIn()) }
  func introPillIn() -> some View { modifier(IntroPillIn()) }
}

/// A round announced full screen: the mode's name arriving, then the opening
/// rising in a beat later; the whole cover fades out to the board. Every
/// mode's round starts with it. `.round-intro`.
struct IntroCover: View {
  var mode: String
  var trail: [String]

  var body: some View {
    VStack(spacing: 18) {
      Text(mode).font(.system(size: 56, weight: .heavy)).tracking(-1.7).lineLimit(1).minimumScaleFactor(0.5)
        .foregroundStyle(Theme.text).introModeIn()
      Text(trail.joined(separator: " \u{203a} ")).font(.system(size: 24, weight: .bold)).foregroundStyle(Theme.accent)
        .multilineTextAlignment(.center).arriving(delay: 0.25)
    }
    .padding(.horizontal, 16)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.background.ignoresSafeArea())
    .contentShape(Rectangle())
    .introCoverFade()
  }
}

/// Autopilot's round, announced by its plate: the plate rising in over an
/// opaque cover that fades out to the board. `.intro-plate` in `.round-intro`.
struct PlateIntroCover<Plate: View>: View {
  @ViewBuilder var plate: Plate

  var body: some View {
    ZStack {
      Theme.background.ignoresSafeArea()
      plate.arriving().padding()
    }
    .contentShape(Rectangle())
    .introCoverFade()
  }
}
