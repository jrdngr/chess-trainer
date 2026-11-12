import ChessCore
import Model
import SwiftUI

/// How far into your prep a run is, a segment for each of your moves.
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
          segment(i, count: count, prepCount: prepCount, lit: lit)
        }
      }
      .frame(height: height)
    }
  }

  @ViewBuilder private func segment(_ i: Int, count: Int, prepCount: Int, lit: Int) -> some View {
    let isBook = i >= prepCount
    let here = isBook ? i == count - 1 : i == lit
    let past = !isBook && i < lit
    let fill: SwiftUI.Color = isBook ? Theme.book : here ? SwiftUI.Color(hex: 0xf2f2f5) : past ? Theme.accent : SwiftUI.Color(hex: 0x3a3a48)
    RoundedRectangle(cornerRadius: 3)
      .fill(fill)
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
