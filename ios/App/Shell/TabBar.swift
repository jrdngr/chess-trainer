import SwiftUI

/// The four tabs along the bottom: `nav` in `App.tsx`.
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

  var icon: String {
    switch self {
    case .home: "home"
    case .playbook: "tree"
    case .stats: "chart"
    case .analysis: "analysis"
    }
  }
}

struct TabBar: View {
  @Binding var tab: Tab
  /// Positions due for review, on Home's tab.
  var due = 0

  var body: some View {
    HStack(spacing: 0) {
      ForEach(Tab.allCases, id: \.self) { item in
        let active = item == tab
        Button { tab = item } label: {
          VStack(spacing: 4) {
            Icon(name: item.icon, size: 24, filled: active)
            Text(item.label).font(.system(size: 10.5, weight: .semibold))
          }
          .frame(maxWidth: .infinity, minHeight: 56)
          .foregroundStyle(active ? Theme.accent : Theme.text3)
          .overlay(alignment: .top) {
            if item == .home && due > 0 {
              Text("\(due)").font(.system(size: 10, weight: .heavy)).foregroundStyle(Theme.accentInk)
                .frame(minWidth: 17, minHeight: 17).padding(.horizontal, 4)
                .background(Capsule().fill(Theme.accent)).offset(x: 14, y: 6)
            }
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
    }
    .background(.ultraThinMaterial.opacity(0.9))
    .background(Theme.background.opacity(0.82))
    .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.07)).frame(height: 1) }
  }
}
