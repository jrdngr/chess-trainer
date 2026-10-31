import SwiftUI

/// Horizontal bars for a few named things, one hue, value at the tip:
/// `BarList` in `charts.tsx`.
struct BarList: View {
  struct Row {
    var label: String
    var value: Int
    var highlight = false
  }

  var rows: [Row]
  var color: Color

  var body: some View {
    let top = max(1, rows.map(\.value).max() ?? 0)
    VStack(spacing: 8) {
      ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
        HStack(spacing: 10) {
          Text(row.label).font(.system(size: 13, weight: .semibold))
            .foregroundStyle(row.highlight ? Theme.text : Theme.text2).lineLimit(1)
            .frame(width: 110, alignment: .leading)
          GeometryReader { geo in
            UnevenRoundedRectangle(bottomTrailingRadius: 4, topTrailingRadius: 4).fill(color)
              .frame(width: max(2, geo.size.width * CGFloat(row.value) / CGFloat(top)))
          }
          .frame(height: 12)
          .background(Theme.surface2)
          .clipShape(RoundedRectangle(cornerRadius: 4))
          Text("\(row.value)").font(.system(size: 13).monospacedDigit()).foregroundStyle(Theme.text2)
            .frame(width: 40, alignment: .trailing)
        }
      }
    }
  }
}
