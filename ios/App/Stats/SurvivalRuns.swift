import Model
import Shared
import SwiftUI

/// The last runs' moves survived as bars, the latest lit, a dashed line at
/// the best. Follows the selection; not bound to the Stats window.
struct SurvivalRuns: View {
  @Environment(AppStore.self) private var store

  var body: some View {
    let selection = store.state.settings.selection
    let score = survivalFor(store.state.survival, selection.opening == ANY_FAVORITE ? "" : selection.opening)
    let runs = score.history
    StatsSection(title: "Survival", aside: score.best > 0 ? "best \(score.best)" : nil)
    StatsCard {
      Canvas { context, size in
        let w = size.width, h = size.height
        let base = h - 14, top = 8.0
        let maxV = Double(max(10, score.best, runs.max() ?? 0)) * 1.1
        let y = { (v: Double) in base - (v / maxV) * (base - top) }
        let slot = (w - 8) / CGFloat(HISTORY_RUNS)
        let offset = HISTORY_RUNS - runs.count
        for i in 0..<HISTORY_RUNS {
          let x = 4 + CGFloat(i) * slot + 2
          if i < offset {
            context.fill(Path(roundedRect: CGRect(x: x, y: base - 3, width: slot - 4, height: 3), cornerRadius: 1.5), with: .color(Theme.surface2))
          } else {
            let bar = max(3, base - y(Double(runs[i - offset])))
            let last = i == HISTORY_RUNS - 1
            context.fill(Path(roundedRect: CGRect(x: x, y: base - bar, width: slot - 4, height: bar), cornerRadius: 3),
                         with: .color(last ? Theme.accent : Theme.surface3))
          }
        }
        if score.best > 0 {
          var line = Path()
          line.move(to: CGPoint(x: 4, y: y(Double(score.best))))
          line.addLine(to: CGPoint(x: w - 4, y: y(Double(score.best))))
          context.stroke(line, with: .color(Theme.warn), style: StrokeStyle(lineWidth: 1.5, dash: [3, 4]))
        }
        context.draw(Text("\(HISTORY_RUNS) runs ago").font(.system(size: 10)).foregroundStyle(Theme.text3), at: CGPoint(x: 4, y: h - 2), anchor: .bottomLeading)
        context.draw(Text("last").font(.system(size: 10)).foregroundStyle(Theme.text3), at: CGPoint(x: w - 4, y: h - 2), anchor: .bottomTrailing)
      }
      .aspectRatio(320 / 92, contentMode: .fit)
    }
  }
}
