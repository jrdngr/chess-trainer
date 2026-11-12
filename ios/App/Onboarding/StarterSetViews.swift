import Game
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

