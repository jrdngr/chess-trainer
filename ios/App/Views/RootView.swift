import Book
import Model
import SwiftUI

/// A mode open over the tabs: `mode` in `App.tsx`.
enum Mode: Equatable {
  case autopilot, survival, drill, growth, play
}

/// The app: onboarding ahead of everything, a mode over the tabs, or the tabs. `App.tsx`.
struct RootView: View {
  @Environment(AppStore.self) private var store
  @State private var tab: Tab = Self.debugTab ?? .home
  @State private var mode: Mode?

  var body: some View {
    ZStack {
      Theme.background.ignoresSafeArea()
      if let tree = store.tree, let index = store.index {
        content(tree, index)
      } else {
        ProgressView().tint(Theme.text2)
      }
    }
    .environment(\.boardLook, BoardLook(theme: store.state.settings.boardTheme, coordinates: store.state.settings.showCoordinates))
    .task { debugSeed() }
  }

  @ViewBuilder private func content(_ tree: OpeningTree, _ index: ReferenceIndex) -> some View {
    if !store.state.settings.onboarded {
      StarterView(tree: tree)
    } else if let mode {
      switch mode {
      case .autopilot: AutopilotView(tree: tree, index: index) { leave() }
      default: ComingSoon(mode: mode) { leave() }
      }
    } else {
      VStack(spacing: 0) {
        Group {
          switch tab {
          case .home: HomeView(tree: tree) { mode = $0 }
          case .playbook: PlaybookView(tree: tree, index: index)
          case .stats: StatsView(tree: tree, index: index)
          case .analysis: AnalysisTab(tree: tree, index: index)
          }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        TabBar(tab: $tab, due: countDue(Array(store.state.cards.values)).due)
      }
    }
  }

  /// Leaving a mode, from anywhere inside it, lands on Home.
  private func leave() {
    mode = nil
    tab = .home
  }

  /// Debug builds open on a tab with `OPEN_TAB=stats`, for screenshots.
  private static var debugTab: Tab? {
    #if DEBUG
      ProcessInfo.processInfo.environment["OPEN_TAB"].flatMap(Tab.init(rawValue:))
    #else
      nil
    #endif
  }

  /// Debug builds onboard a fresh install with a starter set, `SEED_SET=classical`, for screenshots.
  private func debugSeed() {
    #if DEBUG
      guard let id = ProcessInfo.processInfo.environment["SEED_SET"], let tree = store.tree,
        !store.state.settings.onboarded, let set = STARTER_SETS.first(where: { $0.id == id })
      else { return }
      store.update { $0.seed(tree, set) }
    #endif
  }
}

/// A mode not ported yet.
struct ComingSoon: View {
  let mode: Mode
  let onExit: () -> Void

  var body: some View {
    VStack(spacing: 12) {
      Text("Not here yet").font(.headline).foregroundStyle(Theme.text)
      Text("This mode is still being ported.").foregroundStyle(Theme.text2)
      Button("Back", action: onExit).buttonStyle(.bordered)
    }
  }
}
