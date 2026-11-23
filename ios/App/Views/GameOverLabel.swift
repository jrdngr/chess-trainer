import ChessCore
import SwiftUI

/// A finished position's name in analysis, in the run ending's style: checkmate red with its cross
/// when `you` are the side mated, green when you gave it; stalemate and other draws gray.
struct GameOverLabel: View {
  let fen: String
  let you: ChessCore.Color

  var body: some View {
    let status = positionStatus(fen)
    let mated = status.checkmate && fenTurn(fen) == you
    let tone: SwiftUI.Color = mated ? Theme.bad : status.checkmate ? Theme.good : Theme.text2
    HStack(spacing: 8) {
      if mated {
        Icon(name: "cross", size: 18).frame(width: 26, height: 26).background(Circle().fill(Theme.bad.opacity(0.14)))
      }
      Text(status.checkmate ? "Checkmate" : status.stalemate ? "Stalemate" : "Draw")
        .font(.system(size: 19, weight: .heavy)).tracking(-0.19)
    }
    .foregroundStyle(tone)
  }
}
