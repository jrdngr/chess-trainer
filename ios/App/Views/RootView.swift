import Book
import ChessCore
import Model
import SwiftUI

/// A mode open over the tabs.
enum Mode: Equatable {
  case autopilot, endgame, middlegame
}

/// The app: onboarding ahead of everything, a mode over the tabs, or the tabs.
struct RootView: View {
  @Environment(AppStore.self) private var store
  @State private var tab: Tab = Self.debugTab ?? .home
  @State private var mode: Mode? = Self.debugMode
  /// The mode opens on its setup screen instead of starting at once. Debug opens keep the setup, for screenshots.
  @State private var setupFirst = Self.debugMode != nil
  /// Play on the board, opened from the Playbook tab.
  @State private var building = false
  /// Import my games, opened from the Playbook tab.
  @State private var importing = false
  /// A line the Playbook sent to the Analysis tab, and the side it was sent from.
  @State private var explore: (sans: [String], side: ChessCore.Color)?
  /// A line a mode sent to Analysis, opened over it: the mode stays underneath, and Back returns to it.
  @State private var analyzing: (sans: [String], side: ChessCore.Color)?
  /// A find handed over from the end of a round, for Tidy to open on.
  @State private var tidyFocus: TidyFind?
  /// A Growth sitting, from a recommendation or an opening's Grow.
  @State private var growing: GrowthModel?
  /// A line from the opening sheet for Middlegame mode to play out.
  @State private var middlegameLine: MiddlegameLine?

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
    .sheet(isPresented: Binding(get: { !store.restoreOffer.isEmpty }, set: { if !$0 { store.restoreOffer = [] } })) {
      RestoreView(offered: store.restoreOffer).presentationBackground(Theme.background).interactiveDismissDisabled()
    }
    .modifier(MilestoneToasts())
    .environment(\.boardLook, BoardLook(theme: store.state.settings.boardTheme, coordinates: store.state.settings.showCoordinates))
    .task(id: store.tree != nil) { debugSeed() }
  }

  @ViewBuilder private func content(_ tree: OpeningTree, _ index: ReferenceIndex) -> some View {
    if !store.state.settings.seenIntro || !store.state.settings.onboarded {
      // The welcome, then a first game with tips, or Skip to Home.
      WelcomeView(onTutorial: {
        store.update {
          $0.settings.seenIntro = true
          $0.settings.onboarded = true
          $0.settings.tips = FirstGameTip.allCases
        }
        tab = .home
        mode = .autopilot
      }, onSkip: {
        store.update {
          $0.settings.seenIntro = true
          $0.settings.onboarded = true
          $0.settings.tips = FirstGameTip.afterFirstGame
        }
        tab = .home
      })
    } else if importing {
      ImportView(onBack: { importing = false })
    } else if let growing {
      GrowthSitting(model: growing, onAnalyze: { sans, side in
        explore = (sans, side)
        self.growing = nil
        tab = .analysis
      }, onExit: { self.growing = nil })
    } else if building {
      BoardBuildView(onBack: { _ in building = false })
    } else if let mode {
      ZStack {
        modeView(mode, tree, index)
          .opacity(analyzing == nil ? 1 : 0).allowsHitTesting(analyzing == nil)
          .environment(\.openTidy) { find in
            // Leave the mode for Tidy, on the Playbook tab, open on the position the round ended at.
            tidyFocus = find
            analyzing = nil
            self.mode = nil
            tab = .playbook
          }
        if let analyzing {
          AnalysisTab(tree: tree, index: index, line: analyzing.sans, orientation: analyzing.side) { self.analyzing = nil }
            .id(analyzing.sans.joined(separator: " "))
        }
      }
    } else {
      TabView(selection: $tab) {
        HomeView(tree: tree, onOpen: { next in
          setupFirst = false
          mode = next
        }, onSetup: { next in
          setupFirst = true
          mode = next
        }, onGap: { gap in
          growing = GrowthModel(gap: gap, store: store, tree: tree, index: index)
        }, onPlaybook: { tab = .playbook })
          .tabItem { Label(Tab.home.label, systemImage: Tab.home.symbol) }.tag(Tab.home)
        PlaybookView(tree: tree, index: index, tidyFocus: tidyFocus, onConsumedTidyFocus: { tidyFocus = nil }, onExplore: { sans, side in
          explore = (sans, side)
          tab = .analysis
        }, onGrow: { offer in
          growing = GrowthModel(offer: offer, store: store, tree: tree, index: index)
        }, onMiddlegame: { side, sans in
          middlegameLine = MiddlegameLine(color: side, sans: sans)
          mode = .middlegame
        }, onImport: { importing = true }, onBuild: { building = true }, onHome: { tab = .home }, onPlay: {
          setupFirst = false
          mode = .autopilot
        })
          .tabItem { Label(Tab.playbook.label, systemImage: Tab.playbook.symbol) }.tag(Tab.playbook)
        StatsView(tree: tree, index: index)
          .tabItem { Label(Tab.stats.label, systemImage: Tab.stats.symbol) }.tag(Tab.stats)
        AnalysisTab(tree: tree, index: index, line: explore?.sans ?? [], orientation: explore?.side ?? .w)
          .id(explore?.sans.joined(separator: " ") ?? "")
          .tabItem { Label(Tab.analysis.label, systemImage: Tab.analysis.symbol) }.tag(Tab.analysis)
      }
      .tint(Theme.accent)
    }
  }

  @ViewBuilder private func modeView(_ mode: Mode, _ tree: OpeningTree, _ index: ReferenceIndex) -> some View {
    switch mode {
    case .autopilot:
      AutopilotView(tree: tree, index: index, onAnalyze: { analyzing = ($0, $1) }) { leave() }
    case .endgame: EndgameView { leave() }
    case .middlegame:
      MiddlegameView(
        tree: tree, index: index, exact: middlegameLine, onExit: { leave() }, onAnalyze: { analyzing = ($0, $1) },
        straight: !setupFirst)
    }
  }

  /// Leaving a mode, from anywhere inside it, lands on Home.
  private func leave() {
    if mode == .autopilot { store.backFromPlay = true }
    analyzing = nil
    mode = nil
    middlegameLine = nil
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
  /// `SEED_SET` and `ONB_STEP` both skip the intro pages.
  private func debugSeed() {
    #if DEBUG
      let env = ProcessInfo.processInfo.environment
      if env["SEED_SET"] != nil || env["ONB_STEP"] != nil, !store.state.settings.seenIntro {
        store.update { $0.settings.seenIntro = true }
      }
      guard let id = ProcessInfo.processInfo.environment["SEED_SET"], let tree = store.tree,
        !store.state.settings.onboarded, let set = STARTER_SETS.first(where: { $0.id == id })
      else { return }
      store.update { $0.seed(tree, set) }
    #endif
  }
}

