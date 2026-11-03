import Model
import SwiftUI

/// A favorite on Stats: its tier, its name, its rating across the window as a
/// sparkline, the rating, and how far it moved in the window.
struct FavoriteRow: View {
  var entry: Ranked
  var days: Int
  var onOpen: (String) -> Void

  var body: some View {
    let own = entry.stats
    let rank = rankOf(own.rating, own.rated)
    let change = own.rated > 0 ? Int(JSRound(ratingChange(own, Double(days)))) : nil
    let tint = change.map { $0 > 0 ? Theme.good : $0 < 0 ? Theme.bad : Theme.text3 } ?? Theme.text3
    Button { onOpen(entry.node.id) } label: {
      HStack(spacing: 10) {
        Circle().fill(Color(hexString: (rank.held ?? UNRATED).color)).frame(width: 10, height: 10)
        Text(entry.node.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
          .frame(maxWidth: .infinity, alignment: .leading)
        Sparkline(values: ratingOverTime(own, days).map(\.value), color: tint).frame(width: 56, height: 22)
        Text(own.rated == 0 ? "\u{2014}" : ratingText(own.rating)).font(.system(size: 15, weight: .heavy).monospacedDigit())
          .foregroundStyle(Theme.text).frame(width: 40, alignment: .trailing)
        Text(change.map { $0 == 0 ? "\u{2013}" : "\($0 > 0 ? "\u{25b2}" : "\u{25bc}")\(abs($0))" } ?? "")
          .font(.system(size: 12, weight: .bold).monospacedDigit()).foregroundStyle(tint).frame(width: 38, alignment: .trailing)
      }
      .padding(.horizontal, 16).frame(minHeight: 58).contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

/// A small line with no axes: the shape of a series and nothing else.
struct Sparkline: View {
  var values: [Double]
  var color: Color

  var body: some View {
    Canvas { context, size in
      guard values.count > 1, let lo = values.min(), let hi = values.max() else { return }
      let span = max(hi - lo, 1)
      var path = Path()
      for (i, v) in values.enumerated() {
        let at = CGPoint(x: 2 + (size.width - 4) * CGFloat(i) / CGFloat(values.count - 1), y: 2 + (size.height - 4) * CGFloat(1 - (v - lo) / span))
        if i == 0 { path.move(to: at) } else { path.addLine(to: at) }
      }
      context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }
    .accessibilityHidden(true)
  }
}
