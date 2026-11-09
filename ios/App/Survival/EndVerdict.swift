import ChessCore
import Model
import SwiftUI

/// How the run ended, as a callout over the dimmed board as the end screen opens.
struct EndVerdict: View {
  let how: Ending
  let plies: Int

  var body: some View {
    let (symbol, tone): (String, SwiftUI.Color) = switch how {
    case .blunder, .lost: ("xmark", Theme.bad)
    case .won: ("checkmark", Theme.good)
    case .ended: ("flag.fill", Theme.warn)
    case .draw: ("equal", Theme.warn)
    }
    ZStack {
      SwiftUI.Color.black.opacity(0.35)
      BoardCallout(text: endingTitle(how, plies), tone: tone, symbol: symbol).padding(.horizontal, 16)
    }
    .clipShape(RoundedRectangle(cornerRadius: 14))
  }
}

/// Red on the move played and green on the one that should have been, in the position they were played in.
func endHighlights(_ fen: String, played: String, right: String?) -> [String: SwiftUI.Color] {
  var out: [String: SwiftUI.Color] = [:]
  if let wrong = applySan(fen, played) {
    out[wrong.from] = Theme.bad
    out[wrong.to] = Theme.bad
  }
  if let right, let move = applySan(fen, right) {
    out[move.from] = Theme.good
    out[move.to] = Theme.good
  }
  return out
}
