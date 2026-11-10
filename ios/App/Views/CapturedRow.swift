import ChessCore
import SwiftUI

/// The material difference, as Lichess shows it: what each side is up,
/// with even trades left out, and the lead as a plain "+3" beside the
/// pieces of the side that has it. Yours first, wherever you are sitting.
/// Black pieces are edged in white so they read on the dark background.
struct CapturedRow: View {
  var fen: String
  var orientation: ChessCore.Color

  var body: some View {
    let m = material(fen)
    let mine = orientation == .w ? m.byWhite : m.byBlack
    let theirs = orientation == .w ? m.byBlack : m.byWhite
    let ahead = m.lead != 0 && (m.lead > 0) == (orientation == .w)
    HStack(spacing: 1) {
      taken(mine, orientation.other)
      if m.lead != 0 && ahead { lead(m.lead) }
      if !mine.isEmpty && !theirs.isEmpty { Spacer().frame(width: 16) }
      taken(theirs, orientation)
      if m.lead != 0 && !ahead { lead(m.lead) }
      Spacer(minLength: 0)
    }
    .frame(minHeight: 22).padding(.horizontal, 2)
    // Never widens the screen.
    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
  }

  private func lead(_ lead: Int) -> some View {
    Text("+\(abs(lead))").font(.system(size: 13, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.text2)
      .padding(.leading, 5).fixedSize()
  }

  private func taken(_ pieces: [PieceType], _ color: ChessCore.Color) -> some View {
    ForEach(Array(pieces.enumerated()), id: \.offset) { _, type in
      PieceView(piece: BoardPiece(square: "a1", type: type, color: color), size: 18, outlined: true)
    }
  }
}
