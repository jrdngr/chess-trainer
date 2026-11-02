import Model
import SwiftUI

/// A rating a round moved: where it stood and where it stands.
struct RatingMoment: Equatable {
  var name: String
  var before: Double
  var after: Double
}

/// The color a rating's bar fills in: its tier's, or the first rung's below it. `ScoreBar.fillColor`.
func fillColor(_ rating: Double) -> Color {
  let rank = rankOf(rating)
  return Color(hexString: (rank.held ?? rank.next ?? UNRATED).color)
}

extension Color {
  init(hexString: String) {
    self.init(hex: UInt32(hexString.dropFirst(), radix: 16) ?? 0)
  }
}

/// The card's state, still or mid-playback.
struct RatingView: Equatable {
  /// The rating the tier names and the paint follow.
  var rating: Double
  /// The number shown, counting toward the new rating.
  var shown: Double
  /// How full the bar is, 0...1.
  var width: Double
  /// How long the width takes to get where it is going; 0 snaps.
  var speed: Double = 0
  /// A tier crossed: the bar flashes in this color. Changes count up each flash.
  var flash: Color?
  var flashes = 0
  /// The stretch a change within a tier added or took away, glowing.
  var stretch: (from: Double, to: Double, gain: Bool)?
  /// The change has started: the delta shows.
  var moved = false
  /// A tier was gained: the card rings, sparks fly, the new tier stamps in.
  var promoted = false
  /// The delta drops in as it shows; a card coming back shows it still.
  var pops = true

  static func resting(_ rating: Double) -> RatingView {
    RatingView(rating: rating, shown: rating, width: rankOf(rating).progress)
  }

  static func == (a: RatingView, b: RatingView) -> Bool {
    a.rating == b.rating && a.shown == b.shown && a.width == b.width && a.speed == b.speed && a.flash == b.flash
      && a.flashes == b.flashes && a.moved == b.moved && a.promoted == b.promoted
      && a.stretch?.from == b.stretch?.from && a.stretch?.to == b.stretch?.to
  }
}

/// The card itself, drawn from a view: still, or mid-playback.
struct RatingCardView: View {
  let moment: RatingMoment
  var view: RatingView

  var body: some View {
    let rank = rankOf(view.rating)
    let color = fillColor(view.rating)
    let delta = Int(JSRound(moment.after - moment.before))
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(moment.name).font(.system(size: 16, weight: .bold)).tracking(-0.16).foregroundStyle(Theme.text).lineLimit(1)
          .frame(maxWidth: .infinity, alignment: .leading)
        if view.moved {
          Text(delta >= 0 ? "+\(delta)" : "\(delta)").font(.system(size: 14, weight: .heavy).monospacedDigit())
            .foregroundStyle(delta < 0 ? Theme.bad : Theme.good).deltaPop(on: view.pops)
        }
        Text("\(Int(JSRound(view.shown)))").font(.system(size: 22, weight: .heavy).monospacedDigit()).foregroundStyle(Theme.text)
          .frame(minWidth: 44, alignment: .trailing)
          .numberGlow(color, on: view.promoted)
      }
      HStack(alignment: .firstTextBaseline) {
        Text(rank.heldLabel).foregroundStyle(color).tierPop(on: view.promoted, color: color).id(rank.heldLabel)
        Spacer()
        Text(rank.nextLabel ?? "")
      }
      .font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.text2).padding(.top, 10)
      RatingTrack(view: view, color: color).frame(height: 10).padding(.top, 6)
    }
    .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 16)
    .background(RoundedRectangle(cornerRadius: 18).fill(Theme.surface))
    .overlay { if view.promoted { PromotionShine().clipShape(RoundedRectangle(cornerRadius: 18)) } }
    .promotionRing(on: view.promoted, color: color)
  }
}

/// The bar: the fill growing at the view's speed, the stretch glowing, the flash, the sparks.
struct RatingTrack: View {
  let view: RatingView
  let color: Color
  @Environment(\.accessibilityReduceMotion) private var reduce

  var body: some View {
    GeometryReader { geo in
      let w = geo.size.width
      ZStack(alignment: .leading) {
        RoundedRectangle(cornerRadius: 5).fill(Theme.surface3)
        paint(view.rating).frame(width: w)
          .mask(alignment: .leading) { RoundedRectangle(cornerRadius: 5).frame(width: w * view.width) }
          .shadow(color: color, radius: 5)
          .animation(view.speed > 0 && !reduce ? Motion.arrive(view.speed) : nil, value: view.width)
        if let s = view.stretch, s.from != s.to {
          StretchGlow(gain: s.gain).frame(width: w * abs(s.to - s.from)).offset(x: w * min(s.from, s.to))
        }
        if let flash = view.flash { RatingFlash(color: flash).id(view.flashes) }
        if view.promoted { SparkBurst(color: color).offset(x: w) }
      }
    }
  }
}

/// The rating change at rest, where it stays on the end screen: `RatingCard`, arriving from above.
struct RestingRatingCard: View {
  let moment: RatingMoment
  var arriving = true

  private var view: RatingView {
    var v = RatingView.resting(moment.after)
    v.moved = true
    v.pops = arriving
    return v
  }

  var body: some View {
    RatingCardView(moment: moment, view: view)
      .modifier(Arriving(offset: -40, scale: 0.97, duration: arriving ? 0.5 : 0, delay: 0))
  }
}
