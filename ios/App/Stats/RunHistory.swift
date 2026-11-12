import Model
import Shared
import SwiftUI

/// The last runs' moves survived as bars, the latest lit and the best in
/// gold, with lines at the best and the average. Over them, the last run and
/// how it sat against the average. Follows the selection; not bound to the
/// Stats window.
struct RunHistory: View {
  @Environment(AppStore.self) private var store

  var body: some View {
    let selection = store.state.settings.selection
    let score = runFor(store.state.runRecord, selection.opening)
    let runs = score.history
    StatsSection(title: "Play", aside: "last \(HISTORY_RUNS) runs")
    StatsCard {
      VStack(alignment: .leading, spacing: 12) {
        if let last = runs.last {
          header(last, Double(runs.reduce(0, +)) / Double(runs.count))
        }
        chart(runs, best: score.best)
      }
    }
  }

  private func header(_ last: Int, _ average: Double) -> some View {
    let diff = Double(last) - average
    return HStack(alignment: .firstTextBaseline, spacing: 10) {
      Text("\(last)").font(.system(size: 30, weight: .heavy).monospacedDigit()).foregroundStyle(Theme.text)
      Text(last == 1 ? "move last run" : "moves last run").font(.system(size: 13)).foregroundStyle(Theme.text2)
      Spacer(minLength: 0)
      if abs(diff) >= 0.5 {
        StatsBadge(text: "\(diff > 0 ? "\u{25b2}" : "\u{25bc}") \(oneDecimal(abs(diff))) \(diff > 0 ? "over" : "under") average", good: diff > 0)
      }
    }
  }

  private func chart(_ runs: [Int], best: Int) -> some View {
    let average = runs.isEmpty ? 0 : Double(runs.reduce(0, +)) / Double(runs.count)
    return Canvas { context, size in
      let w = size.width, base = size.height, top = 14.0
      let maxV = Double(max(10, best, runs.max() ?? 0)) * 1.12
      let y = { (v: Double) in base - (v / maxV) * (base - top) }
      let gap: CGFloat = 6
      let slot = (w + gap) / CGFloat(HISTORY_RUNS)
      let offset = HISTORY_RUNS - runs.count
      for i in 0..<HISTORY_RUNS {
        let x = CGFloat(i) * slot
        if i < offset {
          context.fill(Path(roundedRect: CGRect(x: x, y: base - 3, width: slot - gap, height: 3), cornerRadius: 1.5), with: .color(Theme.surface2))
          continue
        }
        let run = runs[i - offset]
        let bar = max(3, base - y(Double(run)))
        let color = i == HISTORY_RUNS - 1 ? Theme.accent : run == best ? Theme.warn : Theme.surface3
        context.fill(Path(roundedRect: CGRect(x: x, y: base - bar, width: slot - gap, height: bar), cornerRadius: 3), with: .color(color))
      }
      // The average is left out when it sits on the best line.
      if !runs.isEmpty, best == 0 || y(average) - y(Double(best)) > 12 {
        line(&context, y(average), w, Theme.text3, [1, 3], 1)
        context.draw(label("avg \(oneDecimal(average))", Theme.text2), at: CGPoint(x: 0, y: y(average) - 3), anchor: .bottomLeading)
      }
      if best > 0 {
        line(&context, y(Double(best)), w, Theme.warn, [3, 4], 1.5)
        context.draw(label("best \(best)", Theme.warn, bold: true), at: CGPoint(x: w, y: y(Double(best)) - 3), anchor: .bottomTrailing)
      }
    }
    .frame(height: 110)
  }

  private func line(_ context: inout GraphicsContext, _ y: CGFloat, _ w: CGFloat, _ color: Color, _ dash: [CGFloat], _ width: CGFloat) {
    var path = Path()
    path.move(to: CGPoint(x: 0, y: y))
    path.addLine(to: CGPoint(x: w, y: y))
    context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, dash: dash))
  }

  private func label(_ s: String, _ color: Color, bold: Bool = false) -> Text {
    Text(s).font(.system(size: 10, weight: bold ? .bold : .regular).monospacedDigit()).foregroundStyle(color)
  }
}

/// "14.5", "14": a number to one decimal place, without a trailing ".0".
func oneDecimal(_ v: Double) -> String {
  let r = JSRound(v * 10) / 10
  return r == r.rounded() ? "\(Int(r))" : String(format: "%.1f", r)
}
