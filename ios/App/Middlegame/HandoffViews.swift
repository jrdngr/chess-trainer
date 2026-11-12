import ChessCore
import Game
import Model
import SwiftUI

/// The moves played for you so far, in the colors of who chose them: your line,
/// the book, or the engine. The latest moves show; earlier ones scroll off the top.
struct HandoffMoves: View {
  let handoff: Handoff
  /// How many of the handoff's moves are on the board.
  let played: Int

  /// The engine's moves on the way to the handoff.
  static let engine = SwiftUI.Color(hex: 0xc4b5fd)

  var body: some View {
    text.font(.system(size: 13.5).monospacedDigit()).lineSpacing(3).lineLimit(2)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
      .padding(.horizontal, 12).padding(.vertical, 8)
      .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
  }

  /// The last few moves as one run of text, the newest underlined.
  private var text: Text {
    let shown = min(played, handoff.line.count)
    // Six whole moves fit the slot's two lines; a line never starts on Black's half of one.
    let from = max(0, shown - 12) / 2 * 2
    var out = Text("")
    for ply in from..<shown {
      if ply % 2 == 0 { out = out + Text("\(ply / 2 + 1). ").foregroundColor(Theme.text3) }
      var san = Text(handoff.line[ply]).foregroundColor(color(handoff.kinds[ply]))
      if handoff.kinds[ply] == .prep { san = san.fontWeight(.semibold) }
      if ply == shown - 1 { san = san.underline() }
      out = out + san + Text(" ")
    }
    return out
  }

  private func color(_ kind: HandoffKind) -> SwiftUI.Color {
    switch kind {
    case .prep: Theme.text
    case .book: Theme.book.opacity(0.8)
    case .engine: Self.engine.opacity(0.8)
    }
  }
}

/// The plan for the structure you are handed, over the dock until you press Play.
struct HandoffPlanCard: View {
  /// The game's positions, the handoff last.
  let fens: [String]
  let me: ChessCore.Color

  var body: some View {
    let trail = PlanTrails.of(fens, me)
    if trail.current != nil {
      PlanCardBody(trail: trail, fen: fens.last!, me: me)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.vertical, 14)
        .planCardFrame()
        .padding(.top, 10)
    }
  }
}

/// The handoff's Play, where End run sits once you play: it closes the plan card and starts your clock.
struct HandoffPlayButton: View {
  let onPlay: () -> Void

  var body: some View {
    Button(action: onPlay) {
      Text("Play").font(.system(size: 15, weight: .heavy)).foregroundStyle(PlanColors.ink)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(RoundedRectangle(cornerRadius: 12).fill(PlanColors.plan))
    }
    .buttonStyle(.plain)
  }
}
