import Book
import ChessCore
import Game
import Model
import SwiftUI
import UIKit

/// The Playbook tab: one side at a time, its openings as a tree that grows from
/// the first moves, with the openings the curve adds next locked in place.
/// Tidy is in the more menu when it has something.
struct PlaybookView: View {
  let tree: OpeningTree
  let index: ReferenceIndex
  var tidyFocus: TidyFind? = nil
  /// The focus is taken: Tidy holds it from here.
  var onConsumedTidyFocus: () -> Void = {}
  /// An opening for the tree to open at, from Home's Next line.
  var mapFocus: MapFocus? = nil
  var onConsumedMapFocus: () -> Void = {}
  var onExplore: ([String], ChessCore.Color) -> Void = { _, _ in }
  /// Grow an opening, from Growth's own pick for it.
  var onGrow: (GrowOffer) -> Void = { _ in }
  /// Play a line out to a middlegame, as this side.
  var onMiddlegame: (ChessCore.Color, [String]) -> Void = { _, _ in }
  /// Go to Home, after an opening page selected its opening.
  var onHome: () -> Void = {}

  @Environment(AppStore.self) private var store
  @Environment(Toasts.self) private var toasts
  @State private var scan = TidyScan(checks: EngineChecks.shared)
  @State private var page: Page?
  @State private var focus: TidyFind?
  @State private var side = ChessCore.Color.w
  /// The app bar's width, to point a tip at its more button.
  @State private var barWidth: CGFloat = 393

  enum Page: Equatable {
    case tidy
    case opening(repId: String, name: String)
    case browse(repId: String, nodeId: String?, title: String)
    /// The board editor on a line of one side's tree, back to the browser after.
    case board(repId: String, sans: [String], title: String)
  }

  var body: some View {
    let state = store.state
    Group {
      switch page {
      case .tidy: TidyView(scan: scan, focus: focus, onFocusShown: { focus = nil }) { page = nil }
      case .opening(let repId, let name):
        OpeningPage(
          tree: tree, index: index, repId: repId, name: name, onBack: { page = nil },
          onOpenLine: { tipId, title in page = .browse(repId: repId, nodeId: tipId, title: title) },
          onGrow: onGrow, onMiddlegame: onMiddlegame,
          onSelected: {
            page = nil
            onHome()
          })
      case .browse(let repId, let nodeId, let title):
        if state.playbooks[repId] != nil {
          PlaybookBrowser(
            repId: repId, startNodeId: nodeId, title: title, onBack: { page = nil }, onExplore: onExplore,
            onEdit: { sans in page = .board(repId: repId, sans: sans, title: title) })
        } else {
          Color.clear.onAppear { page = nil }
        }
      case .board(let repId, let sans, let title):
        if let rep = state.playbooks[repId] {
          BoardBuildView(start: sans, side: rep.color, onBack: { _ in
            // Back to the browser where the line's saved moves end.
            let fresh = store.state.playbooks[repId] ?? rep
            let held = Array(sans.prefix(savedPlies(fresh, sans)))
            page = .browse(repId: repId, nodeId: held.isEmpty ? nil : nodeAtLine(fresh, held)?.id, title: title)
          })
        } else {
          Color.clear.onAppear { page = nil }
        }
      case nil: list
      }
    }
    .task(id: scanInput) { await scan.run(scanInput, tree, index) }
    .onChange(of: mapFocus) { _, focus in
      guard let focus else { return }
      page = nil
      side = focus.side
    }
    .onAppear {
      if let mapFocus {
        page = nil
        side = mapFocus.side
      } else if store.state.playbookList.first(where: { $0.color == side }) == nil, let other = store.state.playbookList.first {
        side = other.color
      }
      guard let tidyFocus else { return }
      focus = tidyFocus
      page = .tidy
      onConsumedTidyFocus()
    }
  }

  private var scanInput: TidyScan.Input {
    let state = store.state
    return TidyScan.Input(
      playbooks: state.playbooks, order: state.playbookOrder, selection: state.settings.selection,
      growth: state.settings.growth)
  }

  private var list: some View {
    let reps = store.state.playbookList
    let rep = reps.first { $0.color == side }
    let tip: GameTip? = store.state.settings.seen(.playbook) ? nil : .playbook
    let putAway = { dismissTip(store, tip) }
    let untidy = scan.count ?? 0
    return VStack(spacing: 0) {
      AppBar(title: "Playbook", large: true) {
        Menu {
          if untidy > 0 {
            Button { page = .tidy } label: { Label("Tidy (\(untidy))", systemImage: "wand.and.stars") }
          }
          if !reps.isEmpty {
            ShareLink(item: exportFile(reps)) { Label("Export", systemImage: "square.and.arrow.up") }
          }
        } label: {
          Icon(name: "more", size: 20).foregroundStyle(Theme.text).frame(width: 38, height: 38).background(Circle().fill(Theme.surface))
        }
        .accessibilityLabel("More")
      }
      .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { barWidth = $0 }
      .tip(tip, when: tip != nil, arrowAt: barArrowAt, inset: 16, onDismiss: putAway)
      SegmentedControl(value: $side, options: [(.w, "White"), (.b, "Black")])
        .padding(.horizontal, 16)
      // With nothing on a side, its tree is every family for sale.
      PlaybookMapView(
        tree: tree, side: side, focus: mapFocus, onConsumedFocus: onConsumedMapFocus,
        onOpen: { node in if let rep { open(rep, node) } })
        .padding(.top, 4)
    }
  }

  /// An opening of yours on its page: the tab's row of that name, else the first row
  /// along its line, else the tree of moves at it.
  private func open(_ rep: Playbook, _ node: MapNode) {
    let rows = playbookRows(rep, index)
    let along = { (row: PlaybookRow) in
      row.parts.contains { $0.path.starts(with: node.line) || node.line.starts(with: $0.path) }
    }
    if let row = rows.first(where: { $0.name == node.name }) ?? rows.first(where: along) {
      page = .opening(repId: rep.id, name: row.name)
    } else {
      page = .browse(repId: rep.id, nodeId: nodeAtLine(rep, node.line)?.id, title: node.name)
    }
  }

  /// Where along the app bar the tip points: its more button.
  private var barArrowAt: CGFloat {
    // The bar's 20pt sides, 38pt buttons; the tip spans the bar less 16pt each side.
    let more = barWidth - 20 - 19
    return (more - 16) / max(barWidth - 32, 1)
  }

  /// Your playbook with the log of how it got that way, as a JSON file to share.
  private func exportFile(_ reps: [Playbook]) -> URL {
    let date = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
    let url = FileManager.default.temporaryDirectory.appending(path: "playbook-\(date).json")
    struct Export: Encodable {
      var format = "chess-trainer-playbook"
      var version = 1
      var exportedAt: String
      var playbooks: [Playbook]
      var events: [AppEvent]
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let data = try? encoder.encode(Export(exportedAt: date, playbooks: reps, events: store.state.events)) {
      try? data.write(to: url)
    }
    return url
  }
}

struct RepRef: Identifiable { var id: String }

/// The book's opening a Playbook row stands for, where its form is kept:
/// the shallowest node of that name, else the node at the row's first move order.
@MainActor func openingNode(_ tree: OpeningTree, _ row: PlaybookRow) -> OpeningNode? {
  row.parts.first.flatMap { familyNode(tree, row.name, path: $0.path) }
}
