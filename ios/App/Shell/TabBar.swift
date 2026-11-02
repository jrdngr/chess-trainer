/// The four tabs, shown in the system tab bar.
enum Tab: String, CaseIterable {
  case home, playbook, stats, analysis

  var label: String {
    switch self {
    case .home: "Home"
    case .playbook: "Playbook"
    case .stats: "Stats"
    case .analysis: "Analysis"
    }
  }

  /// Each tab's SF Symbol: a bolt, a branching tree, a line chart, a magnifier.
  var symbol: String {
    switch self {
    case .home: "bolt.fill"
    case .playbook: "arrow.triangle.branch"
    case .stats: "chart.xyaxis.line"
    case .analysis: "magnifyingglass"
    }
  }
}
