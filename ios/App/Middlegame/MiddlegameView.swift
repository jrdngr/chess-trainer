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
  /// The line ends on a reply your Playbook can't meet: you take over there.
  var gap = false
}

/// Middlegame mode, opened from Home or from a line on the opening sheet: one of
/// your lines played out to a middlegame, then a Run run from there. While the
/// handoff is built, the mode is announced over the screen. A run plays on
/// `RunModel` and `RunView`, and ends on `EndView`, as Run's do.
struct MiddlegameView: View {
  let tree: OpeningTree
  let index: ReferenceIndex
  /// The exact line to play out; nil to draw one from your setup each run.
  var exact: MiddlegameLine?
  let onExit: () -> Void
  /// Leave for the Analysis tab on this line, seen from this side.
  let onAnalyze: (_ sans: [String], _ side: ChessCore.Color) -> Void
  /// From Home, start a run at once, without the setup screen.
  var straight = false

  @Environment(AppStore.self) private var store
  @Environment(Toasts.self) private var toasts
  @State private var model: RunModel?
  /// The handoff being built, named by the opening it is in.
  @State private var building: [String]?
  @State private var job: Task<Void, Never>?
  /// The line the last run played out, for Same line.
  @State private var last: MiddlegameLine?
  /// Whether the first run has been tried: until then a straight start shows nothing.
  @State private var opened = false
  @State private var settings = false
  /// The game engine, and a second one for the handoff's checks so a build never waits on a judge.
  private static let engine = EngineSlot()
  private static let builder = EngineSlot()

  var body: some View {
    Group {
      if let building {
        // The announcement fades out on its own; a long build waits under it, and can be left.
        ZStack {
          VStack(spacing: 18) {
            ProgressView().tint(Theme.text2)
            Button("Cancel", action: exit).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text2)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.background)
          PlayIntroCover(trail: building, mode: "Middlegame").allowsHitTesting(false)
        }
      } else if let model {
        if model.phase == .over, let finish = model.finish {
          EndView(
            model: model, finish: finish, onNext: { start(store.state.settings.middlegame) },
            onAnalyze: { onAnalyze(model.run.played, model.run.color) }, onExit: exit,
            onChangeOptions: exact == nil ? { setup() } : nil,
            onSameLine: last == nil ? nil : { if let last { start(store.state.settings.middlegame, line: last) } })
        } else {
          RunView(model: model, onExit: exit, onAnalyze: { onAnalyze(model.run.played, model.run.color) })
            .environment(\.openModeSettings) { settings = true }
        }
      } else if exact != nil || (straight && !opened) {
        Theme.background.ignoresSafeArea()
      } else {
        MiddlegameSetupView(tree: tree, onStart: { start($0) }, onExit: onExit)
      }
    }
    .sheet(isPresented: $settings) {
      MiddlegameSetupView(tree: tree, onStart: { prefs in
        settings = false
        start(prefs, line: exact)
      }, onExit: { settings = false }, startLabel: "Restart")
      .presentationBackground(Theme.background)
    }
    .task {
      if let exact, model == nil, building == nil {
        start(store.state.settings.middlegame, line: exact)
      } else if straight && !opened && model == nil && building == nil {
        start(store.state.settings.middlegame)
      }
      opened = true
    }
  }

  /// Draw a line from the setup (or take `line`), build its handoff, then begin the run there.
  /// A run from the opening sheet draws its next lines through that line's own opening.
  private func start(_ saved: RunPrefs, line: MiddlegameLine? = nil) {
    let prefs = middlegamePrefs(saved)
    let selection = (line ?? exact).map(selectionOf) ?? store.takeRoundSelection()
    let seed = (Env.random() * 2_147_483_648).rounded(.down)
    var options = runStart(prefs, selection, store.state, tree, seed: seed)
    guard let drawn = line ?? startRun(options).map({ begun -> MiddlegameLine in
      let yours = middlegameLine(begun, store.state.playbookList)
      return MiddlegameLine(color: begun.state.run.color, sans: yours.sans, gap: yours.gap)
    }),
      !drawn.sans.isEmpty
    else {
      toasts.show("No line to play out here")
      if exact != nil && model == nil { onExit() }
      return
    }
    options.color = drawn.color == .w ? .w : .b
    model?.stop()
    model = nil
    last = drawn
    building = trail(drawn.sans)
    let tools = handoffTools(Self.builder(), index, prefs.opponentLevel(store.state.strength))
    job?.cancel()
    job = Task {
      let began = Date()
      let handoff = await buildHandoff(drawn.sans, color: drawn.color, tools: tools, seed: seed, gap: drawn.gap)
      // The announcement holds at least as long as Run's, however quick the build.
      let left = RunModel.announceMs - Date().timeIntervalSince(began)
      if left > 0 { try? await Task.sleep(for: .seconds(left)) }
      guard !Task.isCancelled else { return }
      building = nil
      guard let handoff,
        let run = RunModel(
          middlegame: options, handoff: handoff, prefs: prefs, selection: selection,
          store: store, tree: tree, index: index, engine: Self.engine())
      else {
        toasts.show("This line couldn't be played out")
        if exact != nil { onExit() }
        return
      }
      model = run
      run.start()
    }
  }

  /// The opening a line is in and its side, as a selection to draw from.
  private func selectionOf(_ line: MiddlegameLine) -> Selection {
    Selection(color: line.color == .w ? .w : .b, opening: deepestNodeAlong(tree, line.sans)?.id ?? tree.root.id)
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
