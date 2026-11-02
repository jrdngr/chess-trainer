import Model
import SwiftUI

/// The lobby's settings: how common a reply must be, how deep, past the
/// book, and what the green arrow nudges toward.
struct GrowthSettings: View {
  let prefs: GrowthPrefs
  let change: ((inout GrowthPrefs) -> Void) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      PlaySection(title: "Worth answering")
      SegmentedControl(
        value: bind(\.minShare), options: SHARE_STEPS.map { ($0, shareLabel($0)) })
      PlaySection(title: "How deep")
      SegmentedControl(
        value: bind(\.maxPly), options: GROWTH_DEPTHS.map { ($0, "\(Int((Double($0) / 2).rounded(.up))) moves") })
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
