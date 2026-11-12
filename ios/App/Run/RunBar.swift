import ChessCore
import Model
import SwiftUI

/// Run's app bar: close, "Run" over the selection, and what sits
/// on the right (the clock and the run's count). `AppBar` with `actions`.
struct RunBar<Actions: View>: View {
  /// The mode's name: Run, or Middlegame.
  var title = "Run"
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

/// The run's score in the app bar, said with its unit.
struct RunCount: View {
  var value: Int
  /// Points, when moments, missions or the combo score; else moves survived.
  var points: Bool
  var body: some View {
    Text("\(value) \(points ? "pt" : "move")\(value == 1 ? "" : "s")")
      .font(.system(size: 13, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.text2).fixedSize()
  }
}

/// The move clock: a ring that empties as the budget goes, then greys out
/// at nothing. Running out ends nothing.
struct RunClock: View {
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

/// The app bar over a run: the opening it is in, the clock on your
/// turn, and the run's points (or moves, with no extras on).
struct RunHeaderBar: View {
  let model: RunModel
  let onExit: () -> Void

  var body: some View {
    let state = model.session.state
    RunBar(title: "Middlegame", subtitle: openingName(model.tree, model.openingId), onClose: onExit) {
      if let budget = clockSeconds(model.prefs.clock), model.live, !model.held, model.myTurn {
        RunClock(budget: budget, since: model.turnStarted).id(model.turnStarted)
      }
      RunCount(value: model.scoredInPoints ? state.extras.points : state.moves, points: model.scoredInPoints)
      ModeSettingsButton()
    }
  }
}
