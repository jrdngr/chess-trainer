import ChessCore
import Model
import SwiftUI

/// An arrow drawn over the board.
struct BoardArrow: Equatable {
  var from: String
  var to: String
  var color: SwiftUI.Color
  /// A soft halo under the arrow: Growth's nudge toward or away from your patterns.
  var glow: SwiftUI.Color? = nil
  /// Drawn over the pieces: a threat that has to read even across the pieces in its way.
  var over = false
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
  /// Which popup `pop` is: a new one floats up, the same one doesn't start over when the board moves.
  var popId = 0
  /// Nil follows the setting.
  var coordinates: Bool?
  @Environment(\.boardLook) private var look
  /// What a held lens draws over the position.
  var marks: LensMarks?
  /// Either side may move, not only `orientation`'s: the browsers, the board builder and Analysis.
  var bothSides = false
  /// Only these moves, by SAN, may be played: Growth's answers at a hole.
  var allowed: [String]? = nil
  /// A move part of the way along, as a swipe through a finished game has it.
  var slide: BoardSlide? = nil
  var onMove: (LegalMove) -> Void
  /// A legal move `allowed` held back.
  var onRefused: (() -> Void)? = nil

  @State private var selected: String?
  @State private var tracker = PieceTracker()
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var light: SwiftUI.Color { look.theme.light }
  private var dark: SwiftUI.Color { look.theme.dark }
  private static let lastTint = SwiftUI.Color(red: 1, green: 214 / 255, blue: 90 / 255).opacity(0.42)
  private static let selectedTint = SwiftUI.Color(red: 1, green: 214 / 255, blue: 90 / 255).opacity(0.55)

  var body: some View {
    GeometryReader { geo in
      let size = min(geo.size.width, geo.size.height)
      let cell = size / 8
      let pieces = Dictionary(piecesFromFen(fen).map { ($0.square, $0) }, uniquingKeysWith: { a, _ in a })
      let targets = selected.map { from in playable.filter { $0.from == from }.map(\.to) } ?? []
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
        // Under the pieces: an arrow never hides what it points at.
        ArrowsView(arrows: arrows.filter { !$0.over }, cell: cell, position: position).allowsHitTesting(false)
        let ids = tracker.ids(fen, pieces)
        let tints = LensColors.pieceTints(marks)
        let sliding = slide.map { $0.motion(pieces) }
        // A capture taken back comes in again under the piece that made it.
        if let back = sliding?.returning {
          PieceView(piece: back, size: cell * 0.78)
            .frame(width: cell, height: cell)
            .offset(x: CGFloat(position(back.square).col) * cell, y: CGFloat(position(back.square).row) * cell)
            .opacity(sliding?.amount ?? 0)
            .allowsHitTesting(false)
        }
        ForEach(pieces.keys.sorted().map { (id: ids[$0] ?? 0, square: $0) }, id: \.id) { placed in
          let piece = pieces[placed.square]!
          let target = sliding?.moving[placed.square]
          let shift = target.map { t -> CGSize in
            let a = position(placed.square), b = position(t), k = sliding?.amount ?? 0
            return CGSize(width: CGFloat(b.col - a.col) * cell * k, height: CGFloat(b.row - a.row) * cell * k)
          } ?? .zero
          PlacedPiece(id: placed.id, square: placed.square, piece: piece, cell: cell, position: position(placed.square),
                      tint: tints[placed.square], ghost: marks.map { $0.focus.map { !$0.contains(placed.square) } ?? ($0.ghost == true && piece.type != .p) } ?? false,
                      shift: shift, fade: sliding?.fading == placed.square ? 1 - (sliding?.amount ?? 0) : 1)
            .zIndex(target != nil ? 1 : 0)
        }
        .animation(reduceMotion ? nil : Motion.slide(0.16), value: fen)
        if let marks { LensOverView(marks: marks, cell: cell, position: position) }
        ArrowsView(arrows: arrows.filter(\.over), cell: cell, position: position).allowsHitTesting(false)
        if let pop {
          PopView(pop: pop)
            .modifier(MoveScoreFloat())
            .id(popId)
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
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.8), value: glow)
        // Gone at once, so a moment's found pulse never lands on its fading glow.
        .transition(.asymmetric(insertion: .opacity, removal: .identity))
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

  /// The legal moves, held to `allowed` when it is set.
  private var playable: [LegalMove] {
    let moves = legalMoves(fen)
    guard let allowed else { return moves }
    return moves.filter { allowed.contains($0.san) }
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
      let moves = playable.filter { $0.from == from && $0.to == square }
      if let move = moves.first(where: { $0.promotion == nil || $0.promotion == .q }) {
        selected = nil
        onMove(move)
        return
      }
      if allowed != nil, legalMoves(fen).contains(where: { $0.from == from && $0.to == square }) {
        selected = nil
        onRefused?()
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

/// A piece, drawn with the app's own shapes.
struct PieceView: View {
  var piece: BoardPiece
  var size: CGFloat
  /// A black piece edged in white, to read on the dark background off the board.
  var outlined = false
  /// A lens's color laid over the piece's own, light on White's pieces and dark on Black's.
  var tint: SwiftUI.Color? = nil

  private static let shapes: [PieceType: String] = [
    .p: PieceShapes.p, .n: PieceShapes.n, .b: PieceShapes.b, .r: PieceShapes.r, .q: PieceShapes.q, .k: PieceShapes.k,
  ]

  var body: some View {
    let white = piece.color == .w
    let fill = SwiftUI.Color(hex: white ? 0xf6f8fb : 0x20262f)
    let stroke = SwiftUI.Color(hex: white ? 0x2b3441 : 0x05080c)
    let edged = outlined && !white
    let line = StrokeStyle(lineWidth: (edged ? 1.8 : 1.5) * size / 45, lineCap: .round, lineJoin: .round)
    ZStack {
      SVGPath(d: Self.shapes[piece.type]!).fill(fill)
      if let tint { SVGPath(d: Self.shapes[piece.type]!).fill(tint.opacity(white ? 0.6 : 0.7)) }
      SVGPath(d: Self.shapes[piece.type]!).stroke(edged ? SwiftUI.Color(hex: 0xf2f4f8) : stroke, style: line)
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

/// Arrows over the board. A disc under the piece a run of arrows starts from, a dark
/// edge under each so it reads on light and dark squares, every shaft before
/// any head, and Growth's soft glow under the lot.
/// One piece on its square. Keyed by the piece, not the square, so a move
/// slides it.
private struct PlacedPiece: View {
  let id: Int
  let square: String
  let piece: BoardPiece
  let cell: CGFloat
  let position: (col: Int, row: Int)
  /// A lens's word on the piece, as its color.
  let tint: SwiftUI.Color?
  let ghost: Bool
  /// Part of the way to another square, under a swipe.
  var shift: CGSize = .zero
  var fade: Double = 1

  var body: some View {
    PieceView(piece: piece, size: cell * 0.78, tint: tint)
      .opacity((ghost ? 0.18 : 1) * fade)
      .frame(width: cell, height: cell)
      .offset(x: CGFloat(position.col) * cell + shift.width, y: CGFloat(position.row) * cell + shift.height)
      .allowsHitTesting(false)
  }
}

struct ArrowsView: View {
  var arrows: [BoardArrow]
  var cell: CGFloat
  var position: (String) -> (col: Int, row: Int)
  /// The disc under where a run of arrows starts; a lens's arrows have none.
  var origins = true

  /// Widths in squares.
  static let width: CGFloat = 0.13
  static let edge: CGFloat = 0.025
  static let glowEdge: CGFloat = 0.04
  static let ink = SwiftUI.Color(red: 10 / 255, green: 12 / 255, blue: 20 / 255).opacity(0.7)

  var body: some View {
    Canvas { context, _ in
      let drawn = arrows.map { shape(center($0.from), center($0.to)) }
      for (arrow, d) in zip(arrows, drawn) {
        guard let glow = arrow.glow else { continue }
        var halo = context
        halo.addFilter(.blur(radius: cell * 0.07))
        halo.opacity = 0.85
        halo.stroke(d.shaft, with: .color(glow), style: StrokeStyle(lineWidth: cell * 0.34, lineCap: .round))
        halo.fill(d.head, with: .color(glow))
        halo.stroke(d.head, with: .color(glow), style: StrokeStyle(lineWidth: cell * 0.2, lineJoin: .round))
      }
      // Where a run of arrows starts: a disc under the piece that moves first.
      for (arrow, d) in zip(arrows, drawn) where origins && !arrows.contains(where: { $0.to == arrow.from }) {
        let r = cell * 0.4
        let disc = Path(ellipseIn: CGRect(x: d.from.x - r, y: d.from.y - r, width: 2 * r, height: 2 * r))
        var faint = context
        faint.opacity = 0.45
        faint.fill(disc, with: .color(arrow.color))
        faint.stroke(disc, with: .color(Self.ink), lineWidth: cell * Self.edge)
      }
      for (arrow, d) in zip(arrows, drawn) {
        let edge = arrow.glow == nil ? Self.edge : Self.glowEdge
        context.stroke(d.shaft, with: .color(arrow.glow ?? Self.ink),
                       style: StrokeStyle(lineWidth: cell * (Self.width + edge * 2), lineCap: .round))
      }
      for (arrow, d) in zip(arrows, drawn) {
        context.stroke(d.shaft, with: .color(arrow.color), style: StrokeStyle(lineWidth: cell * Self.width, lineCap: .round))
      }
      for (arrow, d) in zip(arrows, drawn) {
        context.stroke(d.head, with: .color(arrow.glow ?? Self.ink),
                       style: StrokeStyle(lineWidth: cell * (arrow.glow == nil ? Self.edge * 2 : Self.glowEdge * 3.2), lineJoin: .round))
        context.fill(d.head, with: .color(arrow.color))
      }
    }
  }

  /// The head is three stroke widths long, its tip a little past the target's
  /// centre; the shaft stops at the head's base, its round cap just reaching it.
  private func shape(_ from: CGPoint, _ to: CGPoint) -> (from: CGPoint, shaft: Path, head: Path) {
    let w = Self.width * cell
    let dx = to.x - from.x, dy = to.y - from.y
    let len = max(hypot(dx, dy), 1)
    let ux = dx / len, uy = dy / len
    let tip = CGPoint(x: to.x + ux * w * 1.4, y: to.y + uy * w * 1.4)
    let base = CGPoint(x: tip.x - ux * w * 3, y: tip.y - uy * w * 3)
    let half = w * 1.5
    var head = Path()
    head.move(to: tip)
    head.addLine(to: CGPoint(x: base.x - uy * half, y: base.y + ux * half))
    head.addLine(to: CGPoint(x: base.x + uy * half, y: base.y - ux * half))
    head.closeSubpath()
    let back = w / 2 - 0.01 * cell
    var shaft = Path()
    shaft.move(to: from)
    shaft.addLine(to: CGPoint(x: base.x - ux * back, y: base.y - uy * back))
    return (from, shaft, head)
  }

  private func center(_ square: String) -> CGPoint {
    let p = position(square)
    return CGPoint(x: (CGFloat(p.col) + 0.5) * cell, y: (CGFloat(p.row) + 0.5) * cell)
  }
}

/// A move's popup over its square: a prepared move's tick and time, what a move cost, or a found moment's bonus.
struct PopView: View {
  var pop: Pop

  var body: some View {
    let tone: SwiftUI.Color = pop.tone == .up ? Theme.good : pop.tone == .slight ? Theme.warn : Theme.bad
    if pop.moment {
      HStack(spacing: 4) {
        Text("\u{2713}")
        Text(pop.text)
      }
      .font(.system(size: 17, weight: .heavy).monospacedDigit())
      .foregroundStyle(.white)
      .padding(.horizontal, 10)
      .padding(.vertical, 4)
      .background(Capsule().fill(Theme.good))
      .shadow(color: Theme.good.opacity(0.6), radius: 6)
    } else {
      plain(tone)
    }
  }

  private func plain(_ tone: SwiftUI.Color) -> some View {
    HStack(spacing: 3) {
      if pop.found { Text("\u{2713}").foregroundStyle(pop.book ? Theme.book : pop.ext ? Theme.ext : tone) }
      // A common move past your line gets only its quiet tick: no time, no word.
      if !pop.book {
        if pop.ext { Text("Ext").foregroundStyle(Theme.ext) }
        Text(pop.text).foregroundStyle(tone)
      }
    }
    .font(.system(size: 13, weight: .bold).monospacedDigit())
    .padding(.horizontal, 6)
    .padding(.vertical, 2)
    .background(Capsule().fill(Theme.background.opacity(0.85)))
    .overlay(Capsule().stroke(pop.ext ? Theme.ext : .clear, lineWidth: 1))
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

/// A move part of the way along: forward from the board's position, or (`back`) the move
/// that led to it being taken back. `before` is the position the move was played from.
/// `progress` runs 0...1, and the pieces follow it on an S curve.
struct BoardSlide: Equatable {
  var move: LegalMove
  var before: String
  var back: Bool
  var progress: Double

  /// Where each moving piece is headed, the capture fading out, the one taken back, and how far along.
  func motion(_ pieces: [String: BoardPiece]) -> (moving: [String: String], fading: String?, returning: BoardPiece?, amount: Double) {
    let amount = (1 - cos(Double.pi * min(1, max(0, progress)))) / 2
    let from = move.from, to = move.to
    var moving: [String: String] = back ? [to: from] : [from: to]
    // Castling: the rook comes along.
    if move.piece == .k, abs(Int(from.utf8.first!) - Int(to.utf8.first!)) == 2 {
      let rank = String(from.last!)
      let rook = to.first == "g" ? ("h" + rank, "f" + rank) : ("a" + rank, "d" + rank)
      if back { moving[rook.1] = rook.0 } else { moving[rook.0] = rook.1 }
    }
    guard let captured = move.captured else { return (moving, nil, nil, amount) }
    // En passant takes a pawn beside the square moved to, which was empty.
    let enPassant = move.piece == .p && !piecesFromFen(before).contains { $0.square == to }
    let square = enPassant ? String(to.first!) + String(from.last!) : to
    if back {
      let mover = fenTurn(before)
      return (moving, nil, BoardPiece(square: square, type: captured, color: mover.other), amount)
    }
    return (moving, square, nil, amount)
  }
}
