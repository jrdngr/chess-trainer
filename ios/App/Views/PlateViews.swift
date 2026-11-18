import ChessCore
import Game
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

/// Past your prep, in the prep bar's place: a gold step for each of your moves toward the next
/// distance marker, and the pawn its pawns pop out of, brighter with each step.
struct MarkerBar: View {
  let moves: Int
  var height: CGFloat = 5
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var paid = 0

  var body: some View {
    HStack(spacing: 6) {
      HStack(spacing: 3) {
        ForEach(0..<DISTANCE_EVERY, id: \.self) { i in
          RoundedRectangle(cornerRadius: 3).fill(i < moves ? Theme.pawn : SwiftUI.Color(hex: 0x3a3a48))
        }
      }
      .frame(height: height)
      .animation(.easeOut(duration: 0.2), value: moves)
      PawnCoin(stroked: false, size: 13, fill: Theme.pawn)
        .opacity(0.35 + 0.13 * Double(moves))
        .keyframeAnimator(initialValue: 1.0, trigger: paid) { view, scale in view.scaleEffect(scale) } keyframes: { _ in
          CubicKeyframe(reduceMotion ? 1 : 1.35, duration: 0.12)
          CubicKeyframe(1, duration: 0.18)
        }
        .frame(width: 28, alignment: .leading)
        .pawnSpot("marker")
    }
    .onChange(of: moves) { old, new in if new < old { paid += 1 } }
    .accessibilityElement()
    .accessibilityLabel("\(DISTANCE_EVERY - moves) moves to the next pawns")
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
