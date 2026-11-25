import ChessCore
import Game
import Model
import SwiftUI

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
