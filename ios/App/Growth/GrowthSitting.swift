import ChessCore
import Model
import SwiftUI

/// A sitting of Growth wherever it opens: from Home, or grown from the end
/// of an Autopilot or Survival run. A game from here plays over it.
struct GrowthSitting: View {
  let model: GrowthModel
  /// Analysis on a line, seen from a side.
  let onAnalyze: ([String], ChessCore.Color) -> Void
  /// Home.
  let onExit: () -> Void

  /// The position a carry-on game starts from, once one is asked for.
  @State private var playFrom: String?

  var body: some View {
    ZStack {
      GrowthView(model: model, exits: GrowthView.Exits(
        analyze: { onAnalyze(model.run.path, model.run.color) },
        playFrom: { playFrom = $0 },
        close: onExit))
        .opacity(playFrom == nil ? 1 : 0).allowsHitTesting(playFrom == nil)
      if let playFrom {
        PlayOnView(from: playFrom, color: model.run.color, label: model.launch.row.name) { self.playFrom = nil }
          .background(Theme.background)
      }
    }
  }
}
