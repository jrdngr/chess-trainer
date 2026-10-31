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

/// The card, drawn from a view of it: still, or mid-playback. `RatingCard.tsx`.
struct RatingCardView: View {
  let moment: RatingMoment
  var rating: Double
  var shown: Double
  var width: Double
  var moved = true
  var flash: Color?
  var promoted = false

  var body: some View {
    let rank = rankOf(rating)
    let color = fillColor(rating)
    let delta = Int(JSRound(moment.after - moment.before))
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(moment.name).font(.subheadline.bold()).foregroundStyle(Theme.text).lineLimit(1)
        Spacer()
        if moved {
          Text(delta >= 0 ? "+\(delta)" : "\(delta)").font(.subheadline.bold().monospacedDigit())
            .foregroundStyle(delta < 0 ? Theme.bad : Theme.good)
        }
        Text("\(Int(JSRound(shown)))").font(.headline.monospacedDigit()).foregroundStyle(Theme.text)
      }
      HStack {
        Text(rank.heldLabel).font(.caption.bold()).foregroundStyle(color)
          .scaleEffect(promoted ? 1.15 : 1).animation(.spring(duration: 0.4), value: promoted)
        Spacer()
        Text(rank.nextLabel ?? "").font(.caption).foregroundStyle(Theme.text2)
      }
      GeometryReader { geo in
        ZStack(alignment: .leading) {
          Capsule().fill(Theme.surface2)
          Capsule().fill(color).frame(width: geo.size.width * width)
            .shadow(color: color.opacity(0.8), radius: 6)
          if let flash { Capsule().fill(flash) }
        }
      }
      .frame(height: 8)
    }
    .padding(14)
    .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
    .overlay(RoundedRectangle(cornerRadius: 14).stroke(promoted ? color : .clear, lineWidth: 2))
  }
}

/// The rating change playing over the board as the end screen opens: a gain
/// grows the bar; a promotion fills it, flashes the new tier, stamps its name
/// and regrows; a drop flashes red and shrinks. A tap skips to the end.
struct RatingPlayback: View {
  let moment: RatingMoment
  let onDone: () -> Void

  /// Before the bar moves; a change within a tier; the fill, flash and regrowth of a promotion; the hold.
  static let lead = 0.7, grow = 0.9, top = 0.65, flashTime = 0.76, regrow = 0.7, hold = 1.1

  @State private var rating: Double
  @State private var shown: Double
  @State private var width: Double
  @State private var moved = false
  @State private var flash: Color?
  @State private var promoted = false

  init(moment: RatingMoment, onDone: @escaping () -> Void) {
    self.moment = moment
    self.onDone = onDone
    _rating = State(initialValue: moment.before)
    _shown = State(initialValue: moment.before)
    _width = State(initialValue: rankOf(moment.before).progress)
  }

  var body: some View {
    VStack(spacing: 14) {
      if promoted {
        Text(rankOf(rating).heldLabel).font(.system(size: 40, weight: .heavy)).foregroundStyle(fillColor(rating))
          .shadow(color: fillColor(rating), radius: 12)
          .transition(.scale.combined(with: .opacity))
      }
      RatingCardView(moment: moment, rating: rating, shown: shown, width: width, moved: moved, flash: flash, promoted: promoted)
    }
    .padding()
    .contentShape(Rectangle())
    .onTapGesture(perform: onDone)
    .task { await play() }
  }

  private func wait(_ seconds: Double) async { try? await Task.sleep(for: .seconds(seconds)) }

  private func count(from: Double, to: Double, over seconds: Double) async {
    let steps = max(1, Int(seconds * 30))
    for i in 1...steps {
      let t = Double(i) / Double(steps)
      shown = from + (to - from) * (1 - pow(1 - t, 3))
      await wait(seconds / Double(steps))
    }
  }

  private func play() async {
    let before = moment.before, after = moment.after
    let was = rankOf(before), now = rankOf(after)
    await wait(Self.lead)
    moved = true
    if now.reached == was.reached {
      withAnimation(.easeOut(duration: Self.grow)) { width = now.progress }
      await count(from: before, to: after, over: Self.grow)
    } else if now.reached > was.reached {
      withAnimation(.easeOut(duration: Self.top)) { width = 1 }
      await count(from: before, to: now.floor, over: Self.top)
      rating = after
      flash = fillColor(after)
      withAnimation { promoted = true }
      await wait(Self.flashTime)
      flash = nil
      width = 0
      withAnimation(.easeOut(duration: Self.regrow)) { width = now.progress }
      await count(from: now.floor, to: after, over: Self.regrow)
    } else {
      // No tier is red, so the flash reads only as a drop.
      flash = Theme.bad
      width = 1
      async let counting: Void = count(from: before, to: after, over: Self.flashTime + Self.regrow)
      await wait(Self.flashTime)
      flash = nil
      rating = after
      withAnimation(.easeOut(duration: Self.regrow)) { width = now.progress }
      await counting
    }
    await wait(Self.hold)
    onDone()
  }
}
