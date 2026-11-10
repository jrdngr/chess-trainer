import Model
import SwiftUI

/// Pick a style: every starter set by name, with the openings it gives each side. `SetList`.
struct SetListView: View {
  let tree: OpeningTree
  let onBack: () -> Void
  let onOpen: (String) -> Void

  var body: some View {
    VStack(spacing: 0) {
      OnbAppBar(title: "Pick a style", large: true, onBack: onBack)
      ScrollView {
        VStack(spacing: 10) {
          ForEach(STARTER_SETS, id: \.id) { set in
            Button { onOpen(set.id) } label: { card(set) }.buttonStyle(.plain)
          }
        }
        .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 20)
      }
    }
  }

  private func card(_ set: StarterSet) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(set.name).font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.text)
      ForEach(slotsOf(set), id: \.self) { slot in
        HStack(spacing: 8) {
          SideDot(side: SLOT_COLOR[slot]!)
          Text(slotNames(tree, set, slot).joined(separator: ", ")).font(.system(size: 14)).foregroundStyle(Theme.text2).lineLimit(1)
        }
      }
    }
    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
    // The first set is the one to start with: it carries the accent, like Suggest a set.
    .overlay { if set.id == STARTER_SETS[0].id { RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.accent, lineWidth: 1.5) } }
    .contentShape(Rectangle())
  }
}

/// A set's page: each slot's opening on a small board, and Use. `SetDetail`.
struct SetDetailView: View {
  let tree: OpeningTree
  let set: StarterSet
  let onBack: () -> Void
  let onUse: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      OnbAppBar(title: set.name, large: true, onBack: onBack)
      ScrollView {
        VStack(alignment: .leading, spacing: 10) {
          Text(set.description).font(.system(size: 14)).foregroundStyle(Theme.text2).lineSpacing(1.5)
            .padding(.horizontal, 4).padding(.bottom, 4)
          ForEach(slotsOf(set), id: \.self) { slot in slotCard(slot) }
        }
        .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 20)
      }
      OnboardBar { BigButton(label: "Use \(set.name)", action: onUse) }
    }
  }

  private func slotCard(_ slot: SetSlot) -> some View {
    let color = SLOT_COLOR[slot]!
    let moves = setMoves(set, slot)
    return HStack(spacing: 14) {
      MiniBoard(sans: line(set.slots[slot]![0].id), orientation: color, size: 88, lastMove: true)
        .clipShape(RoundedRectangle(cornerRadius: 6))
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 6) {
          SideSquare(color: color, size: 11)
          Text(SLOT_LABELS[slot]!.uppercased()).font(.system(size: 12, weight: .bold)).tracking(0.6).foregroundStyle(Theme.text2)
        }
        Text(slotNames(tree, set, slot).joined(separator: " \u{00b7} ")).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.text)
        Text(plural(moves, "move")).font(.system(size: 13)).foregroundStyle(Theme.text3)
      }
      Spacer(minLength: 0)
    }
    .padding(12)
    .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
  }
}

/// Chips that wrap onto as many lines as they need.
struct FlowLayout: Layout {
  var spacing: CGFloat = 6

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let rows = arrange(proposal.width ?? .infinity, subviews)
    let width = rows.map { $0.width }.max() ?? 0
    let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
    return CGSize(width: proposal.width ?? width, height: height)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    var y = bounds.minY
    for row in arrange(bounds.width, subviews) {
      var x = bounds.minX
      for i in row.items {
        let size = subviews[i].sizeThatFits(.unspecified)
        subviews[i].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
        x += size.width + spacing
      }
      y += row.height + spacing
    }
  }

  private func arrange(_ width: CGFloat, _ subviews: Subviews) -> [(items: [Int], width: CGFloat, height: CGFloat)] {
    var rows: [(items: [Int], width: CGFloat, height: CGFloat)] = []
    for (i, view) in subviews.enumerated() {
      let size = view.sizeThatFits(.unspecified)
      if let last = rows.last, last.width + spacing + size.width <= width {
        rows[rows.count - 1].items.append(i)
        rows[rows.count - 1].width += spacing + size.width
        rows[rows.count - 1].height = max(last.height, size.height)
      } else {
        rows.append(([i], size.width, size.height))
      }
    }
    return rows
  }
}
