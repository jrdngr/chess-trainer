import Model
import SwiftUI

/// The lobby's settings: past the book, and what the green arrow nudges toward.
/// How many moves a sitting adds is the main Settings' Moves per fill.
struct GrowthSettings: View {
  let prefs: GrowthPrefs
  let change: ((inout GrowthPrefs) -> Void) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      PlaySection(title: "Past the book")
      SegmentedControl(value: bind(\.pastBook), options: [(false, "Off"), (true, "On")])
      PlaySection(title: "Nudge toward")
      SegmentedControl(value: bind(\.nudgePriority), options: [(.transposition, "Transpositions"), (.habit, "Habits")])
      Text(prefs.nudgePriority == .transposition ? "Green arrow: a move into a line you already have." : "Green arrow: a move you already play here.")
        .font(.system(size: 12)).foregroundStyle(Theme.text3).lineSpacing(2)
        .padding(.horizontal, 4).padding(.top, 6)
      PlaySection(title: "Pawn structure")
      SegmentedControl(value: bind(\.nudgePawns), options: [(false, "Off"), (true, "Counts as a habit")])
    }
  }

  private func bind<T>(_ key: WritableKeyPath<GrowthPrefs, T>) -> Binding<T> {
    Binding(get: { prefs[keyPath: key] }, set: { value in change { $0[keyPath: key] = value } })
  }
}
