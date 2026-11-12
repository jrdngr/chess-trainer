import Game
import Model
import SwiftUI

/// Weeks the activity grid shows.
private let GRID_WEEKS = 18

/// The heatmap's five shades, none to busiest.
private let HEAT = [0x1f1f26, 0x2f3170, 0x4d50b8, 0x7174ee, 0xa5a7ff].map { Color(hex: $0) }

/// The top of the page: the window's switch, rounds in the window, the streak,
/// and every day of the last eighteen weeks as a square, a week to a column.
struct ActivityHero: View {
  var stats: NodeStats
  @Binding var days: Int

  var body: some View {
    let rounds = recentRounds(stats, days)
    let run = streak(stats)
    VStack(alignment: .leading, spacing: 16) {
      SegmentedControl(value: $days, options: STATS_WINDOWS)
      HStack(alignment: .bottom) {
        VStack(alignment: .leading, spacing: 2) {
          Text("\(rounds)").font(.system(size: 56, weight: .heavy).monospacedDigit()).tracking(-2).foregroundStyle(Theme.text)
            .frame(height: 56)
          Text("\(rounds == 1 ? "round" : "rounds") in \(windowText(days))").font(.system(size: 15)).foregroundStyle(Theme.text2)
        }
        Spacer()
        if run > 0 {
          VStack(alignment: .trailing, spacing: 2) {
            HStack(spacing: 6) {
              Icon(name: "flame", size: 18)
              Text("\(run)").font(.system(size: 22, weight: .heavy).monospacedDigit())
            }
            .foregroundStyle(Theme.warn)
            Text("day streak").font(.system(size: 13)).foregroundStyle(Theme.text2)
          }
        }
      }
      grid
    }
    .padding(20)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 22).fill(Theme.surface))
  }

  private var grid: some View {
    let cells = activityGrid(stats, weeks: GRID_WEEKS)
    let top = cells.map(\.value).max() ?? 0
    return Canvas { context, size in
      let gap: CGFloat = 3
      let side = (size.width - gap * CGFloat(GRID_WEEKS - 1)) / CGFloat(GRID_WEEKS)
      for (i, cell) in cells.enumerated() {
        let rect = CGRect(x: CGFloat(i / 7) * (side + gap), y: CGFloat(i % 7) * (side + gap), width: side, height: side)
        context.fill(Path(roundedRect: rect, cornerRadius: side / 4), with: .color(HEAT[heatLevel(cell.value, top)]))
      }
    }
    .aspectRatio(CGFloat(GRID_WEEKS) / 7, contentMode: .fit)
    .accessibilityLabel("Rounds a day over the last \(GRID_WEEKS) weeks")
  }
}

/// "30 days", "90 days", "a year": the window in a sentence.
func windowText(_ days: Int) -> String { days >= 365 ? "a year" : "\(days) days" }
