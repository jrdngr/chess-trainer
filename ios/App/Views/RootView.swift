import Book
import ChessCore
import Game
import Model
import SwiftUI

/// A mode open over the tabs.
enum Mode: Equatable {
  case play, endgame, middlegame
}

/// The app: onboarding ahead of everything, a mode over the tabs, or the tabs.
struct RootView: View {
  @Environment(AppStore.self) private var store
  @State private var tab: Tab = Self.debugTab ?? .home
  @State private var mode: Mode? = Self.debugMode
  /// The mode opens on its setup screen instead of starting at once. Debug opens keep the setup, for screenshots.
  @State private var setupFirst = Self.debugMode != nil
  /// A line the Playbook sent to the Analysis tab, and the side it was sent from.
  @State private var explore: (sans: [String], side: ChessCore.Color)?
  /// A line a mode sent to Analysis, opened over it: the mode stays underneath, and Back returns to it.
  @State private var analyzing: (sans: [String], side: ChessCore.Color)?
  /// The opening Home's Next line opens the Playbook tree at.
  @State private var mapFocus: MapFocus?
  /// An opening's Grow: the gap Play's first run starts at.
  @State private var growFrom: Gap?
  /// Where leaving a mode goes: the Playbook for a run started from an opening's Grow, else Home.
  @State private var returnTab: Tab?
  /// The Pawn Shop item to open, from a locked control.
  @State private var shopFocus: String? = Self.debugShopItem
  @State private var playbookPage: PlaybookView.Page?
  @State private var playbookSide = ChessCore.Color.w
  /// The Playbook tree's open path on each side, kept while an opening's page is open.
  @State private var playbookPaths: [ChessCore.Color: [String]] = [:]

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
    .environment(\.boardLook, BoardLook(coordinates: store.state.settings.showCoordinates))
    .task(id: store.tree != nil) { debugSeed() }
  }

  @ViewBuilder private func content(_ tree: OpeningTree, _ index: ReferenceIndex) -> some View {
    if !store.state.settings.seenIntro {
      WelcomeView(onRecommend: recommend) { store.update { $0.settings.seenIntro = true } }
    } else if !store.state.settings.onboarded {
      // Choose my openings: a family per slot, then the first game.
      ChooseOpeningsView(tree: tree, onBack: { store.update { $0.settings.seenIntro = false } }) { families in
        store.chooseOpenings(families)
        tab = .home
        setupFirst = false
        mode = .play
      }
    } else if let mode {
      ZStack {
        modeView(mode, tree, index)
          .opacity(analyzing == nil ? 1 : 0).allowsHitTesting(analyzing == nil)
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
        }, onNext: { node in
          mapFocus = MapFocus(side: node.color, id: node.id)
          tab = .playbook
        })
          .background(Theme.background.ignoresSafeArea())
          .tabItem { Label(Tab.home.label, systemImage: Tab.home.symbol) }.tag(Tab.home)
        PlaybookView(tree: tree, index: index, page: $playbookPage, side: $playbookSide, paths: $playbookPaths,
          mapFocus: mapFocus, onConsumedMapFocus: { mapFocus = nil }, onAnalyze: { sans, side in
          explore = (sans, side)
          tab = .analysis
        }, onGrow: { gap in
          growFrom = gap
          returnTab = .playbook
          setupFirst = false
          mode = .play
        }, onHome: { tab = .home })
          .background(Theme.background.ignoresSafeArea())
          .tabItem { Label(Tab.playbook.label, systemImage: Tab.playbook.symbol) }.tag(Tab.playbook)
        StatsView(tree: tree, index: index)
          .background(Theme.background.ignoresSafeArea())
          .tabItem { Label(Tab.stats.label, systemImage: Tab.stats.symbol) }.tag(Tab.stats)
        AnalysisTab(tree: tree, index: index, line: explore?.sans ?? [], orientation: explore?.side ?? .w)
          .id(explore?.sans.joined(separator: " ") ?? "")
          .tabItem { Label(Tab.analysis.label, systemImage: Tab.analysis.symbol) }.tag(Tab.analysis)
        ShopView(focus: $shopFocus) { feature in
          // A feature with a place on Home shows itself off there; the lenses wait for the next game,
          // and an endgame family is found in Endgames.
          if !feature.isLens && feature != .endgamesPawn && feature != .endgamesRook { tab = .home }
        }
          .tabItem { Label { Text(Tab.shop.label) } icon: { Image.pawn } }.badge(store.state.buyableCount).tag(Tab.shop)
      }
      .tint(Theme.accent)
      // Leaving the Playbook tab closes its page, so coming back shows the tree. A run from an
      // opening's Grow keeps the tab, so its page is still there afterward.
      .onChange(of: tab) { old, _ in if old == .playbook { playbookPage = nil } }
      .environment(\.openShop) { id in
        shopFocus = id
        tab = .shop
      }
    }
  }

  @ViewBuilder private func modeView(_ mode: Mode, _ tree: OpeningTree, _ index: ReferenceIndex) -> some View {
    switch mode {
    case .play:
      PlayView(tree: tree, index: index, grow: growFrom, onAnalyze: { analyzing = ($0, $1) }) { leave() }
    case .endgame: EndgameView { leave() }
    case .middlegame:
      MiddlegameView(
        tree: tree, index: index, onExit: { leave() }, onAnalyze: { analyzing = ($0, $1) },
        straight: !setupFirst)
    }
  }

  /// Recommend some openings: the recommended set goes in, and the first game starts.
  private func recommend() {
    store.update { $0.settings.seenIntro = true }
    store.recommendOpenings()
    tab = .home
    setupFirst = false
    mode = .play
  }

  /// Leaving a mode, from anywhere inside it, lands on Home.
  private func leave() {
    analyzing = nil
    mode = nil
    growFrom = nil
    tab = returnTab ?? .home
    returnTab = nil
  }

  /// Debug builds open a Pawn Shop item's sheet with `OPEN_SHOP=lensPawns` (with `OPEN_TAB=shop`), for screenshots.
  private static var debugShopItem: String? {
    #if DEBUG
      ProcessInfo.processInfo.environment["OPEN_SHOP"]
    #else
      nil
    #endif
  }

  /// Debug builds open on a tab with `OPEN_TAB=stats`, for screenshots.
  private static var debugTab: Tab? {
    #if DEBUG
      ProcessInfo.processInfo.environment["OPEN_TAB"].flatMap(Tab.init(rawValue:))
    #else
      nil
    #endif
  }

  /// Debug builds onboard a fresh install with the recommended openings, `SEED_SET=1`, for screenshots,
  /// or open on choosing them with `ONB_STEP=choose`. Both skip Welcome.
  private func debugSeed() {
    #if DEBUG
      let env = ProcessInfo.processInfo.environment
      if env["SEED_SET"] != nil || env["ONB_STEP"] != nil, !store.state.settings.seenIntro {
        store.update { $0.settings.seenIntro = true }
      }
      guard env["SEED_SET"] != nil, !store.state.settings.onboarded else { return }
      store.recommendOpenings()
    #endif
  }
}

