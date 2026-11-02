import ChessCore
import Model
import SwiftUI

/// How far into your prep a run is, a segment a ply.
struct PrepSegmentsView: View {
  let span: PrepSpan?
  var height: CGFloat = 5

  /// The most segments the track is cut into; a longer prep is shown to scale.
  static let maxSegments = 16

  var body: some View {
    if let span, span.total + (span.book ?? 0) > 0 {
      let book = span.book ?? 0
      let all = span.total + book
      let count = min(all, Self.maxSegments)
      let prepCount = book > 0 ? Int(JSRound(Double(span.total) / Double(all) * Double(count))) : count
      let lit = book > 0 ? prepCount : Int(JSRound(Double(min(span.played, span.total)) / Double(span.total) * Double(count)))
      HStack(spacing: 3) {
        ForEach(0..<count, id: \.self) { i in
          segment(i, count: count, prepCount: prepCount, lit: lit, span: span)
        }
      }
      .frame(height: height)
    }
  }

  @ViewBuilder private func segment(_ i: Int, count: Int, prepCount: Int, lit: Int, span: PrepSpan) -> some View {
    let isBook = i >= prepCount
    let here = isBook ? i == count - 1 : i == lit
    let past = !isBook && i < lit
    // A segment holding any ply past where the prep leaves the book is drawn outlined.
    let ext = !isBook && span.ext != nil && Double((i + 1) * span.total) / Double(prepCount) > Double(span.ext!)
    let fill: SwiftUI.Color = isBook ? Theme.book : here ? SwiftUI.Color(hex: 0xf2f2f5) : past ? Theme.accent : SwiftUI.Color(hex: 0x3a3a48)
    RoundedRectangle(cornerRadius: 3)
      .fill(ext ? (past ? Theme.accent.opacity(0.35) : .clear) : fill)
      .overlay(RoundedRectangle(cornerRadius: 3).stroke(ext ? (here ? SwiftUI.Color(hex: 0xf2f2f5) : Theme.accent) : .clear, lineWidth: 1.5))
      .shadow(color: here ? (isBook ? Theme.book : Theme.accent).opacity(0.9) : .clear, radius: 4)
  }
}

/// The side you play, as a small square.
struct SideSquare: View {
  let color: ChessCore.Color
  var size: CGFloat = 14
  var body: some View {
    RoundedRectangle(cornerRadius: 3)
      .fill(color == .w ? SwiftUI.Color(hex: 0xf2f2f5) : SwiftUI.Color(hex: 0x1a1a1f))
      .overlay(RoundedRectangle(cornerRadius: 3).stroke(color == .w ? .clear : SwiftUI.Color(hex: 0x6b6b78), lineWidth: 1.5))
      .frame(width: size, height: size)
  }
}

/// Autopilot's round as its intro announces it: the opening's position faded
/// in behind its name, and how far into your prep the run starts along the bottom.
struct IntroPlate: View {
  let name: String
  let sans: [String]
  let color: ChessCore.Color
  let span: PrepSpan?

  var body: some View {
    VStack(spacing: 0) {
      ZStack {
        BoardView(fen: walkSan(sans).fens.last!, orientation: color, interactive: false, lastMove: lastMoveOf(sans), coordinates: false, onMove: { _ in })
          .frame(width: 300, height: 300)
          .opacity(0.3)
          .mask(RadialGradient(colors: [.black, .clear], center: .center, startRadius: 60, endRadius: 150))
        HStack(alignment: .top, spacing: 10) {
          SideSquare(color: color).padding(.top, 8)
          Text(name).font(.system(size: name.count > 20 ? 24 : 28, weight: .bold)).foregroundStyle(Theme.text)
        }
        .padding(.horizontal, 24)
      }
      .frame(maxWidth: 380)
      .frame(height: 210)
      .clipped()
      .background(Theme.surface)
      .overlay(alignment: .bottom) { PrepSegmentsView(span: span).padding(.horizontal, 18) }
      .clipShape(RoundedRectangle(cornerRadius: 22))
    }
  }
}
