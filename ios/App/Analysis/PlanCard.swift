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
            Text("PLAN").font(.system(size: 12, weight: .bold)).tracking(0.5).foregroundStyle(PlanColors.plan)
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
    PlanSteps(fen: fen, me: me, structure: structure).padding(.leading, 4).padding(.trailing, 8).padding(.bottom, 8)
  }
}

/// The plan's cyan, on its label and the Plan lens.
enum PlanColors {
  static let plan = SwiftUI.Color(hex: 0x22c3e6)
  static let ink = SwiftUI.Color(hex: 0x04212a)
}

/// The plan's steps, ticked where a step's square is reached.
struct PlanSteps: View {
  let fen: String
  let me: ChessCore.Color
  let structure: Structure

  var body: some View {
    let steps = planFor(structure, me)
    VStack(alignment: .leading, spacing: 4) {
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
  }
}

/// The Plan lens held: the structure's name and its steps, where a lens key would show.
struct PlanLegend: View {
  let fen: String
  let me: ChessCore.Color

  var body: some View {
    if let structure = structureOf(fen) {
      VStack(alignment: .leading, spacing: 8) {
        Text(structureLabel(structure)).font(.system(size: 14, weight: .semibold)).foregroundStyle(PlanColors.plan)
        PlanSteps(fen: fen, me: me, structure: structure)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 14).padding(.vertical, 12)
      .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
      .padding(.top, 12)
    }
  }
}

/// The plan card's content: the structure as its label, then the steps.
struct PlanCardBody: View {
  let fen: String
  let me: ChessCore.Color
  let structure: Structure

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(structureLabel(structure).uppercased()).font(.system(size: 11, weight: .heavy)).tracking(0.7)
        .foregroundStyle(PlanColors.plan).lineLimit(1)
      PlanSteps(fen: fen, me: me, structure: structure)
    }
  }
}

extension View {
  /// The plan card's ground: a surface with the plan's cyan along its top edge.
  func planCardFrame() -> some View {
    background(Theme.surface)
      .overlay(alignment: .top) { Rectangle().fill(PlanColors.plan).frame(height: 2) }
      .clipShape(RoundedRectangle(cornerRadius: 16))
  }
}
