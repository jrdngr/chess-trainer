import Model
import SwiftUI

/// A rating's place between its tier and the next.
struct RankBar<Centre: View>: View {
  var rank: Rank
  @ViewBuilder var centre: Centre
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let fill = SwiftUI.Color(hexString: (rank.held ?? rank.next ?? UNRATED).color)
    VStack(spacing: 6) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(rank.heldLabel).frame(maxWidth: .infinity, alignment: .leading)
        centre.font(.system(size: 14, weight: .heavy).monospacedDigit()).foregroundStyle(Theme.text)
        Text(rank.nextLabel ?? "").frame(maxWidth: .infinity, alignment: .trailing)
      }
      .font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.text2).lineLimit(1)
      GeometryReader { geo in
        ZStack(alignment: .leading) {
          Capsule().fill(Theme.surface3)
          paint(rank.rating).frame(width: geo.size.width)
            .mask(alignment: .leading) { Capsule().frame(width: geo.size.width * rank.progress) }
            .shadow(color: fill.opacity(0.7), radius: 4)
            .animation(reduceMotion ? nil : Motion.arrive(0.7), value: rank.progress)
        }
      }
      .frame(height: 8)
    }
  }
}
