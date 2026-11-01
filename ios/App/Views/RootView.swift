import Book
import ChessCore
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
  @State private var mode: Mode? = Self.debugMode
  /// Play on the board, opened from the Playbook tab.
  @State private var building = false
  /// A Drill sitting opened from the Playbook: its positions and title.
  @State private var drilling: (items: [TrainingItem], title: String)?
  @Environment(Toasts.self) private var toasts
  /// Import games, opened from the Playbook tab.
  @State private var importing = ImportDebug.open
  /// A line the Playbook sent to the Analysis tab, and the side it was sent from.
  @State private var explore: (sans: [String], side: ChessCore.Color)?
  /// A line a mode sent to Analysis, opened over it: the mode stays underneath, and Back returns to it.
  @State private var analyzing: (sans: [String], side: ChessCore.Color)?
  /// The one opening Growth's way back holds Autopilot to, in place of the saved selection.
  @State private var scope: Selection?
  /// A find handed over from the end of a round, for Tidy to open on.
  @State private var tidyFocus: TidyFind?

  var body: some View {
    ZStack {
      Theme.background.ignoresSafeArea()
      if let tree = store.tree, let index = store.index {
        content(tree, index)
      } else {
        ProgressView().tint(Theme.text2)
      }
    }
    .overlay { ToastHost() }
    .modifier(MilestoneToasts())
    .environment(\.boardLook, BoardLook(theme: store.state.settings.boardTheme, coordinates: store.state.settings.showCoordinates))
    .task(id: store.tree != nil) { debugSeed() }
  }

  @ViewBuilder private func content(_ tree: OpeningTree, _ index: ReferenceIndex) -> some View {
    if !store.state.settings.onboarded {
      OnboardingView(tree: tree, index: index) { next in
        tab = .home
        mode = next == .autopilot ? .autopilot : nil
      }
    } else if importing {
      ImportView(onBack: { importing = false })
    } else if let drilling {
      DrillSessionView(tree: tree, index: index, store: store, items: drilling.items, title: drilling.title) { self.drilling = nil }
    } else if building {
      BoardBuildView(onBack: { building = false }, onDone: { _ in building = false })
    } else if let mode {
      ZStack {
        modeView(mode, tree, index)
          .opacity(analyzing == nil ? 1 : 0).allowsHitTesting(analyzing == nil)
          .environment(\.openTidy) { find in
            // Leave the mode for Tidy, on the Playbook tab, open on the position the round ended at.
            tidyFocus = find
            analyzing = nil
            self.mode = nil
            scope = nil
            tab = .playbook
          }
        if let analyzing {
          AnalysisTab(tree: tree, index: index, line: analyzing.sans, orientation: analyzing.side) { self.analyzing = nil }
            .id(analyzing.sans.joined(separator: " "))
        }
      }
    } else {
      VStack(spacing: 0) {
        Group {
          switch tab {
          case .home: HomeView(tree: tree) { mode = $0 }
          case .playbook:
            PlaybookView(tree: tree, index: index, tidyFocus: tidyFocus, onConsumedTidyFocus: { tidyFocus = nil }, onExplore: { sans, side in
              explore = (sans, side)
              tab = .analysis
            }, onDrill: { repId, nodeId, title in
              guard let rep = store.state.repertoires[repId] else { return }
              let items = Array(branchItems(rep, nodeId).prefix(40))
              if items.isEmpty { toasts.show("Nothing to drill") } else { drilling = (items, title) }
            }, onImport: { importing = true }, onBuild: { building = true })
          case .stats: StatsView(tree: tree, index: index)
          case .analysis:
            AnalysisTab(tree: tree, index: index, line: explore?.sans ?? [], orientation: explore?.side ?? .w)
              .id(explore?.sans.joined(separator: " ") ?? "")
          }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        TabBar(tab: $tab, due: countDue(Array(store.state.cards.values)).due)
      }
    }
  }

  @ViewBuilder private func modeView(_ mode: Mode, _ tree: OpeningTree, _ index: ReferenceIndex) -> some View {
    switch mode {
    case .autopilot:
      AutopilotView(tree: tree, index: index, scope: scope) { leave() }
        .id(scope.map { "\($0.color.rawValue):\($0.opening)" } ?? "autopilot")
    case .play: PlayView(tree: tree, index: index) { leave() }
    case .drill: DrillView(tree: tree, index: index) { leave() }
    case .growth:
      GrowthModeView(
        tree: tree, index: index, onExit: { leave() },
        onPractice: { selection in
          scope = selection
          self.mode = .autopilot
        },
        onAnalyze: { analyzing = ($0, $1) })
    case .survival:
      SurvivalView(
        tree: tree, index: index, onExit: { leave() }, onAnalyze: { analyzing = ($0, $1) },
        onPractice: { selection in
          scope = selection
          self.mode = .autopilot
        })
    }
  }

  /// Leaving a mode, from anywhere inside it, lands on Home.
  private func leave() {
    analyzing = nil
    mode = nil
    scope = nil
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
