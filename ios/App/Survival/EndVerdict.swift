import ChessCore
import Model
import SwiftUI

/// How the run ended, on a pill over the dimmed board as the end screen opens: `.board-flash` and `.verdict`.
struct EndVerdict: View {
  let how: Ending
  let plies: Int

  var body: some View {
    let (icon, tone): (String, SwiftUI.Color) = switch how {
    case .blunder, .lost: ("cross", Theme.bad)
    case .won: ("check", Theme.good)
    case .ended: ("close", Theme.warn)
    case .draw: ("check", Theme.warn)
    }
    ZStack {
      SwiftUI.Color.black.opacity(0.35)
      HStack(spacing: 8) {
        Icon(name: icon, size: 18).frame(width: 26, height: 26).background(Circle().fill(tone.opacity(0.14)))
        Text(endingTitle(how, plies)).font(.system(size: 19, weight: .heavy)).tracking(-0.2).lineLimit(1)
      }
      .foregroundStyle(tone)
      .padding(.leading, 14).padding(.trailing, 22).padding(.vertical, 12)
      .background(Capsule().fill(Theme.surface)).shadow(color: .black.opacity(0.5), radius: 15, y: 10)
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
