import Model
import SwiftUI

/// The Extensions review's graph, drawn from `layoutGraph`'s rows: book
/// moves filled, extensions outlined, a saved mistake with a warning mark.
/// White's columns carry the move numbers. `ExtensionGraph.tsx`.
struct ExtensionGraphView: View {
  let rows: [GraphRow]
  /// The ply of column 0's moves: 0 is White's first move.
  let rootPly: Int
  let selected: String?
  let onSelect: (String) -> Void

  static let x0: CGFloat = 24, cw: CGFloat = 41, nw: CGFloat = 37, nh: CGFloat = 26, rh: CGFloat = 36, top: CGFloat = 30
  private func cx(_ col: Int) -> CGFloat { Self.x0 + CGFloat(col) * Self.cw }
  private func ry(_ row: Int) -> CGFloat { Self.top + CGFloat(row) * Self.rh }

  var body: some View {
    let cols = max(1, rows.map { $0.start + $0.cells.count }.max() ?? 1)
    let joins = rows.contains { $0.cells.contains { $0.kind == .join } }
    let width = Self.x0 + CGFloat(cols) * Self.cw + (joins ? 18 : 8)
    let height = Self.top + CGFloat(rows.count) * Self.rh
    ZStack(alignment: .topLeading) {
      Canvas { context, _ in draw(context, cols: cols, height: height) }
      ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
        ForEach(Array(row.cells.enumerated()), id: \.offset) { j, cell in
          cellView(cell).offset(x: cx(row.start + j), y: ry(i))
        }
      }
      if joins {
        ForEach(rows.indices, id: \.self) { i in
          Text("\(i + 1)").font(.system(size: 10)).foregroundStyle(SwiftUI.Color(hex: 0x3a3a44))
            .frame(width: 16, alignment: .trailing).offset(x: width - 20, y: ry(i) + 6)
        }
      }
    }
    .frame(width: width, height: height, alignment: .topLeading)
  }

  private func draw(_ context: GraphicsContext, cols: Int, height: CGFloat) {
    for c in 0..<cols {
      let ply = rootPly + c
      let label: String? = ply % 2 == 0 ? "\(ply / 2 + 1)." : c == 0 ? "\((ply + 1) / 2)..." : nil
      if ply % 2 == 0 {
        context.fill(Path(roundedRect: CGRect(x: cx(c) - 2, y: 22, width: Self.cw * 2 - 2, height: height - 22), cornerRadius: 6),
                     with: .color(.white.opacity(0.025)))
      }
      if let label {
        context.draw(Text(label).font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.text3), at: CGPoint(x: cx(c) + Self.nw / 2, y: 14))
      }
    }
    guard !rows.isEmpty else { return }
    let mid = Self.nh / 2
    context.fill(Path(ellipseIn: CGRect(x: 3, y: ry(0) + mid - 5, width: 10, height: 10)), with: .color(Theme.accent))
    func stroke(_ path: Path, ext: Bool, join: Bool = false) {
      context.stroke(path, with: .color(Theme.accent.opacity(ext ? 0.65 : 1)), style: StrokeStyle(lineWidth: 2, dash: join ? [2, 2] : []))
    }
    let isExt = { (cell: GraphCell?) in cell.map { $0.kind != .move(.book) } ?? false }
    for (i, row) in rows.enumerated() {
      let y = ry(i) + mid
      if let parent = row.parent {
        let gx = cx(row.start) - 3
        var p = Path()
        p.move(to: CGPoint(x: cx(parent.col) + Self.nw, y: ry(parent.row) + mid))
        p.addLine(to: CGPoint(x: gx, y: ry(parent.row) + mid))
        p.addLine(to: CGPoint(x: gx, y: y - 6))
        p.addQuadCurve(to: CGPoint(x: gx + 5, y: y), control: CGPoint(x: gx, y: y))
        stroke(p, ext: isExt(row.cells.first))
      } else {
        var p = Path()
        p.move(to: CGPoint(x: 8, y: ry(0) + mid))
        if i == 0 {
          p.addLine(to: CGPoint(x: cx(0), y: ry(0) + mid))
        } else {
          p.addLine(to: CGPoint(x: 8, y: y - 8))
          p.addQuadCurve(to: CGPoint(x: 16, y: y), control: CGPoint(x: 8, y: y))
          p.addLine(to: CGPoint(x: cx(0), y: y))
        }
        stroke(p, ext: isExt(row.cells.first))
      }
      for j in 0..<max(0, row.cells.count - 1) {
        let a = cx(row.start + j) + Self.nw
        let next = row.cells[j + 1]
        var p = Path()
        p.move(to: CGPoint(x: a, y: y))
        p.addLine(to: CGPoint(x: a + Self.cw - Self.nw, y: y))
        stroke(p, ext: isExt(next), join: next.kind == .join)
      }
    }
  }

  @ViewBuilder private func cellView(_ cell: GraphCell) -> some View {
    let book = cell.kind == .move(.book)
    let quiet = cell.kind == .join || cell.kind == .more
    let picked = cell.nodeId != nil && cell.nodeId == selected
    ZStack {
      if picked {
        RoundedRectangle(cornerRadius: 9).stroke(Theme.text, lineWidth: 2).frame(width: Self.nw + 8, height: Self.nh + 8)
      }
      RoundedRectangle(cornerRadius: 7)
        .fill(book ? Theme.accent : quiet ? Theme.surface : Theme.background)
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(quiet ? SwiftUI.Color(hex: 0x3a3a44) : Theme.accent, lineWidth: 1.5))
        .frame(width: Self.nw, height: Self.nh)
      Text(cell.label).font(.system(size: cell.label.count >= 5 ? 11 : 12, weight: .heavy, design: .monospaced))
        .foregroundStyle(book ? Theme.accentInk : quiet ? Theme.text2 : Theme.ext).lineLimit(1).minimumScaleFactor(0.7)
        .frame(width: Self.nw - 2)
      if cell.kind == .move(.mistake) {
        Path { p in
          p.move(to: CGPoint(x: Self.nw - 2, y: -7))
          p.addLine(to: CGPoint(x: Self.nw + 4, y: 4))
          p.addLine(to: CGPoint(x: Self.nw - 8, y: 4))
          p.closeSubpath()
        }
        .fill(Theme.background).overlay(
          Path { p in
            p.move(to: CGPoint(x: Self.nw - 2, y: -7))
            p.addLine(to: CGPoint(x: Self.nw + 4, y: 4))
            p.addLine(to: CGPoint(x: Self.nw - 8, y: 4))
            p.closeSubpath()
          }
          .stroke(Theme.warn, style: StrokeStyle(lineWidth: 1.8, lineJoin: .round)))
        .frame(width: Self.nw, height: Self.nh, alignment: .topLeading)
      }
    }
    .frame(width: Self.nw, height: Self.nh)
    .contentShape(Rectangle())
    .onTapGesture { if let id = cell.nodeId { onSelect(id) } }
  }
}
