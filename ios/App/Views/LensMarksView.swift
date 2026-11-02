import Model
import SwiftUI

/// A held lens's marks on the board, under and over the pieces.
enum LensColors {
  static func rgb(_ r: Double, _ g: Double, _ b: Double) -> SwiftUI.Color { SwiftUI.Color(red: r / 255, green: g / 255, blue: b / 255) }
  static let blue = rgb(59, 130, 246)
  static let red = rgb(239, 68, 68)
  static let orange = rgb(249, 115, 22)
  static let green = rgb(34, 197, 94)
  static let amber = rgb(245, 158, 11)
  static let lightBlue = rgb(96, 165, 250)
  static let lightRed = rgb(248, 113, 113)

  static func tint(_ color: TintColor) -> SwiftUI.Color {
    switch color {
    case .blue: blue
    case .red: red
    case .purple: rgb(168, 85, 247)
    case .purpleBlue: rgb(125, 105, 250)
    case .purpleRed: rgb(205, 80, 190)
    case .green: green
    case .amber: amber
    }
  }

  static let tintAlpha: [Int: Double] = [1: 0.3, 2: 0.44, 3: 0.58]

  static func tone(_ tone: String) -> SwiftUI.Color {
    switch tone {
    case "warn": orange
    case "mine": blue
    case "good": green
    case "route": lightBlue
    default: red
    }
  }
}

/// The marks under the pieces: tints, a king's zone, holes, missing shield pawns.
struct LensUnderView: View {
  var marks: LensMarks
  var cell: CGFloat
  var position: (String) -> (col: Int, row: Int)

  var body: some View {
    ZStack(alignment: .topLeading) {
      ForEach(marks.tints ?? [], id: \.square) { t in
        Rectangle().fill(LensColors.tint(t.color).opacity(LensColors.tintAlpha[t.strength] ?? 0.3)).at(t.square, cell, position)
      }
      ForEach(marks.zone ?? [], id: \.self) { square in
        Rectangle().fill(SwiftUI.Color(red: 15 / 255, green: 23 / 255, blue: 42 / 255).opacity(0.3))
          .overlay(Rectangle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5).padding(2))
          .overlay(Rectangle().strokeBorder(.black.opacity(0.6), lineWidth: 2))
          .at(square, cell, position)
      }
      ForEach(marks.dots ?? [], id: \.self) { square in
        Circle().fill(LensColors.amber.opacity(0.9)).frame(width: cell * 0.22, height: cell * 0.22)
          .at(square, cell, position)
      }
      ForEach(marks.emptyPawns ?? [], id: \.self) { square in
        Circle().strokeBorder(LensColors.red.opacity(0.9), style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
          .frame(width: cell * 0.52, height: cell * 0.52).at(square, cell, position)
      }
    }
    .allowsHitTesting(false)
  }
}

/// The marks over the pieces: rings, tags, stars, pips, shields, lines and arrows.
struct LensOverView: View {
  var marks: LensMarks
  var cell: CGFloat
  var position: (String) -> (col: Int, row: Int)

  var body: some View {
    ZStack(alignment: .topLeading) {
      lines
      ForEach(marks.rings ?? [], id: \.square) { r in
        Circle().strokeBorder(LensColors.tone(r.tone), lineWidth: 3).at(r.square, cell, position)
      }
      ForEach(marks.tags ?? [], id: \.square) { t in
        Circle().fill(t.tone == "good" ? LensColors.green : LensColors.red)
          .frame(width: cell * 0.24, height: cell * 0.24)
          .padding(cell * 0.07)
          .frame(width: cell, height: cell, alignment: .topTrailing)
          .at(t.square, cell, position)
      }
      ForEach(marks.stars ?? [], id: \.square) { s in
        Text("\u{2605}").font(.system(size: cell * 0.3)).foregroundStyle(s.side == .mine ? LensColors.lightBlue : LensColors.lightRed)
          .shadow(color: .black.opacity(0.6), radius: 1, y: 1)
          .padding(.horizontal, cell * 0.06).padding(.vertical, cell * 0.02)
          .frame(width: cell, height: cell, alignment: .topLeading)
          .at(s.square, cell, position)
      }
      ForEach(marks.pips ?? [], id: \.square) { p in
        HStack(spacing: 2) {
          ForEach(0..<min(p.attackers, 4), id: \.self) { _ in Circle().fill(LensColors.lightRed).frame(width: 5, height: 5) }
          ForEach(0..<min(p.defenders, 4), id: \.self) { _ in Circle().fill(LensColors.lightBlue).frame(width: 5, height: 5) }
        }
        .padding(.horizontal, 3).padding(.vertical, 2)
        .background(Capsule().fill(.black.opacity(0.45)))
        .padding(.bottom, cell * 0.05)
        .frame(width: cell, height: cell, alignment: .bottom)
        .at(p.square, cell, position)
      }
      ForEach(marks.shields ?? [], id: \.square) { s in
        ShieldShape().fill(s.grade == .safe ? LensColors.green : s.grade == .exposed ? LensColors.amber : LensColors.red)
          .frame(width: cell * 0.38, height: cell * 0.38)
          .shadow(color: .black.opacity(0.6), radius: 1, y: 1)
          .padding(cell * 0.03)
          .frame(width: cell, height: cell, alignment: .topTrailing)
          .at(s.square, cell, position)
      }
      ArrowsView(
        arrows: (marks.arrows ?? []).map { BoardArrow(from: $0.from, to: $0.to, color: LensColors.tone($0.tone)) },
        cell: cell, position: position, origins: false)
    }
    .allowsHitTesting(false)
  }

  private var lines: some View {
    Canvas { context, _ in
      for line in marks.lines ?? [] {
        var path = Path()
        path.move(to: center(line.from))
        path.addLine(to: center(line.to))
        context.stroke(
          path, with: .color(LensColors.red.opacity(0.6)),
          style: StrokeStyle(lineWidth: cell * 0.07, lineCap: .round, dash: [cell * 0.18, cell * 0.12]))
      }
    }
  }

  private func center(_ square: String) -> CGPoint {
    let p = position(square)
    return CGPoint(x: (CGFloat(p.col) + 0.5) * cell, y: (CGFloat(p.row) + 0.5) * cell)
  }
}

/// The king's shield, on a 24-point grid.
struct ShieldShape: Shape {
  func path(in rect: CGRect) -> Path {
    SVGPath.parse("M12 2 4 5v6c0 5 3.4 9.4 8 11 4.6-1.6 8-6 8-11V5l-8-3z")
      .applying(CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: rect.width / 24, y: rect.height / 24))
  }
}

extension View {
  /// Places a square-sized view on `square`.
  fileprivate func at(_ square: String, _ cell: CGFloat, _ position: (String) -> (col: Int, row: Int)) -> some View {
    let p = position(square)
    return frame(width: cell, height: cell).offset(x: CGFloat(p.col) * cell, y: CGFloat(p.row) * cell)
  }
}
