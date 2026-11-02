import Book
import ChessCore
import Model
import SwiftUI

/// Drill: the setup, then the session it describes.
struct DrillView: View {
  @Environment(AppStore.self) private var store
  let tree: OpeningTree
  let index: ReferenceIndex
  let onExit: () -> Void
  @State private var running: Running?

  /// A sitting, as Start fixed it: the options, and the selection with Any favorite resolved.
  struct Running {
    var prefs: DrillPrefs
    var selection: Selection
    /// Lines have one side: with either selected, one is picked per visit.
    var lineColor: ChessCore.Color?
    var id = UUID()
  }

  var body: some View {
    Group {
      if let running { session(running).id(running.id) } else { DrillSetupView(tree: tree, onStart: start, onExit: onExit) }
    }
    .task { debugOpen() }
  }

  @ViewBuilder private func session(_ r: Running) -> some View {
    let region = regionOf(tree, r.selection)
    if let color = r.lineColor {
      LineDrillView(
        tree: tree, index: index, store: store, color: color, openingId: region.id, lean: r.prefs.weakFirst ? .weak : .popular,
        prefs: r.prefs, onExit: onExit)
    } else {
      let items = itemsInRegion(tree, region, repertoiresIn(store.state.repertoireList, r.selection.color).flatMap { allItems([$0]) })
      DrillSessionView(
        tree: tree, index: index, store: store, items: items, mode: r.prefs.draw.mode, title: "Drill", prefs: r.prefs,
        openingId: region.id, onExit: onExit)
    }
  }

  private func start(_ prefs: DrillPrefs) {
    let selection = store.takeRoundSelection()
    var lineColor: ChessCore.Color?
    if prefs.form == .lines {
      if selection.color == .w { lineColor = .w } else if selection.color == .b { lineColor = .b } else {
        let region = regionOf(tree, selection)
        let sides = repertoiresIn(store.state.repertoireList, selection.color)
          .filter { !drillableLines($0, tree, region).isEmpty }.map(\.color)
        lineColor = sides.isEmpty ? .w : sides[Int((Env.random() * Double(sides.count)).rounded(.down))]
      }
    }
    running = Running(prefs: prefs, selection: selection, lineColor: lineColor)
  }

  /// Debug builds open a sitting with `DRILL_SCREEN=positions` or `lines`, for screenshots.
  private func debugOpen() {
    #if DEBUG
      guard running == nil, let screen = ProcessInfo.processInfo.environment["DRILL_SCREEN"], screen != "setup" else { return }
      var prefs = store.state.settings.drill
      prefs.form = screen == "lines" ? .lines : .positions
      start(prefs)
    #endif
  }
}
