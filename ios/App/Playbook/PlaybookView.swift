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
  /// The tree's open path on each side: kept above the tabs, so coming back from a page finds the same opening open.
  @Binding var paths: [ChessCore.Color: [String]]
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
  /// An opening being bought: its pawns in the air, the balance counting down.
  @State private var purchase: Purchase?
  @State private var flights: [Flight] = []
  @State private var balanceFrame: CGRect = .zero
  @State private var buyingPawns = false
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
      AppBar(title: "Playbook", large: true) {
        TidyButton(onOpen: { page = .tidy })
        balance
      }
      .zIndex(1)
      SegmentedControl(value: $side, options: [(.w, "White"), (.b, "Black")])
        .padding(.horizontal, 20).padding(.bottom, 8)
      // With nothing on a side, its tree is every family for sale.
      PlaybookMapView(
        tree: tree, side: side, kept: $paths, focus: mapFocus ?? nextFocus,
        onConsumedFocus: {
          if mapFocus != nil { onConsumedMapFocus() } else { nextFocus = nil }
        },
        onOpen: { node in page = .opening(node) },
        purchase: $purchase, flights: $flights, balanceFrame: balanceFrame)
    }
    .overlay { FlightLayer(flights: flights) }
    .coordinateSpace(name: PlaybookMapView.space)
    .pawnSheet(isPresented: $buyingPawns)
  }

  /// The pawn balance, as in the Shop: it counts down while an opening is bought, and a tap opens the pawn sheet.
  private var balance: some View {
    Button { if purchase == nil { buyingPawns = true } } label: {
      PawnAmount(count: purchase?.balance ?? store.state.pawns)
        .padding(.horizontal, 14).frame(height: 42)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(store.state.pawns) pawns, buy pawns")
    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(PlaybookMapView.space)) } action: { balanceFrame = $0 }
  }
}
