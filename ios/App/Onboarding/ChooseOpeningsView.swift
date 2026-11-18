import Book
import ChessCore
import Game
import Model
import SwiftUI

/// Welcome's "Choose my openings": the Playbook tree in its choosing mode, one side at a
/// time, and a bar of three slots under it: a White opening, a Black one against 1.e4 and one
/// against 1.d4. Tapping an opening fills its slot; Done appears once all three are filled.
struct ChooseOpeningsView: View {
  let tree: OpeningTree
  let onBack: () -> Void
  let onDone: ([String]) -> Void

  @State private var side = ChessCore.Color.w
  @State private var picks: [ChoiceSlot: String] = [:]

  var body: some View {
    VStack(spacing: 0) {
      OnbAppBar(title: "Choose your openings", onBack: onBack)
      SegmentedControl(value: $side, options: [(.w, "White"), (.b, "Black")])
        .padding(.horizontal, 16)
      PlaybookMapView(tree: tree, side: side, choosing: $picks)
        .id(side)
        .padding(.top, 4)
    }
    .safeAreaInset(edge: .bottom, spacing: 0) { bar }
    .background(Theme.background.ignoresSafeArea())
  }

  private var bar: some View {
    let full = ChoiceSlot.allCases.allSatisfy { picks[$0] != nil }
    return OnboardBar {
      HStack(spacing: 8) {
        ForEach(ChoiceSlot.allCases, id: \.self) { slot in
          Button { side = slot.color } label: { slotView(slot) }
            .buttonStyle(.plain)
        }
      }
      if full {
        BigButton(label: "Done") { onDone(ChoiceSlot.allCases.compactMap { picks[$0] }) }
          .padding(.top, 8)
          .transition(.opacity)
      }
    }
    .animation(.easeOut(duration: 0.2), value: full)
  }

  private func slotView(_ slot: ChoiceSlot) -> some View {
    let family = picks[slot]
    return VStack(spacing: 3) {
      Text(slot.label).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.text3).lineLimit(1)
      if let family {
        Text(curatedOpening(family)?.name ?? "")
          .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
          .lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.8)
      }
    }
    .padding(.horizontal, 6).frame(maxWidth: .infinity, minHeight: 58)
    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
    .overlay(
      RoundedRectangle(cornerRadius: 12)
        .strokeBorder(family == nil ? SwiftUI.Color(hex: 0x3a3a44) : Theme.accent, style: StrokeStyle(lineWidth: 1.5, dash: family == nil ? [4, 3] : []))
    )
    .contentShape(Rectangle())
  }
}
