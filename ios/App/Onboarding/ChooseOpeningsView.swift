import Book
import ChessCore
import Game
import Model
import SwiftUI

/// Welcome's "Choose my openings": three slots filled in order, a White opening, a Black one
/// against 1.e4 and one against 1.d4. The tree shows only the slot being filled, which the bar
/// under it highlights. Tapping an opening fills that slot and moves on; a filled slot can be
/// tapped to change it. Done appears once all three are filled.
struct ChooseOpeningsView: View {
  let tree: OpeningTree
  let onBack: () -> Void
  let onDone: ([String]) -> Void

  @State private var choosing = Choosing()

  var body: some View {
    VStack(spacing: 0) {
      OnbAppBar(title: "Choose your openings", onBack: onBack)
      PlaybookMapView(tree: tree, side: choosing.slot.color, choosing: $choosing)
        .id(choosing.slot)
        .padding(.top, 4)
        .transition(.opacity)
    }
    .safeAreaInset(edge: .bottom, spacing: 0) { bar }
    .background(Theme.background.ignoresSafeArea())
  }

  private var bar: some View {
    let full = choosing.done
    return OnboardBar {
      HStack(spacing: 8) {
        ForEach(ChoiceSlot.allCases, id: \.self) { slot in
          Button { withAnimation(.easeOut(duration: 0.2)) { choosing.open(slot) } } label: { slotView(slot) }
            .buttonStyle(.plain)
            .disabled(!choosing.canOpen(slot))
        }
      }
      if full {
        BigButton(label: "Done") { if let ids = choosing.ids { onDone(ids) } }
          .padding(.top, 8)
          .transition(.opacity)
      }
    }
    .animation(.easeOut(duration: 0.2), value: full)
  }

  private func slotView(_ slot: ChoiceSlot) -> some View {
    let family = choosing.picks[slot]
    let current = slot == choosing.slot
    return VStack(spacing: 3) {
      Text(slot.label).font(.system(size: 11, weight: .semibold))
        .foregroundStyle(current ? Theme.accent : Theme.text3).lineLimit(1)
      if let family {
        Text(curatedOpening(family)?.name ?? "")
          .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
          .lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.8)
      }
    }
    .padding(.horizontal, 6).frame(maxWidth: .infinity, minHeight: 58)
    .background(RoundedRectangle(cornerRadius: 12).fill(current ? Theme.accent.opacity(0.14) : Theme.surface))
    .overlay(
      RoundedRectangle(cornerRadius: 12)
        .strokeBorder(
          current || family != nil ? Theme.accent : SwiftUI.Color(hex: 0x3a3a44),
          style: StrokeStyle(lineWidth: current ? 2 : 1.5, dash: current || family != nil ? [] : [4, 3])
        )
    )
    .opacity(choosing.canOpen(slot) ? 1 : 0.45)
    .contentShape(Rectangle())
  }
}
