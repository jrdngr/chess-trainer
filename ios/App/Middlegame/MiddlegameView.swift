import Book
import ChessCore
import Engine
import Foundation
import Model
import SwiftUI

/// A line your Playbook asked for, to play out exactly: from the opening sheet.
struct MiddlegameLine: Equatable {
  var color: ChessCore.Color
  var sans: [String]
}

/// Middlegame mode, opened from Home or from a line on the opening sheet: one of
/// your lines played out to a middlegame, then a Survival run from there. While the
/// handoff is built, the mode is announced over the screen. A run plays on
/// `RunModel` and `RunView`, and ends on `EndView`, as Survival's do.
struct MiddlegameView: View {
  let tree: OpeningTree
  let index: ReferenceIndex
  /// The exact line to play out; nil to draw one from your setup each run.
  var exact: MiddlegameLine?
  let onExit: () -> Void
  /// Leave for the Analysis tab on this line, seen from this side.
  let onAnalyze: (_ sans: [String], _ side: ChessCore.Color) -> Void

  @Environment(AppStore.self) private var store
  @Environment(Toasts.self) private var toasts
  @State private var model: RunModel?
  /// The handoff being built, named by the opening it is in.
  @State private var building: [String]?
  @State private var job: Task<Void, Never>?
  /// The line the last run played out, for Same line.
  @State private var last: MiddlegameLine?
  /// The game engine, and a second one for the handoff's checks so a build never waits on a judge.
  private static let engine = BasicEngine()
  private static let builder = BasicEngine()

  var body: some View {
    Group {
      if let building {
        PlayIntroCover(trail: building, mode: "Middlegame")
      } else if let model {
        if model.phase == .over, let finish = model.finish {
          EndView(
            model: model, finish: finish, onNext: { start(store.state.settings.middlegame) },
            onGrow: { _ in }, onAnalyze: { onAnalyze(model.run.played, model.run.color) }, onExit: exit,
            onChangeOptions: exact == nil ? { setup() } : nil,
            onSameLine: last == nil ? nil : { if let last { start(store.state.settings.middlegame, line: last) } })
        } else {
          RunView(model: model, onExit: exit)
        }
      } else if exact != nil {
        Color.clear
      } else {
        MiddlegameSetupView(tree: tree, onStart: { start($0) }, onExit: onExit)
      }
    }
    .task {
      if let exact, model == nil, building == nil { start(store.state.settings.middlegame, line: exact) }
    }
  }

  /// Draw a line from the setup (or take `line`), build its handoff, then begin the run there.
  private func start(_ saved: SurvivalPrefs, line: MiddlegameLine? = nil) {
    let prefs = middlegamePrefs(saved)
    let selection = store.takeRoundSelection()
    let seed = (Env.random() * 2_147_483_648).rounded(.down)
    var options = survivalStart(prefs, selection, store.state, tree, seed: seed)
    if let line { options.color = line.color == .w ? .w : .b }
    guard let drawn = line ?? startSurvival(options).map({ MiddlegameLine(color: $0.state.run.color, sans: middlegameLine($0)) }),
      !drawn.sans.isEmpty
    else {
      toasts.show("No line to play out here")
      return
    }
    options.color = drawn.color == .w ? .w : .b
    model?.stop()
    model = nil
    last = drawn
    building = trail(drawn.sans)
    let tools = handoffTools(Self.builder, index, prefs.opponentLevel(store.state.strength))
    job?.cancel()
    job = Task {
      let began = Date()
      let handoff = await buildHandoff(drawn.sans, color: drawn.color, tools: tools, seed: seed)
      // The announcement holds at least as long as Survival's, however quick the build.
      let left = RunModel.announceMs - Date().timeIntervalSince(began)
      if left > 0 { try? await Task.sleep(for: .seconds(left)) }
      guard !Task.isCancelled else { return }
      building = nil
      guard let handoff,
        let run = RunModel(
          middlegame: options, handoff: handoff, prefs: prefs, selection: selection,
          store: store, tree: tree, index: index, engine: Self.engine)
      else {
        toasts.show("This line couldn't be played out")
        if exact != nil { onExit() }
        return
      }
      model = run
      run.start()
    }
  }

  /// The opening the line is in, as the announcement names it.
  private func trail(_ sans: [String]) -> [String] {
    let node = deepestNodeWithin(tree, tree.root, sans)
    guard let catalog = store.catalog else { return [node.name] }
    return selectionTrail(tree, catalog, node.id)
  }

  /// Change options: back to the setup screen.
  private func setup() {
    model?.stop()
    model = nil
  }

  private func exit() {
    job?.cancel()
    model?.stop()
    onExit()
  }
}
