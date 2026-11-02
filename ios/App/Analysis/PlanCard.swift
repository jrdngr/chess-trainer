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
      HStack(alignment: .top, spacing: 4) {
        Button { open.toggle() } label: {
          HStack(alignment: .center, spacing: 8) {
            PlanTitle(structure: structure, me: me)
            Icon(name: "chevron", size: 16).foregroundStyle(Theme.text3).rotationEffect(.degrees(open ? -90 : 90)).animation(.easeInOut(duration: 0.15), value: open)
            Spacer(minLength: 0)
          }
          .padding(.vertical, 8).contentShape(Rectangle())
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
    .padding(.leading, 14).padding([.trailing, .vertical], 4)
    .planCardFrame()
    .padding(.top, 8)
  }

  private func steps(_ structure: Structure) -> some View {
    PlanSteps(fen: fen, me: me, structure: structure).padding(.trailing, 10).padding(.bottom, 10)
  }
}

/// The plan's cyan, on its label and the Plan lens.
enum PlanColors {
  static let plan = SwiftUI.Color(hex: 0x22c3e6)
  static let ink = SwiftUI.Color(hex: 0x04212a)
}

/// The plan's steps, numbered in the plan's cyan, the moves they name in bold,
/// ticked where a step's square is reached.
struct PlanSteps: View {
  let fen: String
  let me: ChessCore.Color
  let structure: Structure

  var body: some View {
    let steps = planFor(structure, me)
    let runs = planRuns(structure, me)
    VStack(alignment: .leading, spacing: 6) {
      ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
        let done = step.goals?.contains { goalRoute(fen, me, $0).done } ?? false
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text("\(i + 1)").font(.system(size: 13.5, weight: .heavy).monospacedDigit())
            .foregroundStyle(done ? Theme.good : PlanColors.plan)
          words(runs[i], done: done).foregroundStyle(done ? Theme.text3 : Theme.text2)
        }
        .font(.system(size: 13.5)).lineSpacing(2)
      }
    }
  }

  /// A step's words, its moves in bold: bright while the step is to do, dimmed with it once done.
  private func words(_ runs: [StepRun], done: Bool) -> Text {
    runs.reduce(Text("")) { out, run in
      out + (run.move ? Text(run.text).fontWeight(.bold).foregroundColor(done ? Theme.text3 : Theme.text) : Text(run.text))
    }
  }
}

/// The plan's name: the structure as a small cyan label over your plan's headline.
struct PlanTitle: View {
  let structure: Structure
  let me: ChessCore.Color

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(structureLabel(structure).uppercased()).font(.system(size: 11, weight: .heavy)).tracking(0.7)
        .foregroundStyle(PlanColors.plan).lineLimit(1)
      if let headline = planHeadline(structure, me) {
        Text(headline).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.text).lineLimit(2)
      }
    }
  }
}

/// The Plan lens held: the plan's name and its steps, where a lens key would show.
struct PlanLegend: View {
  let fen: String
  let me: ChessCore.Color

  var body: some View {
    if let structure = structureOf(fen) {
      PlanCardBody(fen: fen, me: me, structure: structure)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .planCardFrame()
        .padding(.top, 12)
    }
  }
}

/// The plan card's content: the plan's name, then the steps.
struct PlanCardBody: View {
  let fen: String
  let me: ChessCore.Color
  let structure: Structure

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      PlanTitle(structure: structure, me: me)
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
