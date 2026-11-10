import SwiftUI

/// A rim around the board saying what is going on: autoplay, your prep, a
/// moment to find. A label hangs from the rim's bottom edge as a tab grown
/// out of it, clear of the squares.
struct BoardRim: View {
  var color: Color
  var label: String?
  /// How far the label hangs below the board: tips hung from the board clear it by this much.
  static let labelDrop: CGFloat = 34

  var body: some View {
    GeometryReader { geo in
      // Just outside the board, clear of the coordinates on its edge squares.
      RoundedRectangle(cornerRadius: geo.size.width * 0.03 + 4)
        .strokeBorder(color, lineWidth: 3)
        .padding(-4)
        .shadow(color: color.opacity(0.6), radius: 10)
    }
    .overlay(alignment: .bottom) {
      if let label {
        // Hung from a line of no height at the board's bottom edge, so it falls below the board.
        Color.clear.frame(height: 0).overlay(alignment: .top) {
          Text(label)
            .font(.system(size: 15, weight: .bold)).foregroundStyle(Self.ink(color)).lineLimit(1).fixedSize()
            .padding(.horizontal, 16 + RimTab.fillet).padding(.top, 9).padding(.bottom, 7)
            .background(RimTab().fill(color).shadow(color: color.opacity(0.35), radius: 7, y: 4))
            // Its top sits inside the rim's stroke, so the two read as one piece.
            .offset(y: 1)
        }
      }
    }
    .allowsHitTesting(false)
  }

  /// Dark text in the rim's own hue.
  private static func ink(_ color: Color) -> Color {
    if color == Theme.accent { return Theme.accentInk }
    if color == Theme.good { return Color(hex: 0x06210f) }
    return Color(hex: 0x1a1405)
  }
}

/// The label's tab: a flat top joined to the rim with a concave curve each
/// side, and rounded bottom corners.
struct RimTab: Shape {
  static let fillet: CGFloat = 8
  static let corner: CGFloat = 10

  func path(in rect: CGRect) -> Path {
    let f = Self.fillet, c = Self.corner
    let left = rect.minX + f, right = rect.maxX - f
    var path = Path()
    path.move(to: CGPoint(x: rect.minX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
    path.addQuadCurve(to: CGPoint(x: right, y: rect.minY + f), control: CGPoint(x: right, y: rect.minY))
    path.addLine(to: CGPoint(x: right, y: rect.maxY - c))
    path.addQuadCurve(to: CGPoint(x: right - c, y: rect.maxY), control: CGPoint(x: right, y: rect.maxY))
    path.addLine(to: CGPoint(x: left + c, y: rect.maxY))
    path.addQuadCurve(to: CGPoint(x: left, y: rect.maxY - c), control: CGPoint(x: left, y: rect.maxY))
    path.addLine(to: CGPoint(x: left, y: rect.minY + f))
    path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY), control: CGPoint(x: left, y: rect.minY))
    path.closeSubpath()
    return path
  }
}

/// A big word over the board for a moment: Prep complete, Off prep, Found it,
/// Missed it, how a game ended.
struct BoardCallout: View {
  var text: String
  var tone: Color
  var symbol: String

  init(text: String, good: Bool) {
    self.init(text: text, tone: good ? Theme.good : Theme.bad, symbol: good ? "checkmark" : "xmark")
  }

  init(text: String, tone: Color, symbol: String) {
    self.text = text
    self.tone = tone
    self.symbol = symbol
  }

  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: symbol)
        .font(.system(size: 26, weight: .heavy)).foregroundStyle(Theme.background)
        .frame(width: 56, height: 56).background(Circle().fill(tone))
      Text(text).font(.system(size: 28, weight: .heavy)).tracking(-0.4).foregroundStyle(tone).lineLimit(1).minimumScaleFactor(0.6)
    }
    .padding(.vertical, 22).padding(.horizontal, 34)
    .background(RoundedRectangle(cornerRadius: 22).fill(Theme.surface.opacity(0.94)))
    .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(tone, lineWidth: 2))
    .shadow(color: .black.opacity(0.55), radius: 20, y: 16)
    .shadow(color: tone.opacity(0.33), radius: 15)
    .allowsHitTesting(false)
  }
}

/// Whose move, under a screen's title: the side's dot (a spinner while the
/// engine works), the words, and the combo when there is one.
struct StatusLine: View {
  /// White's dot when true, Black's when false.
  var white: Bool
  var text: String
  var busy = false
  var combo: Int?

  var body: some View {
    HStack(spacing: 6) {
      if busy {
        ProgressView().controlSize(.mini)
      } else {
        Circle().fill(white ? Color.white : Color.black).frame(width: 9, height: 9).overlay(Circle().stroke(Theme.text3))
      }
      Text(text).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text2)
      if let combo, combo > 1 {
        Text("\u{00d7}\(combo)").font(.system(size: 13, weight: .heavy).monospacedDigit()).foregroundStyle(Theme.good)
      }
    }
    .lineLimit(1)
    .frame(height: 16)
  }
}
