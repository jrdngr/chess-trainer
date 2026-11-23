import Game
import SwiftUI

/// Show, beside "Blunder": a gray key cut to the row, led by a glyph that says what a press does.
/// A play triangle before; while the line plays, the key is held down and the triangle turns the engine's blue,
/// beating once per move; at the line's end, a replay arrow. The word and width never change.
struct ShowKey: View {
  let analysis: RunAnalysis
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var faded = false

  /// The key, lip included; the row keeps today's 44pt, the spare height above it and the rest under it.
  private static let height: CGFloat = 34
  private static let above: CGFloat = 7.5
  private static let below: CGFloat = 2.5

  var body: some View {
    let playing = analysis.showing
    Button { analysis.show() } label: {
      HStack(spacing: 6) {
        Icon(name: analysis.atPunishmentEnd ? "replay" : "play", size: 13)
          .foregroundStyle(playing ? Theme.book : Theme.text)
          .opacity(playing && faded && !reduceMotion ? 0.4 : 1)
        // Held for seconds, so the word stays near white rather than the pressed gray, which reads as disabled.
        Text("Show").foregroundStyle(playing ? Color(hex: 0xcfcfd7) : Theme.text)
      }
      .frame(width: 79)
    }
    .buttonStyle(PlayButtonStyle(kind: .soft, height: Self.height, radius: 10, font: 15, inset: 0, held: playing))
    .padding(.top, Self.above).padding(.bottom, Self.below)
    // The tap area is the row's full height; it reaches up, never down into the deck.
    .contentShape(Rectangle())
    // A beat as each move lands: the triangle bright, fading until the next.
    .onChange(of: analysis.ply) {
      guard analysis.showing else { return }
      var reset = Transaction()
      reset.disablesAnimations = true
      withTransaction(reset) { faded = false }
      Task { @MainActor in withAnimation(.easeOut(duration: 0.8)) { faded = true } }
    }
  }
}
