import ChessCore
import Game
import Model
import SwiftUI

/// A form's color, from red through orange and amber to green.
func formColor(_ form: Double) -> SwiftUI.Color {
  if form < 0.4 { return Theme.bad }
  if form < 0.55 { return SwiftUI.Color(hex: 0xfb923c) }
  if form < CURVE_GREEN { return Theme.warn }
  return Theme.good
}

/// An opening's form as an arc that fills clockwise from the top; nothing while there is too little to tell.
struct FormArc: View {
  var form: Double?
  var lineWidth: CGFloat = 3

  var body: some View {
    if let form {
      ZStack {
        Circle().stroke(SwiftUI.Color.white.opacity(0.13), lineWidth: lineWidth)
        Circle().trim(from: 0, to: max(0.001, min(1, form)))
          .stroke(formColor(form), style: StrokeStyle(lineWidth: lineWidth, lineCap: form >= 1 ? .butt : .round))
          .rotationEffect(.degrees(-90))
      }
      .padding(lineWidth / 2)
    }
  }
}

/// Form as a ring on its own: the arc over an empty track, the track alone while
/// there is too little to tell; with `value`, the percent inside it.
struct FormRing: View {
  var form: Double?
  var size: CGFloat = 18
  var lineWidth: CGFloat = 2.5
  var value = false

  var body: some View {
    ZStack {
      if form != nil {
        FormArc(form: form, lineWidth: lineWidth)
      } else {
        Circle().stroke(SwiftUI.Color.white.opacity(0.13), lineWidth: lineWidth).padding(lineWidth / 2)
      }
      if value {
        Text(form.map { "\(Int(($0 * 100).rounded()))" } ?? "–")
          .font(.system(size: size * 0.28, weight: .heavy).monospacedDigit()).foregroundStyle(form == nil ? Theme.text3 : Theme.text)
      }
    }
    .frame(width: size, height: size)
    .accessibilityElement()
    .accessibilityLabel(form.map { "Form \(Int(($0 * 100).rounded())) percent" } ?? "No form yet")
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
