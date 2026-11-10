import ChessCore
import Model
import SwiftUI

/// The first screen a new profile sees: the app's name, then a deck of opening
/// cards dealt into a fan once, then Get started.
struct WelcomeView: View {
  let onStart: () -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  /// How far each fan card has come from the deck, 0...1, by its place in `Self.fan`.
  @State private var dealt: [Double] = Array(repeating: 0, count: Self.fan.count)

  /// The fan, left to right: an opening, the side it's seen from, and its tilt.
  private static let fan: [(sans: [String], color: ChessCore.Color, tilt: Double)] = [
    (["e4", "e6", "d4", "d5"], .b, -26),
    (["d4", "d5", "c4"], .w, -13),
    (["e4", "e5", "Nf3", "Nc6", "Bc4"], .w, 0),
    (["e4", "c5", "Nf3", "d6", "d4"], .b, 13),
    (["d4", "Nf6", "c4", "g6", "Nc3", "Bg7"], .w, 26),
  ]
  /// The order the cards leave the deck: the outside ones first, the middle one last and on top.
  private static let dealOrder = [0, 4, 1, 3, 2]
  /// The table the cards are dealt on, in points before it is scaled to fit.
  private static let table = CGSize(width: 390, height: 490)

  var body: some View {
    VStack(spacing: 0) {
      VStack(spacing: 6) {
        Text("Chess Playbook").font(.system(size: 36, weight: .heavy)).tracking(-1.1).foregroundStyle(Theme.text)
        Text("Flash cards you play").font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.text2)
      }
      .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.top, 12)
      GeometryReader { geo in
        let scale = min(1, geo.size.height / Self.table.height)
        tableView
          .frame(width: Self.table.width, height: Self.table.height)
          .scaleEffect(scale, anchor: .top)
          .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
      }
      .padding(.top, 36)
      BigButton(label: "Get started", action: onStart).padding(.horizontal, 20).padding(.bottom, 16)
    }
    .background(Theme.background.ignoresSafeArea())
    .onAppear(perform: deal)
  }

  /// The deck, and the fan dealt from it.
  private var tableView: some View {
    ZStack(alignment: .topLeading) {
      ForEach([-6.0, -3, 0], id: \.self) { o in
        WelcomeCardBack(radius: 12)
          .frame(width: 100, height: 109)
          .position(x: Self.table.width / 2 + o, y: Self.deckY - o)
      }
      ForEach(Self.dealOrder, id: \.self) { i in
        let card = Self.fan[i]
        DealtCard(progress: dealt[i], tilt: card.tilt, deckDrop: Self.deckY - Self.fanY) {
          WelcomeCardFace(sans: card.sans, color: card.color, chosen: card.tilt == 0, shade: abs(card.tilt) > 20 ? 0.38 : abs(card.tilt) > 10 ? 0.2 : 0)
        }
        .position(x: Self.table.width / 2, y: Self.fanY)
      }
    }
  }

  /// Where the middle card of the fan sits, and the deck, down the table.
  private static let fanY: CGFloat = 109
  private static let deckY: CGFloat = 435

  /// Deal once: each card leaves the deck in turn, flipping face up on the way.
  private func deal() {
    guard dealt.allSatisfy({ $0 == 0 }) else { return }
    if reduceMotion {
      dealt = Array(repeating: 1, count: Self.fan.count)
      return
    }
    for (n, i) in Self.dealOrder.enumerated() {
      withAnimation(.timingCurve(0.5, 0, 0.2, 1, duration: 0.9).delay(0.35 + Double(n) * 0.13)) { dealt[i] = 1 }
    }
  }
}

/// A card on its way from the deck to its place in the fan: at 0 it lies face
/// down on the deck at half size, at 1 it stands face up, tilted, on the arc.
private struct DealtCard<Face: View>: View, Animatable {
  var progress: Double
  var tilt: Double
  /// How far below the fan the deck is.
  var deckDrop: CGFloat
  @ViewBuilder var face: () -> Face

  nonisolated var animatableData: Double {
    get { progress }
    set { progress = newValue }
  }

  /// The fan's radius: the cards stand on an arc around a point this far below the middle card.
  private static var radius: Double { 400 }

  var body: some View {
    let p = progress
    let angle = tilt * .pi / 180
    let dx = Self.radius * sin(angle), dy = Self.radius * (1 - cos(angle))
    let flip = 180 * (1 - p)
    ZStack {
      if flip < 90 {
        face()
      } else {
        // Seen through the flip, so mirrored back to read the right way round.
        WelcomeCardBack(radius: 22).scaleEffect(x: -1)
      }
    }
    .frame(width: 200, height: 218)
    .rotation3DEffect(.degrees(flip), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
    .scaleEffect(0.5 + 0.5 * p)
    .rotationEffect(.degrees(tilt * p))
    .offset(x: dx * p, y: deckDrop * (1 - p) + dy * p)
  }
}

/// An opening card face up: its position, and the bar its name would sit on.
private struct WelcomeCardFace: View {
  var sans: [String]
  var color: ChessCore.Color
  /// The middle card, outlined in the accent.
  var chosen: Bool
  /// How much darker it sits, further out in the fan.
  var shade: Double

  var body: some View {
    VStack(alignment: .leading, spacing: 11) {
      MiniBoard(sans: sans, orientation: color, size: 182, lastMove: true).clipShape(RoundedRectangle(cornerRadius: 13))
      RoundedRectangle(cornerRadius: 3).fill(Theme.surface3).frame(width: 102, height: 7).padding(.leading, 4)
    }
    .padding(.horizontal, 9).padding(.top, 9).padding(.bottom, 11)
    .frame(width: 200, height: 218, alignment: .top)
    .background(RoundedRectangle(cornerRadius: 22).fill(Theme.surface))
    .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(chosen ? Theme.accent : Theme.surface2, lineWidth: chosen ? 1.5 : 1))
    .overlay(RoundedRectangle(cornerRadius: 22).fill(.black.opacity(shade)))
    .shadow(color: .black.opacity(0.55), radius: 17, y: 14)
  }
}

/// The back of a card: the book's blue, a dark rim line and a knight. Play's round deal uses it too.
struct WelcomeCardBack: View {
  var radius: CGFloat

  var body: some View {
    GeometryReader { geo in
      let inset = geo.size.width * 0.03
      ZStack {
        RoundedRectangle(cornerRadius: radius).fill(Theme.book)
        RoundedRectangle(cornerRadius: max(2, radius - inset)).strokeBorder(Theme.accentInk, lineWidth: max(1, geo.size.width * 0.0075))
          .padding(inset)
        SVGPath(d: PieceShapes.n).fill(Theme.accentInk)
          .frame(width: geo.size.width * 0.46, height: geo.size.width * 0.46)
      }
    }
    .shadow(color: .black.opacity(0.5), radius: 10, y: 8)
  }
}
