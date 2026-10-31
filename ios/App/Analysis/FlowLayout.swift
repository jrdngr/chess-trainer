import SwiftUI

/// Views in rows, wrapping to the next when one is full: `.strip.wrapped`.
struct AnalysisFlowLayout: Layout {
  var spacing: CGFloat = 4

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let rows = arrange(proposal.width ?? .infinity, subviews)
    let width = rows.map(\.width).max() ?? 0
    let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
    return CGSize(width: proposal.width ?? width, height: height)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    var y = bounds.minY
    for row in arrange(bounds.width, subviews) {
      var x = bounds.minX
      for i in row.items {
        let size = subviews[i].sizeThatFits(.unspecified)
        subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
        x += size.width + spacing
      }
      y += row.height + spacing
    }
  }

  private struct Row {
    var items: [Int] = []
    var width: CGFloat = 0
    var height: CGFloat = 0
  }

  private func arrange(_ maxWidth: CGFloat, _ subviews: Subviews) -> [Row] {
    var rows: [Row] = [Row()]
    for (i, view) in subviews.enumerated() {
      let size = view.sizeThatFits(.unspecified)
      let extra = rows[rows.count - 1].items.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
      if extra > maxWidth && !rows[rows.count - 1].items.isEmpty {
        rows.append(Row())
      }
      var row = rows[rows.count - 1]
      row.width = row.items.isEmpty ? size.width : row.width + spacing + size.width
      row.height = max(row.height, size.height)
      row.items.append(i)
      rows[rows.count - 1] = row
    }
    return rows.filter { !$0.items.isEmpty }
  }
}
