import ChessCore
import Engine
import Game
import Model
import SwiftUI

/// The Eval lens's bar, in the captured row's place over the board: White's share and the score.
struct EvalLensBar: View {
  /// The engine's last word, White's side; a mate reads as ±10000.
  var cp: Double?
  /// In an endgame, the result with best play from your side.
  var result: EndResult? = nil

  var body: some View {
    // The bar keeps the captured row's place; the result word leads it on the same line.
    HStack(spacing: 8) {
      if let result {
        Text(Self.word(result)).font(.system(size: 13, weight: .heavy))
          .foregroundStyle(result == .win ? Theme.good : result == .loss ? Theme.bad : Theme.text)
          .fixedSize()
      }
      PlayEvalBar(line: cp.map { cp in
        abs(cp) >= 10_000
          ? EngineLine(multipv: 1, depth: 0, cp: nil, mate: cp > 0 ? 1 : -1, pv: [])
          : EngineLine(multipv: 1, depth: 0, cp: cp, mate: nil, pv: [])
      })
    }
  }

  static func word(_ result: EndResult) -> String { result == .win ? "Win" : result == .loss ? "Loss" : "Draw" }
}

/// The Eval lens's card under the board: your last judged move and its swing, over the run's eval so far.
struct EvalRunCard: View {
  /// The engine's score before your first judged move and after each one, White's side.
  var trail: [Double]
  var last: JudgedMark?
  var color: ChessCore.Color

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline) {
        Text("THIS RUN").font(.system(size: 11, weight: .bold)).tracking(0.8).foregroundStyle(Theme.text2)
        Spacer()
        if let last {
          Text(last.san).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.text)
          if let swing = last.swing, let score = moveScore(swing) {
            Text(Self.pawns(score.cp)).font(.system(size: 13, weight: .bold).monospacedDigit())
              .foregroundStyle(score.tone == .up ? Theme.good : score.tone == .slight ? Theme.warn : Theme.bad)
          }
        }
      }
      EvalTrailChart(values: trail.map { color == .w ? $0 : -$0 })
        .frame(height: 64)
    }
    .padding(.horizontal, 14).padding(.vertical, 12)
    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
    .padding(.top, 12)
  }

  /// A swing in pawns, one decimal, signed: "+3.1", "−0.4".
  static func pawns(_ cp: Double) -> String {
    let text = String(format: "%.1f", abs(cp) / 100)
    return (cp < 0 ? "\u{2212}" : "+") + text
  }
}

/// The run's eval from your side as a line, the zero line dashed, the biggest swing and the latest point marked.
struct EvalTrailChart: View {
  var values: [Double]
  /// Past this, more pawns don't move the line: a mate or a piece up reads the same.
  static let cap: Double = 600

  var body: some View {
    Canvas { context, size in
      let clamped = values.map { min(Self.cap, max(-Self.cap, $0)) }
      let top = max(100, clamped.map(abs).max() ?? 0)
      let inset: CGFloat = 5
      let height = size.height - inset * 2
      func y(_ v: Double) -> CGFloat { inset + height / 2 - CGFloat(v / top) * height / 2 }
      func x(_ i: Int) -> CGFloat {
        clamped.count < 2 ? size.width / 2 : inset + CGFloat(i) / CGFloat(clamped.count - 1) * (size.width - inset * 2)
      }

      var zero = Path()
      zero.move(to: CGPoint(x: 0, y: y(0)))
      zero.addLine(to: CGPoint(x: size.width, y: y(0)))
      context.stroke(zero, with: .color(Theme.surface3), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
      guard !clamped.isEmpty else { return }

      var line = Path()
      for (i, v) in clamped.enumerated() {
        let point = CGPoint(x: x(i), y: y(v))
        if i == 0 { line.move(to: point) } else { line.addLine(to: point) }
      }
      context.stroke(line, with: .color(Theme.accent), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))

      func dot(_ i: Int, _ color: SwiftUI.Color, _ r: CGFloat) {
        let c = CGPoint(x: x(i), y: y(clamped[i]))
        context.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(color))
      }
      if clamped.count > 1 {
        let swings = (1..<clamped.count).map { (i: $0, by: clamped[$0] - clamped[$0 - 1]) }
        if let big = swings.max(by: { abs($0.by) < abs($1.by) }), abs(big.by) >= 100 {
          dot(big.i, big.by > 0 ? Theme.good : Theme.bad, 4)
        }
      }
      dot(clamped.count - 1, Theme.text, 3.5)
    }
    .accessibilityLabel("Eval across the run")
  }
}
