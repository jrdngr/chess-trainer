import ChessCore
import Model
import SwiftUI

/// Where the run's board sits, for Play's deal to grow its card onto.
struct BoardFrameKey: PreferenceKey {
  static var defaultValue: Anchor<CGRect>? { nil }
  static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
    value = value ?? nextValue()
  }
}

/// Play's round, announced: its card leaves the deck small and flips face up on
/// the round's start position, comes forward under the opening's name with the
/// prep below, then after a beat grows onto the board (`board`) as the
/// rest clears. Plays once, in `length`; a tap goes straight to the board.
struct RoundDeal: View {
  let name: String
  let fen: String
  let lastMove: (from: String, to: String)?
  let color: ChessCore.Color
  let span: PrepSpan?
  /// The run's board, in this view's space.
  let board: CGRect?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  /// How far the card has come from the deck, 0...1, small and face up at 1.
  @State private var dealt = 0.0
  @State private var forward = false
  @State private var named = false
  @State private var grown = false

  static let deal = 0.5, beat = 0.06, forwardTime = 0.54, hold = 0.45, grow = 0.4
  /// The whole announcement: `RunModel.start` waits this long before the board.
  static var length: Double { deal + beat + forwardTime + hold + grow }

  var body: some View {
    GeometryReader { geo in
      let side = min(264, geo.size.width - 126)
      let rest = CGRect(x: (geo.size.width - side) / 2, y: geo.size.height * 0.38 - side / 2, width: side, height: side)
      // The card is drawn at the board's own size and scaled down, so the board inside never relays out
      // (its coordinate labels would fade out and back in) as it grows.
      let full = board?.width ?? side - 24
      let scale = grown ? 1 : (side - 24) / full
      let center = grown ? CGPoint(x: board?.midX ?? rest.midX, y: board?.midY ?? rest.midY) : CGPoint(x: rest.midX, y: rest.midY)
      let inset: CGFloat = grown ? 0 : 12 / scale
      let deck = CGPoint(x: geo.size.width / 2, y: geo.size.height - 130)
      ZStack(alignment: .topLeading) {
        Theme.background.opacity(grown ? 0 : 1).ignoresSafeArea()
        Text(name)
          .font(.system(size: name.count > 20 ? 24 : 28, weight: .bold)).tracking(-0.4).foregroundStyle(Theme.text)
          .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
          .frame(width: geo.size.width - 48, height: 80, alignment: .bottom)
          .position(x: geo.size.width / 2, y: rest.minY - 62)
          .opacity(named && !grown ? 1 : 0).offset(y: named ? 0 : 8)
        PrepSegmentsView(span: span)
          .frame(width: side)
          .position(x: geo.size.width / 2, y: rest.maxY + 30)
          .opacity(named && !grown ? 1 : 0).offset(y: named ? 0 : 8)
        ZStack {
          ForEach([-6.0, -3, 0], id: \.self) { o in
            WelcomeCardBack(radius: 12).frame(width: 106, height: 115).offset(x: o, y: -o)
          }
        }
        .position(deck)
        .opacity(grown ? 0 : 1)
        card(size: full, inset: inset, scale: scale)
          .modifier(DealFlip(progress: dealt, radius: 29 / scale))
          .frame(width: full + 2 * inset, height: full + 2 * inset)
          .scaleEffect(scale * (forward ? 1 : 0.4 + 0.2 * dealt))
          .offset(x: (deck.x - rest.midX) * (1 - dealt), y: (deck.y - rest.midY) * (1 - dealt))
          .position(center)
      }
      .frame(width: geo.size.width, height: geo.size.height)
    }
    .task { await play() }
  }

  /// The card: the round's position in the card's frame, the frame and its accent gone once it is the board.
  /// Sizes are in the board's own units, so each is divided by `scale` to look right once scaled down.
  private func card(size: CGFloat, inset: CGFloat, scale: CGFloat) -> some View {
    BoardView(fen: fen, orientation: color, interactive: false, lastMove: lastMove, onMove: { _ in })
      .frame(width: size, height: size)
      .padding(inset)
      .background(RoundedRectangle(cornerRadius: grown ? 4 : 29 / scale).fill(Theme.surface.opacity(grown ? 0 : 1)))
      .overlay(RoundedRectangle(cornerRadius: grown ? 4 : 29 / scale).strokeBorder(Theme.accent.opacity(grown ? 0 : 1), lineWidth: 1.5 / scale))
      .shadow(color: .black.opacity(grown ? 0 : 0.55), radius: 17 / scale, y: 14 / scale)
  }

  private func play() async {
    if reduceMotion {
      dealt = 1
      forward = true
      named = true
    } else {
      withAnimation(.timingCurve(0.5, 0, 0.2, 1, duration: Self.deal)) { dealt = 1 }
      withAnimation(.easeOut(duration: 0.35).delay(Self.deal + 0.12)) { named = true }
    }
    try? await Task.sleep(for: .seconds(Self.deal + Self.beat))
    if !reduceMotion {
      withAnimation(.timingCurve(0.5, 0, 0.2, 1, duration: Self.forwardTime)) { forward = true }
    }
    try? await Task.sleep(for: .seconds(Self.forwardTime + Self.hold))
    guard !Task.isCancelled else { return }
    withAnimation(reduceMotion ? .easeOut(duration: Self.grow) : .easeInOut(duration: Self.grow)) { grown = true }
  }
}

/// The card turning over on its way from the deck: face down at 0, face up at 1.
private struct DealFlip: ViewModifier, Animatable {
  var progress: Double
  var radius: CGFloat

  nonisolated var animatableData: Double {
    get { progress }
    set { progress = newValue }
  }

  func body(content: Content) -> some View {
    let flip = 180 * (1 - progress)
    ZStack {
      if flip < 90 {
        content
      } else {
        // Seen through the flip, so mirrored back to read the right way round.
        WelcomeCardBack(radius: radius).scaleEffect(x: -1)
      }
    }
    .rotation3DEffect(.degrees(flip), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
  }
}
