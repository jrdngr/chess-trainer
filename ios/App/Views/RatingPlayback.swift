import Model
import SwiftUI

/// A round's rating change, played on its bar.
/// A gain grows the bar with the stretch it added glowing; a promotion fills it
/// to the end, flashes it in the new tier's color, throws sparks and regrows it
/// from the left; a drop flashes red and shrinks. The number counts along.
@Observable @MainActor
final class RatingPlayer {
  static let leadMs = 0.7, growMs = 0.9, topMs = 0.65, flashMs = 0.76, regrowMs = 0.7, holdMs = 1.1

  private(set) var view: RatingView
  private let moment: RatingMoment
  /// Every beat's length is scaled by this: 1 on the end screen, less on the way to the next run.
  private let pace: Double
  private var tasks: [Task<Void, Never>] = []

  init(_ moment: RatingMoment, pace: Double = 1) {
    self.moment = moment
    self.pace = pace
    view = .resting(moment.before)
  }

  /// Plays it through, calling `onDone` once it has settled and been seen.
  func play(haptics: Bool, onDone: @escaping () -> Void) {
    guard tasks.isEmpty else { return }
    let (before, after) = (moment.before, moment.after)
    let was = rankOf(before), now = rankOf(after)
    let pace = self.pace
    let lead = (Self.leadMs * pace)
    let end: Double
    if now.reached == was.reached {
      at(lead) {
        $0.width = now.progress
        $0.speed = (Self.growMs * pace)
        $0.moved = true
        $0.stretch = (was.progress, now.progress, after > before)
      }
      count(lead, (Self.growMs * pace), before, after)
      end = lead + (Self.growMs * pace) + 0.3 * pace
    } else if now.reached > was.reached {
      let color = fillColor(after)
      at(lead) {
        $0.width = 1
        $0.speed = (Self.topMs * pace)
        $0.moved = true
      }
      count(lead, (Self.topMs * pace), before, now.floor)
      let top = lead + (Self.topMs * pace)
      at(top) {
        Haptics.pattern([20, 40, 20, 40, 60], on: haptics)
        $0.rating = after
        $0.flash = color
        $0.flashes += 1
        $0.promoted = true
        $0.speed = 0
      }
      at(top + (Self.flashMs * pace)) {
        $0.width = 0
        $0.flash = nil
        $0.speed = 0
      }
      at(top + (Self.flashMs * pace) + 0.04) { self.settle(&$0, now) }
      count(top + (Self.flashMs * pace) + 0.04, (Self.regrowMs * pace), now.floor, after)
      end = top + (Self.flashMs * pace) + 0.04 + (Self.regrowMs * pace) + 0.5 * pace
    } else {
      at(lead) {
        Haptics.pattern([60, 50, 60], on: haptics)
        $0.width = 1
        $0.speed = 0
        $0.flash = Theme.bad
        $0.flashes += 1
        $0.moved = true
      }
      count(lead, (Self.flashMs * pace) + (Self.regrowMs * pace), before, after)
      at(lead + (Self.flashMs * pace)) {
        self.settle(&$0, now)
        $0.flash = nil
      }
      end = lead + (Self.flashMs * pace) + (Self.regrowMs * pace) + 0.3 * pace
    }
    tasks.append(Task {
      try? await Task.sleep(for: .seconds(end + (Self.holdMs * pace)))
      if !Task.isCancelled { onDone() }
    })
  }

  func stop() {
    tasks.forEach { $0.cancel() }
  }

  private func settle(_ v: inout RatingView, _ now: Rank) {
    v.rating = moment.after
    v.width = now.progress
    v.speed = (Self.regrowMs * pace)
  }

  private func at(_ s: Double, _ step: @escaping (inout RatingView) -> Void) {
    tasks.append(Task {
      try? await Task.sleep(for: .seconds(s))
      if !Task.isCancelled { step(&view) }
    })
  }

  /// The number counting from one value to another, easing out.
  private func count(_ start: Double, _ duration: Double, _ from: Double, _ to: Double) {
    tasks.append(Task {
      try? await Task.sleep(for: .seconds(start))
      let t0 = Date.now
      while !Task.isCancelled {
        let t = min(1, Date.now.timeIntervalSince(t0) / duration)
        view.shown = from + (to - from) * (1 - pow(1 - t, 3))
        if t >= 1 { break }
        try? await Task.sleep(for: .milliseconds(16))
      }
    })
  }
}

/// The rating change playing over the board as the end screen opens: `RatingOverBoard`.
/// A promotion also stamps the new tier's name over the board. A tap skips
/// it; either way `onDone` sends it down to its place on the screen.
struct RatingOverBoard: View {
  let moment: RatingMoment
  var leaving: Bool
  let onDone: () -> Void
  @Environment(AppStore.self) private var store
  @Environment(\.accessibilityReduceMotion) private var reduce
  @State private var player: RatingPlayer
  @State private var shown = false

  /// `pace` scales the playback: Next run plays it quicker than the end screen.
  init(moment: RatingMoment, leaving: Bool, pace: Double = 1, onDone: @escaping () -> Void) {
    self.moment = moment
    self.leaving = leaving
    self.onDone = onDone
    _player = State(initialValue: RatingPlayer(moment, pace: pace))
  }

  var body: some View {
    let view = player.view
    let color = fillColor(view.rating)
    ZStack {
      RoundedRectangle(cornerRadius: 14).fill(Color(red: 13 / 255, green: 13 / 255, blue: 16 / 255).opacity(0.5))
      if view.promoted {
        GeometryReader { geo in
          RatingRays(color: color).position(x: geo.size.width / 2, y: geo.size.height * 0.26)
          RatingStamp(text: rankOf(view.rating).heldLabel, color: color)
            .frame(maxWidth: .infinity).offset(y: geo.size.height * 0.16)
        }
        .allowsHitTesting(false)
      }
      RatingCardView(moment: moment, view: view)
        .shadow(color: .black.opacity(0.55), radius: 22, y: 14)
        .padding(.horizontal, 14)
    }
    .clipShape(RoundedRectangle(cornerRadius: 14))
    .contentShape(Rectangle())
    .onTapGesture { onDone() }
    .accessibilityAddTraits(.isButton).accessibilityLabel("Skip")
    .opacity(leaving ? 0 : shown ? 1 : 0)
    .offset(y: leaving && !reduce ? 60 : 0)
    .scaleEffect(leaving && !reduce ? 0.95 : 1)
    .animation(.easeIn(duration: 0.32), value: leaving)
    .allowsHitTesting(!leaving)
    .onAppear {
      withAnimation(reduce ? nil : .easeOut(duration: 0.35)) { shown = true }
      player.play(haptics: store.state.settings.hapticFeedback, onDone: onDone)
    }
    .onDisappear { player.stop() }
  }
}

/// `ratingStamp`: the new tier's name slamming down from 2.8x over the board.
struct RatingStamp: View {
  let text: String
  let color: Color
  @Environment(\.accessibilityReduceMotion) private var reduce
  @State private var played = false

  var body: some View {
    Text(text).font(.system(size: 54, weight: .black)).tracking(-1.08).foregroundStyle(color)
      .shadow(color: color, radius: 14).shadow(color: .black.opacity(0.45), radius: 0, y: 2)
      .lineLimit(1).minimumScaleFactor(0.5)
      .keyframeAnimator(initialValue: (scale: reduce ? 1.0 : 2.8, opacity: reduce ? 1.0 : 0.0), trigger: played) { view, v in
        view.scaleEffect(v.scale).opacity(v.opacity)
      } keyframes: { _ in
        KeyframeTrack(\.scale) {
          CubicKeyframe(0.94, duration: reduce ? 0 : 0.405)
          CubicKeyframe(1, duration: reduce ? 0 : 0.495)
        }
        KeyframeTrack(\.opacity) { LinearKeyframe(1, duration: reduce ? 0 : 0.4) }
      }
      .onAppear { played = true }
  }
}

/// `ratingRays`: tier-colored stripes turning and spreading behind the stamp, then gone.
struct RatingRays: View {
  let color: Color
  @Environment(\.accessibilityReduceMotion) private var reduce
  @State private var played = false

  var body: some View {
    if !reduce {
      AngularGradient(stops: Self.stripes(color), center: .center)
        .frame(width: 460, height: 460)
        .mask(RadialGradient(colors: [.black, .clear], center: .center, startRadius: 0, endRadius: 230 * 0.62))
        .keyframeAnimator(initialValue: (turn: 0.0, scale: 0.3, opacity: 0.0), trigger: played) { view, v in
          view.rotationEffect(.degrees(v.turn)).scaleEffect(v.scale).opacity(v.opacity)
        } keyframes: { _ in
          KeyframeTrack(\.turn) { LinearKeyframe(50, duration: 2.4, timingCurve: .easeOut) }
          KeyframeTrack(\.scale) { LinearKeyframe(1.15, duration: 2.4, timingCurve: .easeOut) }
          KeyframeTrack(\.opacity) {
            LinearKeyframe(1, duration: 0.48, timingCurve: .easeOut)
            LinearKeyframe(0, duration: 1.92, timingCurve: .easeOut)
          }
        }
        .onAppear { played = true }
    }
  }

  /// 40% tier for 7 degrees, clear for 13, all the way round.
  static func stripes(_ color: Color) -> [Gradient.Stop] {
    (0..<18).flatMap { i -> [Gradient.Stop] in
      let a = Double(i) * 20 / 360, b = (Double(i) * 20 + 7) / 360
      let on = color.opacity(0.4)
      return [.init(color: on, location: a), .init(color: on, location: b), .init(color: .clear, location: b), .init(color: .clear, location: a + 20 / 360)]
    }
  }
}
