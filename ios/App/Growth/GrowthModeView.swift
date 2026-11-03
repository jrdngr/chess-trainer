import Book
import ChessCore
import Model
import SwiftUI

/// Growth opened from Home: the lobby, and a sitting on the row it starts.
/// `onAnalyze` opens the Analysis tab on a line, seen from a side.
struct GrowthModeView: View {
  let tree: OpeningTree
  let index: ReferenceIndex
  let onExit: () -> Void
  let onAnalyze: ([String], ChessCore.Color) -> Void

  @Environment(AppStore.self) private var store
  @State private var sitting: GrowthModel?
  /// Counted up for every run started: another run on the same row is a run of its own.
  @State private var started = 0
  /// The position a carry-on game starts from, once one is asked for.
  @State private var playFrom: String?

  var body: some View {
    ZStack {
      if let sitting {
        GrowthView(model: sitting, exits: exits(sitting)).id(started)
          .opacity(playFrom == nil ? 1 : 0).allowsHitTesting(playFrom == nil)
        if let playFrom {
          PlayOnView(from: playFrom, color: sitting.run.color, label: sitting.launch.row.name) { self.playFrom = nil }
            .background(Theme.background)
        }
      } else {
        GrowthLobbyView(tree: tree, index: index, onStart: start, onExit: onExit)
      }
    }
    .task { debugStart() }
  }

  private func exits(_ model: GrowthModel) -> GrowthView.Exits {
    GrowthView.Exits(
      again: { again(model) },
      analyze: { onAnalyze(model.run.path, model.run.color) },
      playFrom: { playFrom = $0 },
      back: { sitting = nil },
      close: onExit)
  }

  /// A sitting on a row, as the lobby's settings find holes.
  func start(_ row: GrowthRow) {
    let prefs = store.state.settings.growth
    let selection = store.state.settings.selection
    let launch = GrowthModel.Launch(
      row: row, hole: nil, opening: regionOf(tree, selection),
      find: GrowthOptions(minShare: prefs.minShare, maxPly: prefs.maxPly), maxPly: prefs.maxPly, paced: true,
      regionId: selection.opening)
    playFrom = nil
    sitting = GrowthModel(launch: launch, store: store, tree: tree, index: index)
    started += 1
  }

  /// Another run on whatever is now most worth extending; with nothing left, the lobby says so.
  private func again(_ model: GrowthModel) {
    if let next = model.nextRow() { start(next) } else { sitting = nil }
  }

  /// Debug builds reach a sitting's states for screenshots: `GROWTH_START=1`
  /// starts the lobby's first row, `GROWTH_PICKS=2` takes the top answer that
  /// often, `GROWTH_DONE=1` then stops, and `GROWTH_RUNS=4` plays whole runs
  /// until the card points back.
  private func debugStart() {
    #if DEBUG
      let env = ProcessInfo.processInfo.environment
      guard sitting == nil, env["GROWTH_START"] != nil else { return }
      let lobby = GrowthLobby(store.state, tree, index)
      guard let pick = lobby.pick else { return }
      start(pick)
      Task { await debugPlay(Int(env["GROWTH_PICKS"] ?? "") ?? 0, done: env["GROWTH_DONE"] != nil, runs: Int(env["GROWTH_RUNS"] ?? "") ?? 0) }
    #endif
  }

  #if DEBUG
    /// The sitting once it stands on a hole with its answers weighed; nil once it is done.
    private func debugReady() async -> GrowthModel? {
      for _ in 0..<200 {
        guard let model = sitting, model.phase != .done else { return nil }
        if model.phase == .hole, !model.held, !model.choices.isEmpty, model.evals.moves.count >= model.listed.count { return model }
        try? await Task.sleep(for: .milliseconds(100))
      }
      return nil
    }

    private func debugPlay(_ picks: Int, done: Bool, runs: Int) async {
      for _ in 0..<picks {
        guard let model = await debugReady() else { break }
        if let san = model.ranked.first?.san { model.pick(san) }
      }
      if done, let model = await debugReady() { model.finish() }
      for _ in 0..<runs {
        while let model = await debugReady() { if let san = model.ranked.first?.san { model.pick(san) } }
        guard let model = sitting else { break }
        again(model)
        try? await Task.sleep(for: .seconds(4))
      }
    }
  #endif
}
