import ChessCore
import Model
import SwiftUI

/// Survival's app bar: close, "Survival" over the selection, and what sits
/// on the right (the clock and the run's count). `AppBar` with `actions`.
struct SurvivalBar<Actions: View>: View {
  /// The mode's name: Survival, or Middlegame.
  var title = "Survival"
  var subtitle: String?
  var onClose: () -> Void
  @ViewBuilder var actions: Actions

  var body: some View {
    HStack(spacing: 12) {
      IconButton(icon: "close", action: onClose)
      VStack(spacing: 1) {
        Text(title).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.text)
        if let subtitle { Text(subtitle).font(.system(size: 13)).foregroundStyle(Theme.text2) }
      }
      .lineLimit(1).frame(maxWidth: .infinity)
      HStack(spacing: 6) { actions }
    }
    .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 10).frame(minHeight: 56)
  }
}

/// A count in the app bar: `.chip.num.wide`.
struct SurvivalCountChip: View {
  var value: Int
  var body: some View {
    Text("\(value)").font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.text2)
      .padding(.horizontal, 10).padding(.vertical, 4).frame(minWidth: 52)
      .background(Capsule().fill(Theme.surface2))
  }
}

/// "Black · Queen's Gambit Declined": the side and the opening the run is in.
@MainActor
func runSubtitle(_ store: AppStore, _ color: ChessCore.Color, _ opening: String) -> String? {
  guard let tree = store.tree, let catalog = store.catalog else { return nil }
  return selectionText(tree, catalog, color == .w ? .w : .b, opening)
}

/// The move clock: a ring that empties as the budget goes, then greys out
/// at nothing. Running out ends nothing.
struct SurvivalClock: View {
  let budget: Double
  let since: Date

  var body: some View {
    TimelineView(.periodic(from: .now, by: 0.1)) { context in
      let left = max(0, budget - context.date.timeIntervalSince(since))
      let share = left / budget
      let out = left <= 0
      HStack(spacing: 7) {
        ZStack {
          Circle().stroke(out ? Theme.bad.opacity(0.14) : Theme.surface3, lineWidth: 4)
          if !out {
            Circle().trim(from: 0, to: share).stroke(share < 0.5 ? Theme.warn : Theme.good, lineWidth: 4)
              .rotationEffect(.degrees(-90))
          }
        }
        .frame(width: 14, height: 14).padding(2)
        Text("\(Int(left.rounded(.up)))").frame(minWidth: 16, alignment: .trailing)
      }
      .font(.system(size: 13, weight: .bold).monospacedDigit()).foregroundStyle(out ? Theme.text3 : Theme.text)
      .padding(.leading, 6).padding(.trailing, 10).padding(.vertical, 4)
      .background(Capsule().fill(Theme.surface2))
      .shake(on: out)
    }
  }
}

/// The app bar over a run: the side and opening it is in, the clock on your
/// turn, and the run's points (or moves, with no extras on).
struct SurvivalRunBar: View {
  let model: RunModel
  let onExit: () -> Void
  @Environment(AppStore.self) private var store

  var body: some View {
    let state = model.session.state
    SurvivalBar(title: model.handoff != nil ? "Middlegame" : "Survival", subtitle: runSubtitle(store, model.run.color, model.openingId), onClose: onExit) {
      if let budget = clockSeconds(model.prefs.clock), model.live, !model.held, model.myTurn {
        SurvivalClock(budget: budget, since: model.turnStarted).id(model.turnStarted)
      }
      SurvivalCountChip(value: model.scoredInPoints ? state.extras.points : state.moves)
    }
  }
}
