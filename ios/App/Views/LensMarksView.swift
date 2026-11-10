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

  static func grade(_ grade: KingGrade) -> SwiftUI.Color {
    switch grade {
    case .safe: green
    case .exposed: amber
    case .attacked: red
    }
  }

  /// What a lens says about a piece, as the piece's own color: a ring's activity or a pawn's tag.
  static func pieceTints(_ marks: LensMarks?) -> [String: SwiftUI.Color] {
    guard let marks else { return [:] }
    var out: [String: SwiftUI.Color] = [:]
    for ring in marks.rings ?? [] { out[ring.square] = tone(ring.tone) }
    for tag in marks.tags ?? [] { out[tag.square] = tag.tone == "good" ? green : red }
    return out
  }

  static let tintAlpha: [Int: Double] = [1: 0.3, 2: 0.44, 3: 0.58]

  static func tone(_ tone: String) -> SwiftUI.Color {
    switch tone {
    case "warn": orange
    case "mine": blue
    case "good": green
    case "passive": amber
    case "route": lightBlue
    default: red
    }
  }
}

/// The marks under the pieces: tints, each king's zone, a pawn's square, holes, missing shield pawns.
struct LensUnderView: View {
  var marks: LensMarks
  var cell: CGFloat
  var position: (String) -> (col: Int, row: Int)

  var body: some View {
    ZStack(alignment: .topLeading) {
      // Keyed by position: two marks can share a square (both sides' key squares, both kings' zones).
      ForEach(Array((marks.tints ?? []).enumerated()), id: \.offset) { _, t in
        Rectangle().fill(LensColors.tint(t.color).opacity(LensColors.tintAlpha[t.strength] ?? 0.3)).at(t.square, cell, position)
      }
      // One outline per king around its zone, in the color of its grade.
      ForEach(marks.zone == nil ? [] : marks.shields ?? [], id: \.square) { king in
        let around = (marks.zone ?? []).map(position).filter { p in
          let k = position(king.square)
          return abs(p.col - k.col) <= 1 && abs(p.row - k.row) <= 1
        }
        if let left = around.map(\.col).min(), let right = around.map(\.col).max(),
          let top = around.map(\.row).min(), let bottom = around.map(\.row).max()
        {
          let color = LensColors.grade(king.grade)
          RoundedRectangle(cornerRadius: cell * 0.26).fill(color.opacity(0.12))
            .overlay(RoundedRectangle(cornerRadius: cell * 0.26).strokeBorder(color, lineWidth: 2.5))
            .padding(2)
            .frame(width: CGFloat(right - left + 1) * cell, height: CGFloat(bottom - top + 1) * cell)
            .offset(x: CGFloat(left) * cell, y: CGFloat(top) * cell)
        }
      }
      ForEach(marks.boxes ?? [], id: \.from) { box in
        let a = position(box.from), b = position(box.to)
        let col = min(a.col, b.col), row = min(a.row, b.row)
        let width = CGFloat(abs(a.col - b.col) + 1) * cell, height = CGFloat(abs(a.row - b.row) + 1) * cell
        Rectangle().fill(LensColors.green.opacity(0.12))
          .overlay(Rectangle().strokeBorder(LensColors.green, style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
          .frame(width: width, height: height)
          .offset(x: CGFloat(col) * cell, y: CGFloat(row) * cell)
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

/// The marks over the pieces: badges, passer letters, lines, guides and arrows. Rings and tags color the pieces themselves (`BoardView`).
struct LensOverView: View {
  var marks: LensMarks
  var cell: CGFloat
  var position: (String) -> (col: Int, row: Int)

  var body: some View {
    ZStack(alignment: .topLeading) {
      lines
      ForEach(marks.badges ?? [], id: \.self) { square in
        WorstBadge(size: cell * 0.32)
          .padding(cell * 0.04)
          .frame(width: cell, height: cell, alignment: .bottomLeading)
          .at(square, cell, position)
      }
      ForEach(marks.letters ?? [], id: \.square) { l in
        Text(l.text).font(.system(size: cell * 0.24, weight: .heavy))
          .foregroundStyle(.black.opacity(0.85))
          .frame(width: cell * 0.3, height: cell * 0.3)
          .background(Circle().fill(LensColors.green))
          .overlay(Circle().strokeBorder(.black.opacity(0.6), lineWidth: 1))
          .padding(cell * 0.04)
          .frame(width: cell, height: cell, alignment: .bottomTrailing)
          .at(l.square, cell, position)
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
        context.stroke(path, with: .color(LensColors.red.opacity(0.85)), style: StrokeStyle(lineWidth: cell * 0.065, lineCap: .round))
      }
      for guide in marks.guides ?? [] {
        var path = Path()
        path.move(to: center(guide.from))
        path.addLine(to: center(guide.to))
        let color = guide.tone == "cutoff" ? LensColors.amber : SwiftUI.Color(red: 245 / 255, green: 245 / 255, blue: 247 / 255)
        // A dark edge under the dashes keeps them readable on any square.
        context.stroke(path, with: .color(.black.opacity(0.5)), style: StrokeStyle(lineWidth: cell * 0.1, lineCap: .round))
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: cell * 0.07, lineCap: .round, dash: [cell * 0.2, cell * 0.12]))
      }
    }
  }

  private func center(_ square: String) -> CGPoint {
    let p = position(square)
    return CGPoint(x: (CGFloat(p.col) + 0.5) * cell, y: (CGFloat(p.row) + 0.5) * cell)
  }
}

extension View {
  /// Places a square-sized view on `square`.
  fileprivate func at(_ square: String, _ cell: CGFloat, _ position: (String) -> (col: Int, row: Int)) -> some View {
    let p = position(square)
    return frame(width: cell, height: cell).offset(x: CGFloat(p.col) * cell, y: CGFloat(p.row) * cell)
  }
}

/// The mark on a side's least active piece: a small red disc with a down arrow.
struct WorstBadge: View {
  var size: CGFloat

  var body: some View {
    Circle().fill(LensColors.lightRed)
      .overlay(Image(systemName: "arrow.down").font(.system(size: size * 0.62, weight: .heavy)).foregroundStyle(.black.opacity(0.8)))
      .overlay(Circle().strokeBorder(.black.opacity(0.6), lineWidth: 1.5))
      .frame(width: size, height: size)
  }
}
