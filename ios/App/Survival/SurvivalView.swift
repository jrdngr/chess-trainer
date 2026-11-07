import Book
import ChessCore
import Engine
import Model
import SwiftUI

/// Survival, opened from Home: straight into a run on your saved settings
/// (or the setup first, when `straight` is off), then one run after another
/// until you close it. The run's settings button opens the setup over it. A run plays on
/// `RunModel` and `RunView`, and ends on `EndView`, as Autopilot's do.
struct SurvivalView: View {
  let tree: OpeningTree
  let index: ReferenceIndex
  let onExit: () -> Void
  /// Leave for the Analysis tab on this line, seen from this side.
  let onAnalyze: (_ sans: [String], _ side: ChessCore.Color) -> Void
  /// Start a run at once, without the setup screen.
  var straight = false

  @Environment(AppStore.self) private var store
  @State private var model: RunModel?
  @State private var growth: GrowthModel?
  @State private var debugged = false
  /// Whether the first run has been tried: until then a straight start shows nothing.
  @State private var opened = false
  @State private var settings = false
  private static let engine = BasicEngine()

  var body: some View {
    Group {
      if let growth {
        GrowthSitting(model: growth, onAnalyze: onAnalyze, onExit: exit)
      } else if let model {
        if model.phase == .over, let finish = model.finish {
          EndView(
            model: model, finish: finish, onNext: { _ = start(model.prefs) },
            onAnalyze: { onAnalyze(model.run.played, model.run.color) }, onExit: exit,
            onChangeOptions: { setup() })
        } else {
          RunView(model: model, onExit: exit)
            .environment(\.openModeSettings) { settings = true }
        }
      } else if straight && !opened {
        Theme.background.ignoresSafeArea()
      } else {
        SurvivalSetupView(tree: tree, onStart: { start($0) }, onExit: onExit)
      }
    }
    .sheet(isPresented: $settings) {
      SurvivalSetupView(tree: tree, onStart: { prefs in
        settings = false
        start(prefs)
      }, onExit: { settings = false }, startLabel: "Restart")
      .presentationBackground(Theme.background)
    }
    .task {
      debugOpen()
      if straight && !opened && model == nil { start(store.state.settings.survival) }
      opened = true
    }
  }

  /// A run on these options, in the selection taken for it: "Any favorite" lands on one favorite per run.
  @discardableResult private func start(_ prefs: SurvivalPrefs) -> RunModel? {
    let selection = store.takeRoundSelection()
    let seed = (Env.random() * 2_147_483_648).rounded(.down)
    let options = survivalStart(prefs, selection, store.state, tree, seed: seed)
    guard
      let run = RunModel(
        survival: options, prefs: prefs, growth: store.state.settings.growth, selection: selection,
        store: store, tree: tree, index: index, engine: Self.engine)
    else { return nil }
    model?.stop()
    growth = nil
    model = run
    run.start()
    return run
  }

  /// Change options: back to the setup screen.
  private func setup() {
    model?.stop()
    model = nil
    growth = nil
  }

  private func exit() {
    model?.stop()
    onExit()
  }

  /// Debug builds reach a run's states without taps: see `SurvivalDebug`.
  private func debugOpen() {
    #if DEBUG
      guard !debugged, let plan = SurvivalDebug.plan else { return }
      debugged = true
      store.update { plan.prefs(&$0.settings.survival) }
      if let run = start(store.state.settings.survival) { SurvivalDebug.drive(run, plan) }
    #endif
  }
}
