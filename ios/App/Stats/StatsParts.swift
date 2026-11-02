import SwiftUI

/// A section's title, and an aside on the right.
struct StatsSection: View {
  var title: String
  var aside: String?
  var first = false

  var body: some View {
    HStack {
      Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text2)
      Spacer()
      if let aside { Text(aside).font(.system(size: 12)).foregroundStyle(Theme.text3) }
    }
    .padding(.horizontal, 4).padding(.top, first ? 8 : 24).padding(.bottom, 8)
  }
}

/// A plain surface: `.card`.
struct StatsCard<Content: View>: View {
  @ViewBuilder var content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 0) { content }
      .padding(16).frame(maxWidth: .infinity, alignment: .leading)
      .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
  }
}

/// The big number at the top of a page: `.hero`.
struct StatsHero<Content: View>: View {
  var big: String
  var label: String
  @ViewBuilder var content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(big).font(.system(size: 56, weight: .heavy).monospacedDigit()).tracking(-2.24).foregroundStyle(Theme.text)
        .frame(height: 56)
      Text(label).font(.system(size: 15)).foregroundStyle(Theme.text2).padding(.top, 4)
      content
    }
    .padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 22).fill(Theme.surface))
  }
}

/// A figure in a rounded pill, the number bold: `.pill`.
struct StatsPill: View {
  var dot: Color?
  var bold: String?
  var text: String

  var body: some View {
    HStack(spacing: 6) {
      if let dot { Circle().fill(dot).frame(width: 7, height: 7) }
      if let bold { Text(bold).font(.system(size: 13, weight: .bold).monospacedDigit()).foregroundStyle(Theme.text) }
      Text(text).font(.system(size: 13, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.text2)
    }
    .padding(.horizontal, 11).padding(.vertical, 6)
    .background(Capsule().fill(Theme.surface2))
  }
}

/// Small print under a control: `.note`.
struct StatsNote: View {
  var text: Text
  var center = false

  var body: some View {
    text.font(.system(size: 12)).foregroundStyle(Theme.text3).lineSpacing(2.5)
      .multilineTextAlignment(center ? .center : .leading)
      .frame(maxWidth: .infinity, alignment: center ? .center : .leading)
      .padding(.horizontal, 4)
  }
}

/// Views laid left to right, wrapping onto new lines: `flex-wrap`.
struct FlowRow: Layout {
  var spacing: CGFloat = 8

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let rows = arrange(proposal.width ?? .infinity, subviews)
    return CGSize(width: rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    for row in arrange(bounds.width, subviews) {
      var x = bounds.minX
      for i in row.items {
        let size = subviews[i].sizeThatFits(.unspecified)
        subviews[i].place(at: CGPoint(x: x, y: bounds.minY + row.y + (row.height - size.height) / 2), proposal: .unspecified)
        x += size.width + spacing
      }
    }
  }

  private struct Row { var items: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0; var y: CGFloat = 0 }

  private func arrange(_ width: CGFloat, _ subviews: Subviews) -> [Row] {
    var rows: [Row] = []
    var row = Row()
    for i in subviews.indices {
      let size = subviews[i].sizeThatFits(.unspecified)
      if !row.items.isEmpty && row.width + spacing + size.width > width {
        rows.append(row)
        row = Row(y: row.y + row.height + spacing)
      }
      row.width += (row.items.isEmpty ? 0 : spacing) + size.width
      row.height = max(row.height, size.height)
      row.items.append(i)
    }
    if !row.items.isEmpty { rows.append(row) }
    return rows
  }
}
