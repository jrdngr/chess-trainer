import Game
import Model
import SwiftUI

/// Accuracy over the window: where it stands now and how far it moved, the
/// seven-day average as a line, and each day's own share as a faint dot.
struct AccuracySection: View {
  var stats: NodeStats
  var days: Int

  var body: some View {
    let line = rollingAccuracy(stats, days)
    StatsSection(title: "Accuracy")
    StatsCard {
      VStack(alignment: .leading, spacing: 10) {
        if let now = line.last {
          HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(percentText(now.value)).font(.system(size: 30, weight: .heavy).monospacedDigit()).foregroundStyle(Theme.text)
            Text("now").font(.system(size: 13)).foregroundStyle(Theme.text2)
            Spacer(minLength: 0)
            let pts = Int(JSRound((now.value - line[0].value) * 100))
            if line.count > 1, pts != 0 {
              StatsBadge(text: "\(pts > 0 ? "\u{25b2}" : "\u{25bc}") \(abs(pts)) pts in \(windowText(days))", good: pts > 0)
            }
          }
        }
        LineChart(points: line, color: Theme.good, max: 1, percent: true, dots: dailyAccuracy(stats, days), restingReadout: line.isEmpty)
      }
    }
  }
}
