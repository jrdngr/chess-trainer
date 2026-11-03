import Model
import SwiftUI

/// Where the rounds went: one bar split by mode, and under it each mode
/// played with its count and share.
struct ModeShare: View {
  var stats: NodeStats

  var body: some View {
    let rows = ACTIVITY_MODES.map { (mode: $0, rounds: stats.byMode[$0]?.rounds ?? 0) }.filter { $0.rounds > 0 }
    let total = rows.reduce(0) { $0 + $1.rounds }
    StatsSection(title: "Rounds by mode")
    StatsCard {
      if rows.isEmpty {
        Text("Nothing yet").font(.system(size: 13)).foregroundStyle(Theme.text3).frame(maxWidth: .infinity).padding(.vertical, 12)
      } else {
        VStack(alignment: .leading, spacing: 14) {
          GeometryReader { geo in
            HStack(spacing: 2) {
              ForEach(rows, id: \.mode) { row in
                modeColor(row.mode)
                  .frame(width: max(2, (geo.size.width - 2 * CGFloat(rows.count - 1)) * CGFloat(row.rounds) / CGFloat(total)))
              }
            }
          }
          .frame(height: 18)
          .clipShape(RoundedRectangle(cornerRadius: 6))
          .accessibilityHidden(true)
          VStack(spacing: 10) {
            ForEach(rows, id: \.mode) { row in
              HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 3).fill(modeColor(row.mode)).frame(width: 10, height: 10)
                Text(modeName(row.mode)).foregroundStyle(Theme.text2).frame(maxWidth: .infinity, alignment: .leading)
                Text("\(row.rounds)").fontWeight(.bold).foregroundStyle(Theme.text)
                Text(percentText(Double(row.rounds) / Double(total))).foregroundStyle(Theme.text3).frame(width: 48, alignment: .trailing)
              }
              .font(.system(size: 14).monospacedDigit())
            }
          }
        }
      }
    }
  }
}

/// Each mode's color in the tallies.
func modeColor(_ mode: ActivityMode) -> Color {
  switch mode {
  case .run: Theme.accent
  case .survival: Theme.warn
  case .drill: Theme.book
  case .growth: Theme.good
  case .repair: Theme.bad
  }
}
