import Book
import ChessCore
import Model
import SwiftUI

/// Growth opened from Home: the lobby, and a sitting on the row it starts.
/// `onAnalyze` opens Analysis on a line, seen from a side.
struct GrowthModeView: View {
  let tree: OpeningTree
  let index: ReferenceIndex
  let onExit: () -> Void
  let onAnalyze: ([String], ChessCore.Color) -> Void

  @Environment(AppStore.self) private var store
  @State private var sitting: GrowthModel?

  var body: some View {
    ZStack {
      if let sitting {
        GrowthSitting(model: sitting, onAnalyze: onAnalyze, onExit: onExit)
      } else {
        GrowthLobbyView(tree: tree, index: index, onStart: start, onExit: onExit)
      }
    }
    .task { debugStart() }
  }

  /// A sitting on a row, as the lobby's settings find holes: on `launch`'s
  /// hole when it names one, with its kept line.
  func start(_ row: GrowthRow, _ launch: GrowthLobby.Launch) {
    let prefs = store.state.settings.growth
    let selection = store.state.settings.selection
    sitting = GrowthModel(
      launch: GrowthModel.Launch(
        row: row, hole: launch.hole, opening: regionOf(tree, selection),
        find: GrowthOptions(minShare: prefs.minShare, maxPly: prefs.maxPly), maxPly: prefs.maxPly,
        regionId: selection.opening, keep: launch.keep),
      store: store, tree: tree, index: index)
  }

  /// Debug builds reach a sitting's states for screenshots: `GROWTH_START=1`
  /// starts the lobby's first row, `GROWTH_PICKS=2` takes the top answer that
  /// often, and `GROWTH_DONE=1` then stops.
  private func debugStart() {
    #if DEBUG
      let env = ProcessInfo.processInfo.environment
      guard sitting == nil, env["GROWTH_START"] != nil else { return }
      let lobby = GrowthLobby(store.state, tree, index)
      guard let pick = lobby.pick else { return }
      start(pick, lobby.launch(pick))
      Task { await debugPlay(Int(env["GROWTH_PICKS"] ?? "") ?? 0, done: env["GROWTH_DONE"] != nil) }
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

    private func debugPlay(_ picks: Int, done: Bool) async {
      for _ in 0..<picks {
        guard let model = await debugReady() else { break }
        if let san = model.ranked.first?.san { model.pick(san) }
      }
      if done, let model = await debugReady() { model.finish() }
    }
  #endif
}
