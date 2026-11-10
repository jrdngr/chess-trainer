import SwiftUI

/// A rim around the board, in the color of what is going on: replay, your
/// prep, a moment to find, adding moves. The status line under the title says which.
struct BoardRim: View {
  var color: Color

  var body: some View {
    GeometryReader { geo in
      let corner = geo.size.width * 0.03
      // Just outside the board, clear of the coordinates on its edge squares.
      RoundedRectangle(cornerRadius: corner + 4)
        .strokeBorder(color, lineWidth: 3)
        .padding(-4)
        .shadow(color: color.opacity(0.6), radius: 10)
        // The glow spreads outward only: none of it lies over the edge squares.
        .mask {
          Path { path in
            path.addRect(CGRect(origin: .zero, size: geo.size).insetBy(dx: -40, dy: -40))
            path.addRoundedRect(
              in: CGRect(origin: .zero, size: geo.size).insetBy(dx: -1, dy: -1),
              cornerSize: CGSize(width: corner + 1, height: corner + 1))
          }
          .fill(style: FillStyle(eoFill: true))
        }
    }
    .allowsHitTesting(false)
  }
}

/// A word under the board for a moment, in the lenses' place: Prep complete,
/// Off prep, Found it, Missed it, how a game ended.
struct CalloutStrip: View {
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
    HStack(spacing: 10) {
      Image(systemName: symbol)
        .font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.background)
        .frame(width: 26, height: 26).background(Circle().fill(tone))
      Text(text).font(.system(size: 20, weight: .heavy)).tracking(-0.2).foregroundStyle(tone).lineLimit(1).minimumScaleFactor(0.6)
    }
    .frame(maxWidth: .infinity).frame(height: 46)
    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(tone, lineWidth: 1.5))
    .shadow(color: tone.opacity(0.2), radius: 7)
    .allowsHitTesting(false)
  }
}

/// Whose move, under a screen's title: the side's dot (a spinner while the
/// engine works), the words, and the combo when there is one. While the board
/// has a rim the words name it, in the rim's color.
struct StatusLine: View {
  /// White's dot when true, Black's when false.
  var white: Bool
  var text: String
  var busy = false
  var combo: Int?
  var tone: Color = Theme.text2

  var body: some View {
    HStack(spacing: 6) {
      if busy {
        ProgressView().controlSize(.mini)
      } else {
        Circle().fill(white ? Color.white : Color.black).frame(width: 9, height: 9).overlay(Circle().stroke(Theme.text3))
      }
      Text(text).font(.system(size: 13, weight: .semibold)).foregroundStyle(tone)
      if let combo, combo > 1 {
        Text("\u{00d7}\(combo)").font(.system(size: 13, weight: .heavy).monospacedDigit()).foregroundStyle(Theme.good)
      }
    }
    .lineLimit(1)
    .frame(height: 16)
  }
}
