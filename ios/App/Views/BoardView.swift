import ChessCore
import Model
import SwiftUI

/// An arrow drawn over the board.
struct BoardArrow: Equatable {
  var from: String
  var to: String
  var color: SwiftUI.Color
}

/// The board: tap a piece, then a square. Moves are only offered to `movable`'s side.
struct BoardView: View {
  var fen: String
  var orientation: ChessCore.Color
  var interactive: Bool
  var lastMove: (from: String, to: String)?
  var highlights: [String: SwiftUI.Color] = [:]
  var arrows: [BoardArrow] = []
  var glow: Glow?
  var pop: Pop?
  var onMove: (LegalMove) -> Void

  @State private var selected: String?

  private static let light = SwiftUI.Color(hex: 0xe4e8ef)
  private static let dark = SwiftUI.Color(hex: 0x8290a6)

  var body: some View {
    GeometryReader { geo in
      let size = min(geo.size.width, geo.size.height)
      let cell = size / 8
      let pieces = Dictionary(piecesFromFen(fen).map { ($0.square, $0) }, uniquingKeysWith: { a, _ in a })
      let targets = selected.map { from in legalMoves(fen).filter { $0.from == from }.map(\.to) } ?? []
      ZStack(alignment: .topLeading) {
        ForEach(0..<64, id: \.self) { i in
          let square = squareAt(i)
          let (col, row) = position(square)
          let isLight = (col + row) % 2 == 0
          ZStack {
            Rectangle().fill(isLight ? Self.light : Self.dark)
            if let tint = highlights[square] {
              Rectangle().fill(tint.opacity(0.45))
            } else if square == selected {
              Rectangle().fill(SwiftUI.Color.yellow.opacity(0.4))
            } else if let last = lastMove, last.from == square || last.to == square {
              Rectangle().fill(SwiftUI.Color.yellow.opacity(0.22))
            }
            if targets.contains(square) {
              Circle().fill(SwiftUI.Color.black.opacity(0.22)).frame(width: cell * 0.3, height: cell * 0.3)
            }
            if let piece = pieces[square] { PieceView(piece: piece, size: cell) }
          }
          .frame(width: cell, height: cell)
          .offset(x: CGFloat(col) * cell, y: CGFloat(row) * cell)
          .onTapGesture { tap(square, pieces) }
        }
        ArrowsView(arrows: arrows, cell: cell, position: position)
          .allowsHitTesting(false)
        if let pop {
          PopView(pop: pop)
            .position(x: (CGFloat(position(pop.square).col) + 0.5) * cell, y: (CGFloat(position(pop.square).row) + 0.1) * cell)
            .allowsHitTesting(false)
        }
      }
      .frame(width: size, height: size)
      .overlay(glowBorder)
    }
    .aspectRatio(1, contentMode: .fit)
    .onChange(of: fen) { selected = nil }
  }

  @ViewBuilder private var glowBorder: some View {
    if let glow {
      let color: SwiftUI.Color = glow.tone == .green ? Theme.good : glow.tone == .yellow ? Theme.warn : Theme.bad
      RoundedRectangle(cornerRadius: 2)
        .stroke(color.opacity(0.35 + 0.55 * glow.strength), lineWidth: 3 + 5 * glow.strength)
        .blur(radius: 2)
        .allowsHitTesting(false)
    }
  }

  private func squareAt(_ i: Int) -> String {
    let file = i % 8, rank = i / 8
    return String(UnicodeScalar(UInt8(97 + file))) + String(rank + 1)
  }

  private func position(_ square: String) -> (col: Int, row: Int) {
    let u = Array(square.utf8)
    let file = Int(u[0]) - 97, rank = Int(u[1]) - 49
    return orientation == .w ? (file, 7 - rank) : (7 - file, rank)
  }

  private func tap(_ square: String, _ pieces: [String: BoardPiece]) {
    guard interactive else { return }
    let turn = fenTurn(fen)
    if let from = selected {
      // Promotions go to a queen.
      let moves = legalMoves(fen).filter { $0.from == from && $0.to == square }
      if let move = moves.first(where: { $0.promotion == nil || $0.promotion == .q }) {
        selected = nil
        onMove(move)
        return
      }
    }
    if let piece = pieces[square], piece.color == turn, piece.color == orientation {
      selected = square == selected ? nil : square
    } else {
      selected = nil
    }
  }
}

/// A piece, drawn with the chess glyphs.
struct PieceView: View {
  var piece: BoardPiece
  var size: CGFloat

  private static let glyphs: [PieceType: String] = [.k: "\u{265A}", .q: "\u{265B}", .r: "\u{265C}", .b: "\u{265D}", .n: "\u{265E}", .p: "\u{265F}\u{FE0E}"]

  var body: some View {
    let glyph = Self.glyphs[piece.type]!
    ZStack {
      // An outline in the other color keeps each piece readable on both squares.
      Text(glyph).foregroundStyle(piece.color == .w ? SwiftUI.Color.black : SwiftUI.Color.white).blur(radius: 0.6)
      Text(glyph).foregroundStyle(piece.color == .w ? SwiftUI.Color.white : SwiftUI.Color.black)
    }
    .font(.system(size: size * 0.8))
  }
}

struct ArrowsView: View {
  var arrows: [BoardArrow]
  var cell: CGFloat
  var position: (String) -> (col: Int, row: Int)

  var body: some View {
    Canvas { context, _ in
      for arrow in arrows {
        let a = center(arrow.from), b = center(arrow.to)
        let angle = atan2(b.y - a.y, b.x - a.x)
        let head = cell * 0.32
        let end = CGPoint(x: b.x - cos(angle) * head * 0.8, y: b.y - sin(angle) * head * 0.8)
        var shaft = Path()
        shaft.move(to: a)
        shaft.addLine(to: end)
        context.stroke(shaft, with: .color(arrow.color.opacity(0.85)), style: StrokeStyle(lineWidth: cell * 0.16, lineCap: .round))
        var tip = Path()
        tip.move(to: b)
        tip.addLine(to: CGPoint(x: b.x - cos(angle - 0.5) * head, y: b.y - sin(angle - 0.5) * head))
        tip.addLine(to: CGPoint(x: b.x - cos(angle + 0.5) * head, y: b.y - sin(angle + 0.5) * head))
        tip.closeSubpath()
        context.fill(tip, with: .color(arrow.color.opacity(0.9)))
      }
    }
  }

  private func center(_ square: String) -> CGPoint {
    let p = position(square)
    return CGPoint(x: (CGFloat(p.col) + 0.5) * cell, y: (CGFloat(p.row) + 0.5) * cell)
  }
}

/// A move's popup over its square: a prepared move's tick and time, or what a move cost.
struct PopView: View {
  var pop: Pop

  var body: some View {
    let tone: SwiftUI.Color = pop.tone == .up ? Theme.good : pop.tone == .slight ? Theme.warn : Theme.bad
    HStack(spacing: 3) {
      if pop.found { Text("\u{2713}").foregroundStyle(pop.book ? Theme.book : pop.ext ? Theme.ext : tone) }
      if pop.book { Text("Book").foregroundStyle(Theme.book) }
      if pop.ext { Text("Ext").foregroundStyle(Theme.ext) }
      Text(pop.text).foregroundStyle(tone)
    }
    .font(.system(size: 13, weight: .bold).monospacedDigit())
    .padding(.horizontal, 6)
    .padding(.vertical, 2)
    .background(Capsule().fill(Theme.background.opacity(0.85)))
    .overlay(Capsule().stroke(pop.ext ? Theme.ext : .clear, lineWidth: 1))
    .transition(.opacity.combined(with: .move(edge: .bottom)))
  }
}
