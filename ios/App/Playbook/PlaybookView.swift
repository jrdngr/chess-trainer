import Book
import ChessCore
import Game
import Model
import SwiftUI
import UIKit

/// The Playbook tab: one side at a time, its openings as a tree that grows from
/// the first moves, with the openings the curve adds next locked in place. A tap
/// on an opening of yours opens its page.
struct PlaybookView: View {
  let tree: OpeningTree
  let index: ReferenceIndex
  /// The page open and the side shown: kept above the tabs, so Grow and Middlegame come back to them.
  @Binding var page: Page?
  @Binding var side: ChessCore.Color
  /// An opening for the tree to open at, from Home's Next line.
  var mapFocus: MapFocus? = nil
  var onConsumedMapFocus: () -> Void = {}
  /// Analysis on a line, seen from a side.
  var onAnalyze: ([String], ChessCore.Color) -> Void = { _, _ in }
  /// Grow a hole, from an opening's page.
  var onGrow: (Gap) -> Void = { _ in }
  /// Go to Home, after an opening page selected its opening.
  var onHome: () -> Void = {}

  @Environment(AppStore.self) private var store
  /// The tree's own focus, from an opening's page: the opening the curve grows next.
  @State private var nextFocus: MapFocus?

  enum Page: Equatable {
    case opening(MapNode)
    case tidy
  }

  var body: some View {
    Group {
      switch page {
      case .opening(let node):
        OpeningPage(
          tree: tree, node: node, onBack: { page = nil }, onGrow: onGrow,
          onAnalyze: onAnalyze,
          onShowNext: {
            if let next = nextMapNode(store.state, tree) {
              nextFocus = MapFocus(side: next.color, id: next.id)
              side = next.color
            }
            page = nil
          },
          onSelected: {
            page = nil
            onHome()
          })
      case .tidy: TidyView(onBack: { page = nil })
      case nil: list
      }
    }
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
    }
  }

  private var list: some View {
    VStack(spacing: 0) {
      AppBar(title: "Playbook", large: true) { TidyButton(onOpen: { page = .tidy }) }
      SegmentedControl(value: $side, options: [(.w, "White"), (.b, "Black")])
        .padding(.horizontal, 16)
      // With nothing on a side, its tree is every family for sale.
      PlaybookMapView(
        tree: tree, side: side, focus: mapFocus ?? nextFocus,
        onConsumedFocus: {
          if mapFocus != nil { onConsumedMapFocus() } else { nextFocus = nil }
        },
        onOpen: { node in page = .opening(node) })
        .padding(.top, 4)
    }
  }
}
