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

/// Stepping through a finished game from the deck: a swipe left goes back a move, right goes forward.
/// `slide` reports a step part of the way along (0 when there is none), `step` takes it, `cancel` puts it back.
struct DeckSteps {
  let can: (Int) -> Bool
  let slide: (Int, Double) -> Void
  let step: (Int) -> Void
  let cancel: () -> Void
}

/// What a round's card shows: its start position and side.
struct RoundCard {
  let fen: String
  let lastMove: (from: String, to: String)?
  let color: ChessCore.Color
  /// Freeform: the squares of the pieces that start your lines, lit on the card.
  var starters: [String] = []
}

extension RunModel {
  /// This round's card, as the deal shows it.
  var card: RoundCard {
    RoundCard(fen: run.fen, lastMove: lastMoveOf(run.played), color: run.color, starters: starters)
  }
}

/// Play's round, announced: its card leaves the deck small, turns face up on the
/// round's start position on its way, and lands as the board (`board`), its frame
/// fading as it lands. Plays once, in `length`.
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
  /// With the deck under a finished run: swipes step through its game.
  var steps: DeckSteps? = nil
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  /// How far the card has come from the deck, 0...1: face down on the deck at 0, the board at 1.
  @State private var dealt = 0.0
  /// The card is the board: the deck and the cover are gone.
  @State private var landed = false
  @State private var drawn: RoundCard?
  /// The drawn card's face has shown: the rest plays by itself.
  @State private var committed = false
  @State private var over = false
  @State private var playing: Task<Void, Never>?
  /// Which way the finger on the deck is going: up to draw, sideways to step.
  @State private var sideways: Bool?
  /// The deck's top card, swiped to the side.
  @State private var swipeX: CGFloat = 0
  /// A card tucking back under the deck after a step, from the side it went to.
  @State private var tuckX: CGFloat?
  @State private var tucks = 0
  private static let swipeRange: CGFloat = 112

  static let deal = 0.7
  /// The whole announcement: `RunModel.start` waits this long before the board.
  static var length: Double { deal }
  private static var dealCurve: Animation { .timingCurve(0.5, 0, 0.2, 1, duration: deal) }

  private var shown: RoundCard? { draw == nil ? card : drawn }

  var body: some View {
    GeometryReader { geo in
      // The card is drawn at the board's own size and scaled down, so the board inside never relays out
      // (its coordinate labels would fade out and back in) on its way.
      let full = board?.width ?? geo.size.width - 24
      let target = CGPoint(x: board?.midX ?? geo.size.width / 2, y: board?.midY ?? geo.size.height * 0.4)
      let deck = CGPoint(x: geo.size.width / 2, y: geo.size.height - 130)
      // Drawn by hand, the finished run shows until the card comes out.
      let cover = landed ? 0 : draw == nil ? 1 : min(1, dealt * 1.15)
      ZStack(alignment: .topLeading) {
        Theme.background.opacity(cover).ignoresSafeArea()
          .allowsHitTesting(false)
        // Once the drawn card has turned over, a tap anywhere goes straight to the board.
        if committed {
          Color.clear.contentShape(Rectangle()).onTapGesture { done() }
        }
        ZStack {
          if let tuckX {
            WelcomeCardBack(radius: 12).frame(width: 106, height: 115).offset(x: tuckX, y: 6)
          }
          ForEach([-6.0, -3, 0], id: \.self) { o in
            WelcomeCardBack(radius: 12).frame(width: 106, height: 115)
              .offset(x: o + (o == 0 ? swipeX : 0), y: -o - (o == 0 ? abs(swipeX) * 0.06 : 0))
              .rotationEffect(.degrees(o == 0 ? Double(swipeX) * 0.1 : 0))
          }
        }
        .contentShape(Rectangle())
        .gesture(pull(from: deck, to: target), including: draw == nil ? .none : .all)
        .accessibilityElement()
        .accessibilityLabel("Next run")
        .accessibilityAddTraits(.isButton)
        .accessibilityHidden(draw == nil)
        .accessibilityAction { if draw != nil { tapped() } }
        .position(deck)
        .opacity(landed ? 0 : 1)
        if let shown {
          face(shown, size: full)
            .modifier(DealPath(
              progress: dealt, from: CGSize(width: deck.x - target.x, height: deck.y - target.y),
              startScale: 100 / full, thickness: full * 0.035))
            .position(target)
            .allowsHitTesting(false)
        }
      }
      .frame(width: geo.size.width, height: geo.size.height)
    }
    .task { if draw == nil { await play() } }
    .onDisappear { playing?.cancel() }
  }

  /// The card's face: the round's start position at the board's size, Freeform's starting squares lit.
  private func face(_ card: RoundCard, size: CGFloat) -> some View {
    BoardView(
      fen: card.fen, orientation: card.color, interactive: false, lastMove: card.lastMove,
      highlights: Dictionary(card.starters.map { ($0, Theme.accent) }, uniquingKeysWith: { a, _ in a }), onMove: { _ in })
      .frame(width: size, height: size)
  }

  /// A finger on the deck. Up, the card follows it along the deal's path, nowhere else, and a quick
  /// flick up deals it. Sideways, the top card follows and the game steps a move that way.
  private func pull(from deck: CGPoint, to rest: CGPoint) -> some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { value in
        guard !committed, !over else { return }
        let t = value.translation
        if sideways == nil {
          guard abs(t.width) + abs(t.height) > 8 else { return }
          sideways = steps != nil && abs(t.width) > abs(t.height)
          if sideways == true { tucks += 1 }
        }
        if sideways == true {
          swipe(t.width)
          return
        }
        guard take() else { return }
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) { dealt = along(t, deck, rest) }
        // The face is showing: the deal takes over.
        if dealt > 0.5 { commit() }
      }
      .onEnded { value in
        defer { sideways = nil }
        guard !committed, !over else { return }
        switch sideways {
        case nil:
          tapped()
        case true?:
          endSwipe(value.translation.width, predicted: value.predictedEndTranslation.width)
        case false?:
          // Flung up quickly enough to turn over: dealt.
          if along(value.predictedEndTranslation, deck, rest) > 0.5, take() {
            commit()
          } else {
            withAnimation(.easeOut(duration: max(0.12, 0.3 * dealt))) { dealt = 0 }
          }
        }
      }
  }

  /// How far a finger's travel takes the card along the deal's path, 0...1.
  private func along(_ t: CGSize, _ deck: CGPoint, _ rest: CGPoint) -> Double {
    let v = CGSize(width: rest.x - deck.x, height: rest.y - deck.y)
    return min(1, max(0, (t.width * v.width + t.height * v.height) / (v.width * v.width + v.height * v.height)))
  }

  /// The top card follows the finger, and the move with it. With no move that way, it only gives a little.
  private func swipe(_ dx: CGFloat) {
    guard let steps else { return }
    let dir = dx < 0 ? -1 : 1
    var still = Transaction()
    still.disablesAnimations = true
    withTransaction(still) {
      tuckX = nil
      if steps.can(dir) {
        swipeX = CGFloat(dir) * min(56, abs(dx) * 0.5)
        steps.slide(dir, Double(min(1, abs(dx) / Self.swipeRange)))
      } else {
        swipeX = CGFloat(dir) * min(14, abs(dx) * 0.2)
        steps.slide(dir, 0)
      }
    }
  }

  /// Far enough, or flicked: the step is taken and the card tucks back into the deck on that side.
  /// Otherwise everything goes back.
  private func endSwipe(_ dx: CGFloat, predicted: CGFloat) {
    guard let steps else { return }
    let dir = dx < 0 ? -1 : 1
    guard dx != 0, steps.can(dir), abs(dx) >= 36 || abs(predicted) >= 90 else {
      steps.cancel()
      withAnimation(.spring(response: 0.25, dampingFraction: 0.55)) { swipeX = 0 }
      return
    }
    steps.step(dir)
    let tuck = tucks
    guard !reduceMotion else {
      swipeX = 0
      return
    }
    withAnimation(.easeOut(duration: 0.09)) { swipeX = CGFloat(dir) * 62 }
    Task { @MainActor in
      try? await Task.sleep(for: .seconds(0.09))
      guard tucks == tuck else { return }
      var still = Transaction()
      still.disablesAnimations = true
      withTransaction(still) {
        swipeX = 0
        tuckX = CGFloat(dir) * 62
      }
      withAnimation(.easeOut(duration: 0.2)) { tuckX = -6 }
      try? await Task.sleep(for: .seconds(0.2))
      if tucks == tuck { tuckX = nil }
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
      await land()
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
    await land()
  }

  /// The rest of the way from the deck, straight onto the board.
  private func land() async {
    let left = Self.deal * (1 - dealt)
    if reduceMotion {
      dealt = 1
    } else {
      let curve: Animation = dealt > 0 ? .easeOut(duration: left) : Self.dealCurve
      withAnimation(curve) { dealt = 1 }
      try? await Task.sleep(for: .seconds(left))
    }
    guard !Task.isCancelled else { return }
    landed = true
  }
}

/// The card on its way from the deck to the board: face down and small on the deck at 0, turning
/// over as it comes (face up past halfway), the board itself at 1, its card frame fading as it lands.
/// The content is the board at full size; `from` is the deck's offset from the board's center.
/// Its body is thin copies of its rounded outline between the faces, so side-on it keeps an edge.
private struct DealPath: ViewModifier, Animatable {
  var progress: Double
  let from: CGSize
  let startScale: CGFloat
  let thickness: CGFloat

  nonisolated var animatableData: Double {
    get { progress }
    set { progress = newValue }
  }

  private static let layers = 7

  func body(content: Content) -> some View {
    let p = CGFloat(min(1, max(0, progress)))
    let scale = startScale + (1 - startScale) * p
    // The frame fades over the last stretch, as the card becomes the board.
    let frame = 1 - min(1, max(0, (p - 0.75) / 0.25))
    // Sizes below are in the board's own units, divided by `scale` to look right on screen.
    let radius = (4 + 8 * frame) / scale
    let margin = 10 * frame / scale
    let flip = 180 * (1 - Double(p))
    let side = CGFloat(sin(flip * .pi / 180))
    let edge = thickness * frame
    let card = RoundedRectangle(cornerRadius: radius)
    return ZStack {
      if edge > 0 && side > 0.01 {
        ForEach(0..<Self.layers, id: \.self) { i in
          let depth = edge * (CGFloat(i) / CGFloat(Self.layers - 1) - 0.5)
          card
            .fill(i % 2 == 0 ? SwiftUI.Color(hex: 0xaab0be) : SwiftUI.Color(hex: 0xc3c8d3))
            .padding(-margin)
            .rotation3DEffect(.degrees(flip), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .offset(x: depth * side)
        }
      }
      Group {
        if flip < 90 {
          content
            .background(card.fill(Theme.surface.opacity(frame)).padding(-margin))
            .overlay(card.strokeBorder(Theme.accent.opacity(frame), lineWidth: 1.5 / scale).padding(-margin))
            .shadow(color: .black.opacity(0.55 * frame), radius: 17 / scale, y: 14 / scale)
        } else {
          // Seen through the flip, so mirrored back to read the right way round.
          WelcomeCardBack(radius: radius).padding(-margin).scaleEffect(x: -1)
        }
      }
      .rotation3DEffect(.degrees(flip), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
      .offset(x: (flip < 90 ? 0.5 : -0.5) * edge * side)
    }
    .scaleEffect(scale)
    .offset(x: from.width * (1 - p), y: from.height * (1 - p))
  }
}
