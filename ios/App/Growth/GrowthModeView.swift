import Book
import ChessCore
import Model
import SwiftUI

/// Growth opened from Home: a sitting where the lobby's Start would begin it
/// (the lobby itself when `straight` is off), and the lobby whenever there is
/// nothing to start. The sitting's settings button opens Growth's settings
/// with Restart. `onAnalyze` opens Analysis on a line, seen from a side.
struct GrowthModeView: View {
  let tree: OpeningTree
  let index: ReferenceIndex
  let onExit: () -> Void
  let onAnalyze: ([String], ChessCore.Color) -> Void
  /// Start a sitting at once, without stopping at the lobby.
  var straight = false

  @Environment(AppStore.self) private var store
  @State private var sitting: GrowthModel?
  @State private var settings = false
  /// Restarted from the settings: the lobby starts again at once, however Growth opened.
  @State private var restarted = false

  var body: some View {
    ZStack {
      if let sitting {
        GrowthSitting(model: sitting, onAnalyze: onAnalyze, onExit: onExit)
          .environment(\.openModeSettings) { settings = true }
      } else {
        GrowthLobbyView(tree: tree, index: index, onStart: start, onExit: onExit, autoStart: straight || restarted)
      }
    }
    .sheet(isPresented: $settings) {
      GrowthSettingsSheet(unsaved: sitting?.unsaved ?? 0, onRestart: restart) { settings = false }
        .presentationBackground(Theme.background)
    }
    .task { debugStart() }
  }

  /// Leave the sitting, unsaved moves and all, and start again where the lobby would.
  private func restart() {
    settings = false
    sitting = nil
    restarted = true
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

/// Growth's settings over a sitting, with Restart on top.
struct GrowthSettingsSheet: View {
  /// Moves the sitting would lose.
  let unsaved: Int
  let onRestart: () -> Void
  let onClose: () -> Void
  @Environment(AppStore.self) private var store
  @State private var discarding = false

  var body: some View {
    VStack(spacing: 0) {
      PlayAppBar(title: "Growth", onClose: onClose) { EmptyView() }
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          Button { if unsaved > 0 { discarding = true } else { onRestart() } } label: { Text("Restart").frame(maxWidth: .infinity) }
            .buttonStyle(PlayButtonStyle(kind: .primary, height: 56, radius: 16, font: 17))
          GrowthSettings(prefs: store.state.settings.growth) { change in store.update { change(&$0.settings.growth) } }
        }
        .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 28)
      }
    }
    .confirmationDialog(unsaved == 1 ? "Discard 1 move?" : "Discard \(unsaved) moves?", isPresented: $discarding, titleVisibility: .visible) {
      Button("Discard", role: .destructive, action: onRestart)
      Button("Keep playing", role: .cancel) {}
    }
  }
}
