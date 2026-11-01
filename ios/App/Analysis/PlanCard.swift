import ChessCore
import Model
import SwiftUI

/// The plan for the pawn structure on the board: a row that opens on a tap,
/// and a × that puts it away until the structure changes. `usePlanCard`.
struct PlanCard: View {
  let fen: String
  let me: ChessCore.Color
  @State private var open = false
  /// The structure whose card was put away.
  @State private var dismissed: String?

  var body: some View {
    if let structure = structureOf(fen), dismissed != key(structure) {
      card(structure)
    }
  }

  private func key(_ s: Structure) -> String { "\(s.template.id):\(s.a.rawValue)" }

  private func card(_ structure: Structure) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 4) {
        Button { open.toggle() } label: {
          HStack(spacing: 8) {
            Text("PLAN").font(.system(size: 12, weight: .bold)).tracking(0.5).foregroundStyle(Color(hex: 0x22c3e6))
            Text(structureLabel(structure)).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
            Icon(name: "chevron", size: 16).foregroundStyle(Theme.text3).rotationEffect(.degrees(open ? -90 : 90)).animation(.easeInOut(duration: 0.15), value: open)
            Spacer(minLength: 0)
          }
          .padding(.vertical, 6).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        Button {
          dismissed = key(structure)
          open = false
        } label: {
          Icon(name: "close", size: 16).foregroundStyle(Theme.text2).frame(width: 32, height: 32)
        }
        .buttonStyle(.plain).accessibilityLabel("Hide plan")
      }
      if open { steps(structure) }
    }
    .padding(.leading, 12).padding([.trailing, .vertical], 4)
    .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
    .padding(.top, 8)
  }

  private func steps(_ structure: Structure) -> some View {
    let steps = planFor(structure, me)
    return VStack(alignment: .leading, spacing: 4) {
      ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
        let done = step.goals?.contains { goalRoute(fen, me, $0).done } ?? false
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Text("\(i + 1).").foregroundStyle(Theme.text2)
          if done { Icon(name: "check", size: 14).foregroundStyle(Theme.good) }
          Text(step.text).foregroundStyle(done ? Theme.text3 : Theme.text2)
        }
        .font(.system(size: 13.5)).lineSpacing(2)
      }
    }
    .padding(.leading, 4).padding(.trailing, 8).padding(.bottom, 8)
  }
}
