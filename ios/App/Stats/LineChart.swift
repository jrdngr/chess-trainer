import Game
import Model
import Shared
import SwiftUI

/// One series over the days, with a crosshair the reader drags along it.
/// Drawn on a 320-wide grid, scaled to fit.
struct LineChart: View {
  var points: [DayPoint]
  var color: Color
  var height: CGFloat = 150
  /// Fix the top of the scale; otherwise the data decides.
  var max: Double?
  /// Ticks as percentages.
  var percent = false
  /// Faint single-day values behind a smoothed line.
  var dots: [DayPoint] = []
  /// Show the latest value under the chart while nobody is dragging; off
  /// when the card already says it.
  var restingReadout = true

  @State private var hover: Int?
  @State private var width: CGFloat = 320

  private static let W: CGFloat = 320
  private static let pad = (top: 10.0, right: 12.0, bottom: 22.0, left: 34.0)

  var body: some View {
    if points.isEmpty {
      Text("Nothing yet").font(.system(size: 13)).foregroundStyle(Theme.text3)
        .frame(maxWidth: .infinity).padding(.vertical, 28)
    } else {
      VStack(spacing: 4) {
        chart
        readout
      }
    }
  }

  private var scale: Scale { Scale(points: points, max: max, height: height) }

  private var chart: some View {
    let scale = self.scale
    return Canvas { context, size in
      let k = size.width / Self.W
      context.scaleBy(x: k, y: k)
      draw(&context, scale)
    }
    .aspectRatio(Self.W / height, contentMode: .fit)
    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    .contentShape(Rectangle())
    .simultaneousGesture(
      // Only a sideways drag reads the chart, so a swipe that starts on it still scrolls the page.
      DragGesture(minimumDistance: 8)
        .onChanged { drag in
          guard hover != nil || abs(drag.translation.width) > abs(drag.translation.height) else { return }
          hover = nearest(drag.location.x / width * Self.W, scale)
        }
        .onEnded { _ in hover = nil })
  }

  private func draw(_ context: inout GraphicsContext, _ scale: Scale) {
    let pad = Self.pad
    let right = Self.W - pad.right
    let bottom = pad.top + scale.plotH
    for tick in scale.ticks {
      let y = scale.y(tick)
      context.stroke(segment(pad.left, y, right, y), with: .color(Theme.surface3), lineWidth: 1)
      context.draw(tickText(label(tick)), at: CGPoint(x: pad.left - 6, y: y), anchor: .trailing)
    }
    let last = points[points.count - 1]
    if points.count > 1 {
      context.draw(tickText(dateLabel(points[0].at, scale.days)), at: CGPoint(x: pad.left, y: height - 9.5), anchor: .leading)
    }
    context.draw(tickText(dateLabel(last.at, scale.days)), at: CGPoint(x: right, y: height - 9.5), anchor: .trailing)

    var line = Path()
    for (i, p) in points.enumerated() {
      let at = CGPoint(x: scale.x(p.at), y: scale.y(p.value))
      if i == 0 { line.move(to: at) } else { line.addLine(to: at) }
    }
    var area = line
    area.addLine(to: CGPoint(x: scale.x(last.at), y: bottom))
    area.addLine(to: CGPoint(x: scale.x(points[0].at), y: bottom))
    area.closeSubpath()
    context.fill(area, with: .linearGradient(
      Gradient(colors: [color.opacity(0.28), color.opacity(0)]), startPoint: CGPoint(x: 0, y: pad.top), endPoint: CGPoint(x: 0, y: bottom)))
    for dot in dots where dot.at >= points[0].at && dot.at <= last.at {
      let at = CGPoint(x: scale.x(dot.at), y: scale.y(dot.value))
      context.fill(Path(ellipseIn: CGRect(x: at.x - 1.8, y: at.y - 1.8, width: 3.6, height: 3.6)), with: .color(color.opacity(0.35)))
    }
    context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
    marker(&context, CGPoint(x: scale.x(last.at), y: scale.y(last.value)), 4)
    if let hover, points.indices.contains(hover) {
      let p = points[hover]
      context.stroke(segment(scale.x(p.at), pad.top, scale.x(p.at), bottom), with: .color(Theme.text3), lineWidth: 1)
      marker(&context, CGPoint(x: scale.x(p.at), y: scale.y(p.value)), 5)
    }
  }

  private func marker(_ context: inout GraphicsContext, _ at: CGPoint, _ r: CGFloat) {
    let dot = Path(ellipseIn: CGRect(x: at.x - r, y: at.y - r, width: 2 * r, height: 2 * r))
    context.fill(dot, with: .color(color))
    context.stroke(dot, with: .color(Theme.surface), lineWidth: 2)
  }

  private func segment(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) -> Path {
    Path { p in
      p.move(to: CGPoint(x: x1, y: y1))
      p.addLine(to: CGPoint(x: x2, y: y2))
    }
  }

  private func tickText(_ s: String) -> Text {
    Text(s).font(.system(size: 10, weight: .medium).monospacedDigit()).foregroundStyle(Theme.text3)
  }

  private var readout: some View {
    let shown = hover.flatMap { points.indices.contains($0) ? points[$0] : nil }
    let point = shown ?? points[points.count - 1]
    return HStack(alignment: .firstTextBaseline) {
      Text(shown.map { shortDate($0.at) } ?? "Now").font(.system(size: 13)).foregroundStyle(Theme.text2)
      Spacer()
      Text(label(point.value)).font(.system(size: 15, weight: .bold).monospacedDigit()).foregroundStyle(Theme.text)
    }
    .padding(.horizontal, 2)
    .opacity(shown == nil && !restingReadout ? 0 : 1)
  }

  private func label(_ value: Double) -> String { percent ? percentText(value) : "\(Int(JSRound(value)))" }

  private func nearest(_ x: CGFloat, _ scale: Scale) -> Int {
    points.indices.min { abs(scale.x(points[$0].at) - x) < abs(scale.x(points[$1].at) - x) } ?? 0
  }

  private func dateLabel(_ at: Double, _ span: Int) -> String {
    span <= 14 ? Date(timeIntervalSince1970: at / 1000).formatted(.dateTime.weekday(.narrow)) : shortDate(at)
  }

  /// The chart's axes: `scale` in `LineChart`.
  struct Scale {
    var first: Double
    var span: Double
    var ceiling: Double
    var ticks: [Double]
    var plotH: CGFloat
    var days: Int

    init(points: [DayPoint], max: Double?, height: CGFloat) {
      let top = max ?? Swift.max(1, points.map(\.value).max() ?? 0)
      ticks = max != nil ? [0, top / 2, top] : niceTicks(top)
      ceiling = ticks.last.flatMap { $0 == 0 ? nil : $0 } ?? 1
      let last = points.last?.at ?? 1
      // A lone point is today's, so it sits at the right edge.
      first = points.count > 1 ? points[0].at : last - 1
      span = Swift.max(1, last - first)
      plotH = height - LineChart.pad.top - LineChart.pad.bottom
      days = Int(JSRound(span / 86_400_000)) + 1
    }

    func x(_ at: Double) -> CGFloat {
      LineChart.pad.left + CGFloat((at - first) / span) * (LineChart.W - LineChart.pad.left - LineChart.pad.right)
    }

    func y(_ value: Double) -> CGFloat { LineChart.pad.top + plotH - CGFloat(value / ceiling) * plotH }
  }
}
