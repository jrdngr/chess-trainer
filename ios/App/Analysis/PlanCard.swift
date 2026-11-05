import ChessCore
import Engine
import Model
import SwiftUI

/// A game's plan trail, kept so it grows a move at a time instead of being walked again on every draw.
@MainActor enum PlanTrails {
  private static var last: (fens: [String], me: ChessCore.Color, trail: PlanTrail)?

  /// The trail over these positions, the board last.
  static func of(_ fens: [String], _ me: ChessCore.Color) -> PlanTrail {
    if let last, last.me == me, last.fens == fens { return last.trail }
    var trail = PlanTrail()
    var from = 0
    if let last, last.me == me, last.fens.count < fens.count, Array(fens.prefix(last.fens.count)) == last.fens {
      trail = last.trail
      from = last.fens.count
    }
    for fen in fens[from...] { trail = advanceTrail(trail, fen, me) }
    last = (fens, me, trail)
    return trail
  }
}

/// The plan's cyan, on its label and the Plan lens.
enum PlanColors {
  static let plan = SwiftUI.Color(hex: 0x22c3e6)
  static let ink = SwiftUI.Color(hex: 0x04212a)
}

/// A plan's steps: numbered in the plan's cyan while open, ticked when done,
/// crossed when gone. A step the engine says to hold off on goes grey, as do the
/// open steps of a plan the game has left.
struct PlanSteps: View {
  let shown: ShownPlan
  var earlier = false
  var notYet: Set<Int> = []

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      ForEach(Array(shown.plan.steps.indices), id: \.self) { i in
        let mark = shown.marks[i]
        let waiting = mark == nil && !earlier && notYet.contains(i)
        let quiet = mark != nil || earlier || waiting
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          number(i, mark, grey: earlier || waiting)
            .font(.system(size: 13.5, weight: .heavy).monospacedDigit()).frame(minWidth: 10)
          words(shown.plan.runs[i], quiet: quiet).foregroundStyle(quiet ? Theme.text3 : Theme.text2)
          if waiting {
            Spacer(minLength: 4)
            Text("not yet").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Theme.text3).fixedSize()
          }
        }
        .font(.system(size: 13.5)).lineSpacing(2)
      }
    }
  }

  private func number(_ i: Int, _ mark: StepMark?, grey: Bool) -> Text {
    switch mark {
    case .done?: Text("\u{2713}").foregroundColor(Theme.good)
    case .gone?: Text("\u{2717}").foregroundColor(Theme.bad)
    case nil: Text("\(i + 1)").foregroundColor(grey ? Theme.text3 : PlanColors.plan)
    }
  }

  /// A step's words, its moves in bold: bright while the step is to do, dimmed with it otherwise.
  private func words(_ runs: [StepRun], quiet: Bool) -> Text {
    runs.reduce(Text("")) { out, run in
      out + (run.move ? Text(run.text).fontWeight(.bold).foregroundColor(quiet ? Theme.text3 : Theme.text) : Text(run.text))
    }
  }
}

/// The plan's name: a small cyan label over its headline.
struct PlanTitle: View {
  let plan: Plan

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(plan.label.uppercased()).font(.system(size: 11, weight: .heavy)).tracking(0.7)
        .foregroundStyle(PlanColors.plan).lineLimit(1)
      if let headline = plan.headline {
        Text(headline).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.text).lineLimit(2)
      }
    }
  }
}

/// The Plan lens held: the plan's name and its steps, where a lens key would show.
struct PlanLegend: View {
  /// The game's positions, the board last.
  let fens: [String]
  let me: ChessCore.Color

  init(fens: [String], me: ChessCore.Color) {
    self.fens = fens
    self.me = me
  }

  init(fen: String, me: ChessCore.Color) {
    self.init(fens: [fen], me: me)
  }

  var body: some View {
    let trail = PlanTrails.of(fens, me)
    if trail.current != nil {
      PlanCardBody(trail: trail, fen: fens.last!, me: me)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .planCardFrame()
        .padding(.top, 12)
    }
  }
}

/// The plan card's content: the plan's name, its steps, and the plans before it,
/// each of which turns the card to it on a tap.
struct PlanCardBody: View {
  let trail: PlanTrail
  let fen: String
  let me: ChessCore.Color
  /// The card's own row shows the name where it opens and closes.
  var title = true
  /// The earlier plan the card is turned to.
  @State private var viewing: String?
  @State private var notYet: (fen: String, key: String, steps: Set<Int>)?

  var body: some View {
    if let key = viewing, let old = trail.earlier.first(where: { $0.plan.key == key }), let current = trail.current {
      VStack(alignment: .leading, spacing: 10) {
        Button { viewing = nil } label: {
          HStack(spacing: 4) {
            Icon(name: "chevron", size: 13).rotationEffect(.degrees(180))
            Text(current.plan.label).font(.system(size: 13, weight: .semibold)).lineLimit(1)
          }
          .foregroundStyle(Theme.text2).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        PlanTitle(plan: old.plan)
        PlanSteps(shown: old, earlier: true)
      }
    } else if let current = trail.current {
      VStack(alignment: .leading, spacing: 10) {
        if title { PlanTitle(plan: current.plan) }
        PlanSteps(shown: current, notYet: waiting(current))
        if !trail.earlier.isEmpty {
          VStack(spacing: 6) {
            ForEach(trail.earlier.prefix(2), id: \.plan.key) { before($0) }
          }
          .padding(.top, 2)
        }
      }
      .task(id: checkKey(current)) { await check(current) }
    }
  }

  /// "Before: Dragon · Yugoslav ✓ 1 ✗ 1 ›", the tally only where it is not zero.
  private func before(_ shown: ShownPlan) -> some View {
    let tally = markTally(shown)
    return Button { viewing = shown.plan.key } label: {
      HStack(spacing: 8) {
        Text("Before: \(shown.plan.label)").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text2).lineLimit(1)
        Spacer(minLength: 4)
        if tally.done > 0 { Text("\u{2713} \(tally.done)").foregroundStyle(Theme.good) }
        if tally.gone > 0 { Text("\u{2717} \(tally.gone)").foregroundStyle(Theme.bad) }
        Icon(name: "chevron", size: 13).foregroundStyle(Theme.text3)
      }
      .font(.system(size: 12.5, weight: .heavy).monospacedDigit())
      .padding(.horizontal, 12).frame(minHeight: 36)
      .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface2))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  /* ── the engine's word on the open steps ── */

  /// Asked on your turn only, again when the board or a mark changes.
  private func checkKey(_ current: ShownPlan) -> String? {
    guard fenTurn(fen) == me else { return nil }
    return "\(fen)|\(current.plan.key)|\(current.marks.map { $0?.rawValue ?? "-" }.joined())"
  }

  private func waiting(_ current: ShownPlan) -> Set<Int> {
    guard let notYet, notYet.fen == fen, notYet.key == current.plan.key else { return [] }
    return notYet.steps
  }

  private func check(_ current: ShownPlan) async {
    guard checkKey(current) != nil else { return }
    let fen = fen
    let found = await PlanChecks.notYet(HintEngine.shared, fen, me, current.plan.steps, open: current.marks.map { $0 == nil })
    if !Task.isCancelled { notYet = (fen, current.plan.key, found) }
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
