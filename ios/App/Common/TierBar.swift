import ChessCore
import Model
import SwiftUI

/// A rating's tier as a thin bar in the tier's color, with its name over it unless `label` is off.
struct TierBar: View {
  var rating: Double
  var rated: Int
  var label = true

  var body: some View {
    let rank = rankOf(rating, rated)
    GeometryReader { geo in
      ZStack(alignment: .leading) {
        Capsule().fill(Theme.surface3)
        if rated > 0 {
          paint(rating).frame(width: geo.size.width)
            .mask(alignment: .leading) { Capsule().frame(width: geo.size.width * rank.progress) }
            .shadow(color: fillColor(rating).opacity(0.7), radius: 3)
        }
      }
      .overlay {
        if label {
        Text(rated == 0 ? NEW_LABEL : rank.heldLabel).font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.text)
          .shadow(color: .black, radius: 1.5)
          .shadow(color: .black, radius: 2.5)
          .shadow(color: .black.opacity(0.8), radius: 4)
          .shadow(color: .black, radius: 1, y: 1)
          .fixedSize()
        }
      }
    }
    .frame(height: 5).padding(.vertical, 6)
  }
}

/// The fill's paint, laid along the whole track: the tier's colour, leaning
/// toward the next tier's from halfway, never all the way there. `paintFor`.
func paint(_ rating: Double) -> LinearGradient {
  let rank = rankOf(rating)
  let own = fillColor(rating)
  guard rank.held != nil, let next = rank.next else { return LinearGradient(colors: [own, own], startPoint: .leading, endPoint: .trailing) }
  let ownHex = (rank.held ?? rank.next ?? UNRATED).color
  return LinearGradient(
    stops: [
      .init(color: own, location: 0.5),
      .init(color: SwiftUI.Color(hexString: mixHex(ownHex, next.color, 0.2)), location: 0.75),
      .init(color: SwiftUI.Color(hexString: mixHex(ownHex, next.color, 0.9)), location: 1),
    ], startPoint: .leading, endPoint: .trailing)
}

/// Two hex colours mixed, `amount` of the way from `a` to `b`.
func mixHex(_ a: String, _ b: String, _ amount: Double) -> String {
  let channels = { (hex: String) in [1, 3, 5].map { Int(hex.dropFirst($0).prefix(2), radix: 16) ?? 0 } }
  let (x, y) = (channels(a), channels(b))
  return "#" + zip(x, y).map { String(format: "%02x", Int(JSRound(Double($0) + Double($1 - $0) * amount))) }.joined()
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
