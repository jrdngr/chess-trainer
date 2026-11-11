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

/// What a round's card shows: its opening, start position, side and prep.
struct RoundCard {
  let name: String
  let fen: String
  let lastMove: (from: String, to: String)?
  let color: ChessCore.Color
  let span: PrepSpan?
}

extension RunModel {
  /// This round's card, as the deal shows it.
  var card: RoundCard {
    RoundCard(
      name: lineName(tree, pickerCatalog(tree), nodeById(tree, introOpening).sans),
      fen: run.fen, lastMove: lastMoveOf(run.played), color: run.color, span: span)
  }
}

/// Play's round, announced: its card leaves the deck small and flips face up on
/// the round's start position, comes forward under the opening's name with the
/// prep below, then after a beat grows onto the board (`board`) as the
/// rest clears. Plays once, in `length`; a tap goes straight to the board.
///
/// With `draw`, the deck waits under a finished run instead: a tap deals the next
/// round's card, or a finger pulls it out along the same path, turning it over as it
/// comes. Let go before its face shows and it goes back; once the face shows, the rest
/// plays by itself and `onDone` follows, as does a tap while it plays.
struct RoundDeal: View {
  /// The card dealt; with `draw`, the one drawn comes from it instead.
  var card: RoundCard?
  /// The run's board, in this view's space.
  let board: CGRect?
  /// The next round's card, taken when the deck is first touched; nil when there is none.
  var draw: (() -> RoundCard?)? = nil
  var onDone: (() -> Void)? = nil
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  /// How far the card has come from the deck, 0...1, small and face up at 1.
  @State private var dealt = 0.0
  @State private var forward = false
  @State private var named = false
  @State private var grown = false
  @State private var drawn: RoundCard?
  /// The drawn card's face has shown: the rest plays by itself.
  @State private var committed = false
  @State private var over = false
  @State private var playing: Task<Void, Never>?

  static let deal = 0.5, beat = 0.06, forwardTime = 0.54, hold = 0.45, grow = 0.4
  /// The whole announcement: `RunModel.start` waits this long before the board.
  static var length: Double { deal + beat + forwardTime + hold + grow }
  private static var dealCurve: Animation { .timingCurve(0.5, 0, 0.2, 1, duration: deal) }

  private var shown: RoundCard? { draw == nil ? card : drawn }

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
      // Drawn by hand, the finished run shows until the card comes out.
      let cover = grown ? 0 : draw == nil ? 1 : min(1, dealt * 1.15)
      ZStack(alignment: .topLeading) {
        Theme.background.opacity(cover).ignoresSafeArea()
          .allowsHitTesting(false)
        if let shown {
          Text(shown.name)
            .font(.system(size: shown.name.count > 20 ? 24 : 28, weight: .bold)).tracking(-0.4).foregroundStyle(Theme.text)
            .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
            .frame(width: geo.size.width - 48, height: 80, alignment: .bottom)
            .position(x: geo.size.width / 2, y: rest.minY - 62)
            .opacity(named && !grown ? 1 : 0).offset(y: named ? 0 : 8)
            .allowsHitTesting(false)
          PrepSegmentsView(span: shown.span)
            .frame(width: side)
            .position(x: geo.size.width / 2, y: rest.maxY + 30)
            .opacity(named && !grown ? 1 : 0).offset(y: named ? 0 : 8)
            .allowsHitTesting(false)
        }
        // Once the drawn card has turned over, a tap anywhere goes straight to the board.
        if committed {
          Color.clear.contentShape(Rectangle()).onTapGesture { done() }
        }
        ZStack {
          ForEach([-6.0, -3, 0], id: \.self) { o in
            WelcomeCardBack(radius: 12).frame(width: 106, height: 115).offset(x: o, y: -o)
          }
        }
        .contentShape(Rectangle())
        .gesture(pull(from: deck, to: CGPoint(x: rest.midX, y: rest.midY)), including: draw == nil ? .none : .all)
        .accessibilityElement()
        .accessibilityLabel("Next run")
        .accessibilityAddTraits(.isButton)
        .accessibilityHidden(draw == nil)
        .accessibilityAction { if draw != nil { tapped() } }
        .position(deck)
        .opacity(grown ? 0 : 1)
        if let shown {
          face(shown, size: full, inset: inset, scale: scale)
            .modifier(DealFlip(progress: dealt, radius: 29 / scale))
            .frame(width: full + 2 * inset, height: full + 2 * inset)
            .scaleEffect(scale * (forward ? 1 : 0.4 + 0.2 * dealt))
            .offset(x: (deck.x - rest.midX) * (1 - dealt), y: (deck.y - rest.midY) * (1 - dealt))
            .position(center)
            .allowsHitTesting(false)
        }
      }
      .frame(width: geo.size.width, height: geo.size.height)
    }
    .task { if draw == nil { await play() } }
    .onDisappear { playing?.cancel() }
  }

  /// The card: the round's position in the card's frame, the frame and its accent gone once it is the board.
  /// Sizes are in the board's own units, so each is divided by `scale` to look right once scaled down.
  private func face(_ card: RoundCard, size: CGFloat, inset: CGFloat, scale: CGFloat) -> some View {
    BoardView(fen: card.fen, orientation: card.color, interactive: false, lastMove: card.lastMove, onMove: { _ in })
      .frame(width: size, height: size)
      .padding(inset)
      .background(RoundedRectangle(cornerRadius: grown ? 4 : 29 / scale).fill(Theme.surface.opacity(grown ? 0 : 1)))
      .overlay(RoundedRectangle(cornerRadius: grown ? 4 : 29 / scale).strokeBorder(Theme.accent.opacity(grown ? 0 : 1), lineWidth: 1.5 / scale))
      .shadow(color: .black.opacity(grown ? 0 : 0.55), radius: 17 / scale, y: 14 / scale)
  }

  /// A finger on the deck: the card follows it along the deal's path, nowhere else.
  private func pull(from deck: CGPoint, to rest: CGPoint) -> some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { value in
        guard !committed, !over else { return }
        guard take() else { return }
        let t = value.translation
        guard abs(t.width) + abs(t.height) > 6 else { return }
        let v = CGSize(width: rest.x - deck.x, height: rest.y - deck.y)
        let along = (t.width * v.width + t.height * v.height) / (v.width * v.width + v.height * v.height)
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) { dealt = min(1, max(0, along)) }
        // The face is showing: the deal takes over.
        if dealt > 0.5 { commit() }
      }
      .onEnded { value in
        guard !committed, !over else { return }
        let t = value.translation
        if abs(t.width) + abs(t.height) <= 6 {
          tapped()
        } else {
          withAnimation(.easeOut(duration: max(0.12, 0.3 * dealt))) { dealt = 0 }
        }
      }
  }

  /// The next round's card, taken once. With none to deal, straight on.
  private func take() -> Bool {
    if drawn != nil { return true }
    guard let next = draw?() else {
      done()
      return false
    }
    drawn = next
    return true
  }

  private func tapped() {
    guard !committed, !over, take() else { return }
    commit()
  }

  private func commit() {
    committed = true
    playing = Task { @MainActor in
      if reduceMotion {
        dealt = 1
        named = true
      } else {
        let left = Self.deal * (1 - dealt)
        withAnimation(dealt > 0 ? .easeOut(duration: left) : Self.dealCurve) { dealt = 1 }
        withAnimation(.easeOut(duration: 0.35).delay(left)) { named = true }
        try? await Task.sleep(for: .seconds(left + Self.beat))
      }
      await settle()
      try? await Task.sleep(for: .seconds(Self.grow))
      if !Task.isCancelled { done() }
    }
  }

  private func done() {
    guard !over else { return }
    over = true
    playing?.cancel()
    onDone?()
  }

  private func play() async {
    if reduceMotion {
      dealt = 1
      named = true
    } else {
      withAnimation(Self.dealCurve) { dealt = 1 }
      withAnimation(.easeOut(duration: 0.35).delay(Self.deal + 0.12)) { named = true }
    }
    try? await Task.sleep(for: .seconds(Self.deal + Self.beat))
    await settle()
  }

  /// Face up: forward, a beat, then onto the board.
  private func settle() async {
    if reduceMotion {
      forward = true
    } else {
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
