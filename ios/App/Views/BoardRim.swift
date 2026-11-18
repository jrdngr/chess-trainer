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

/// A word under the board for a moment, in the lenses' place:
/// Off prep, Found it, a missed chance, how a game ended.
struct CalloutStrip: View {
  var text: String
  var tone: Color
  var symbol: String

  init(text: String, good: Bool) {
    self.init(text: text, tone: good ? Theme.good : Theme.bad, symbol: good ? "checkmark" : "xmark")
  }

  /// A chance you missed: the game goes on.
  static func missed(_ text: String) -> CalloutStrip { CalloutStrip(text: text, tone: Theme.missed, symbol: "exclamationmark") }

  init(text: String, tone: Color, symbol: String) {
    self.text = text
    self.tone = tone
    self.symbol = symbol
  }

  /// A plain dark bar: the tone only on a small icon tile, the words white.
  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: symbol)
        .font(.system(size: 11, weight: .heavy)).foregroundStyle(tone)
        .frame(width: 24, height: 24).background(RoundedRectangle(cornerRadius: 7).fill(tone.opacity(0.18)))
      Text(text).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.7)
    }
    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).frame(height: 46)
    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
    .allowsHitTesting(false)
  }
}

/// Whose move, under a screen's title: the side's dot (a spinner while the
/// engine works) and the words. While the board
/// has a rim the words name it, in the rim's color.
struct StatusLine: View {
  /// White's dot when true, Black's when false.
  var white: Bool
  var text: String
  var busy = false
  var tone: Color = Theme.text2

  var body: some View {
    HStack(spacing: 6) {
      if busy {
        ProgressView().controlSize(.mini)
      } else {
        Circle().fill(white ? Color.white : Color.black).frame(width: 9, height: 9).overlay(Circle().stroke(Theme.text3))
      }
      Text(text).font(.system(size: 13, weight: .semibold)).foregroundStyle(tone)
    }
    .lineLimit(1)
    .frame(height: 16)
  }
}
