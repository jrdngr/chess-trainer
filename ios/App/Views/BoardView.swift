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
  /// Nil follows the setting.
  var coordinates: Bool?
  @Environment(\.boardLook) private var look
  /// What a held lens draws over the position.
  var marks: LensMarks?
  /// Either side may move, not only `orientation`'s: the browsers, the board builder and Analysis.
  var bothSides = false
  var onMove: (LegalMove) -> Void

  @State private var selected: String?

  private var light: SwiftUI.Color { look.theme.light }
  private var dark: SwiftUI.Color { look.theme.dark }
  private static let lastTint = SwiftUI.Color(red: 1, green: 214 / 255, blue: 90 / 255).opacity(0.42)
  private static let selectedTint = SwiftUI.Color(red: 1, green: 214 / 255, blue: 90 / 255).opacity(0.55)

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
            Rectangle().fill(isLight ? light : dark)
            if let tint = highlights[square] {
              Rectangle().fill(tint.opacity(0.45))
            } else if square == selected {
              Rectangle().fill(Self.selectedTint)
            } else if let last = lastMove, last.from == square || last.to == square {
              Rectangle().fill(Self.lastTint)
            }
            if targets.contains(square) {
              Circle().fill(SwiftUI.Color.black.opacity(0.22)).frame(width: cell * 0.3, height: cell * 0.3)
            }
            if coordinates ?? look.coordinates { coordinateLabels(square, col: col, row: row, onLight: isLight, cell: cell) }
          }
          .frame(width: cell, height: cell)
          .offset(x: CGFloat(col) * cell, y: CGFloat(row) * cell)
          .onTapGesture { tap(square, pieces) }
        }
        if let marks { LensUnderView(marks: marks, cell: cell, position: position) }
        ForEach(Array(pieces.keys), id: \.self) { square in
          let (col, row) = position(square)
          let piece = pieces[square]!
          // Sized to match the web board's pieces.
          PieceView(piece: piece, size: cell * 0.78)
            .opacity(marks?.ghost == true && piece.type != .p ? 0.18 : 1)
            .frame(width: cell, height: cell)
            .offset(x: CGFloat(col) * cell, y: CGFloat(row) * cell)
            .allowsHitTesting(false)
        }
        if let marks { LensOverView(marks: marks, cell: cell, position: position) }
        ArrowsView(arrows: arrows, cell: cell, position: position)
          .allowsHitTesting(false)
        if let pop {
          PopView(pop: pop)
            .position(x: (CGFloat(position(pop.square).col) + 0.5) * cell, y: (CGFloat(position(pop.square).row) + 0.1) * cell)
            .allowsHitTesting(false)
        }
      }
      .frame(width: size, height: size)
      .clipShape(RoundedRectangle(cornerRadius: size * 0.03))
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

  /// Rank numbers down the left edge and file letters along the bottom, in the other square's color.
  @ViewBuilder private func coordinateLabels(_ square: String, col: Int, row: Int, onLight: Bool, cell: CGFloat) -> some View {
    let ink = onLight ? dark : light
    ZStack {
      if col == 0 {
        Text(String(square.last!)).font(.system(size: cell * 0.2, weight: .semibold)).foregroundStyle(ink)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(cell * 0.05)
      }
      if row == 7 {
        Text(String(square.first!)).font(.system(size: cell * 0.2, weight: .semibold)).foregroundStyle(ink)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(cell * 0.05)
      }
    }
    .allowsHitTesting(false)
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
    if let piece = pieces[square], piece.color == turn, bothSides || piece.color == orientation {
      selected = square == selected ? nil : square
    } else {
      selected = nil
    }
  }
}

/// A piece, drawn with the prototype's own shapes: `Pieces.tsx`.
struct PieceView: View {
  var piece: BoardPiece
  var size: CGFloat

  private static let shapes: [PieceType: String] = [
    .p: PieceShapes.p, .n: PieceShapes.n, .b: PieceShapes.b, .r: PieceShapes.r, .q: PieceShapes.q, .k: PieceShapes.k,
  ]

  var body: some View {
    let white = piece.color == .w
    let fill = SwiftUI.Color(hex: white ? 0xf6f8fb : 0x20262f)
    let stroke = SwiftUI.Color(hex: white ? 0x2b3441 : 0x05080c)
    let line = StrokeStyle(lineWidth: 1.5 * size / 45, lineCap: .round, lineJoin: .round)
    ZStack {
      SVGPath(d: Self.shapes[piece.type]!).fill(fill)
      SVGPath(d: Self.shapes[piece.type]!).stroke(stroke, style: line)
      if piece.type == .k {
        SVGPath(d: PieceShapes.kingCross).stroke(stroke, style: StrokeStyle(lineWidth: 2.2 * size / 45, lineCap: .round))
      }
      if piece.type == .b {
        SVGPath(d: PieceShapes.bishopMark).stroke(stroke, style: StrokeStyle(lineWidth: 1.4 * size / 45, lineCap: .round))
      }
      if piece.type == .n {
        Circle().fill(white ? stroke : SwiftUI.Color(hex: 0x8d97a5))
          .frame(width: 2.2 * size / 45, height: 2.2 * size / 45)
          .position(x: 14.3 * size / 45, y: 20.2 * size / 45)
      }
    }
    .frame(width: size, height: size)
    .shadow(color: .black.opacity(0.42), radius: 1.5 * size / 45, y: size / 45)
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

/// How boards look, from the settings: the theme and whether coordinates show.
struct BoardLook {
  var theme = BoardTheme.slate
  var coordinates = true
}

extension EnvironmentValues {
  @Entry var boardLook = BoardLook()
}

extension BoardTheme {
  var light: SwiftUI.Color {
    switch self {
    case .slate: SwiftUI.Color(hex: 0xe4e8ef)
    case .walnut: SwiftUI.Color(hex: 0xf0d9b5)
    case .ocean: SwiftUI.Color(hex: 0xd6e4f0)
    }
  }
  var dark: SwiftUI.Color {
    switch self {
    case .slate: SwiftUI.Color(hex: 0x8290a6)
    case .walnut: SwiftUI.Color(hex: 0xb58863)
    case .ocean: SwiftUI.Color(hex: 0x6d94b8)
    }
  }
}
