import ChessCore
import Game
import Model
import SwiftUI

/// An opening's form as three signal bars in one color; three short dashes while there is too little to tell.
struct FormBars: View {
  var bars: Int?
  var scale: CGFloat = 1

  var body: some View {
    HStack(alignment: .bottom, spacing: 2.5 * scale) {
      ForEach(0..<3, id: \.self) { i in
        if let bars {
          RoundedRectangle(cornerRadius: 1.2 * scale)
            .fill(i < bars ? Theme.accent : SwiftUI.Color.white.opacity(0.13))
            .frame(width: 4 * scale, height: [6, 10, 14][i] * scale)
        } else {
          RoundedRectangle(cornerRadius: 1).fill(SwiftUI.Color(hex: 0x5e5e68))
            .frame(width: 4 * scale, height: max(2, 2 * scale))
        }
      }
    }
    .frame(height: 14 * scale, alignment: .bottom)
    .accessibilityElement()
    .accessibilityLabel(bars.map { "Form \($0) of 3" } ?? "No form yet")
  }
}

/// A side as a small dot.
struct SideDot: View {
  var side: ChessCore.Color
  var body: some View {
    Circle().fill(side == .w ? SwiftUI.Color(hex: 0xf2f2f4) : SwiftUI.Color(hex: 0x35353d))
      .overlay(Circle().strokeBorder(SwiftUI.Color(hex: 0x5a5a66), lineWidth: side == .w ? 0 : 1.5))
      .frame(width: 10, height: 10)
  }
}

/// A side as a small square: white, black, or split diagonally for Either. `ColorSquare`.
struct ColorSquare: View {
  var choice: ColorChoice
  var size: CGFloat = 18

  var body: some View {
    RoundedRectangle(cornerRadius: 5)
      .fill(choice == .b ? SwiftUI.Color.black : SwiftUI.Color(hex: 0xf2f2f4))
      .overlay {
        if choice == .either {
          Path { p in
            p.move(to: CGPoint(x: size, y: 0))
            p.addLine(to: CGPoint(x: size, y: size))
            p.addLine(to: CGPoint(x: 0, y: size))
          }
          .fill(SwiftUI.Color.black)
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: 5))
      .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.white.opacity(0.18), lineWidth: 1.5))
      .frame(width: size, height: size)
  }
}
