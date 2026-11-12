import Book
import ChessCore
import Game
import Model
import SwiftUI

/// The full opening picker: a board you can always play on, the name of what
/// is on it, and lists underneath that each move the board somewhere.
///
/// Choose selects exactly the board's line and closes; the close button leaves
/// the selection as it was. Nothing is selected by tapping a row, which only
/// plays its line out and opens what is under it. With `onChoose` the line is
/// handed over instead of selected.
struct BrowsePicker: View {
  let onClose: () -> Void
  var onBack: (() -> Void)?
  var onChoose: (([String], ChessCore.Color?) -> Void)?

  @Environment(AppStore.self) private var store
  @State private var moves: [String]?
  /// The side the line is played from and the board is seen from. Playing never changes it.
  @State private var sideSet: ChessCore.Color?
  @State private var chip: BrowseChipId?
  @State private var trail: [BrowseLevel] = []
  @State private var filter: SideFilter = .both
  @State private var searching = false
  @State private var query = ""
  /// A search result was tapped: the board is back, on its line.
  @State private var resultShown = false
  @State private var previewed: String?
  @State private var memo = Memo<[BrowseItem]>()

  init(onClose: @escaping () -> Void, onBack: (() -> Void)? = nil, onChoose: (([String], ChessCore.Color?) -> Void)? = nil) {
    self.onClose = onClose
    self.onBack = onBack
    self.onChoose = onChoose
  }

  var body: some View {
    if let tree = store.tree, let index = store.index, let catalog = store.catalog {
      content(BrowseContext(tree: tree, index: index, catalog: catalog, state: store.state))
    }
  }

  private func content(_ ctx: BrowseContext) -> some View {
    let line = moves ?? initialMoves(ctx)
    let side = sideSet ?? (store.state.settings.selection.color == .b ? .b : .w)
    return VStack(spacing: 10) {
      BrowseTopBar(side: Binding(get: { side }, set: { sideSet = $0 }), canUndo: !line.isEmpty, onBack: onBack, onClose: onClose,
                   onUndo: { undo(line) }, onSearch: toggleSearch)
      // A search has the board step aside until a result is tapped, so the results show above the keyboard.
      if !searching || resultShown {
        BoardView(fen: walkSan(line).fens.last ?? START_FEN, orientation: side, interactive: true, lastMove: lastMoveOf(line),
                  bothSides: true) { play(line, $0.san) }
          // The board gives way on short screens so the lists keep some room: `min(100%, 46dvh)`.
          .frame(maxWidth: min(UIScreen.main.bounds.height * 0.46, 600))
          .layoutPriority(1)
      }
      BrowseNameBar(ctx: ctx, moves: line, onChoose: { choose(ctx, line, side) })
      if searching {
        BrowseSearchField(query: $query)
      } else {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 6) {
            ForEach(BrowseChipId.allCases, id: \.self) { c in BrowseChip(label: c.label, on: chip == c) { pickChip(c) } }
          }
          .padding(.horizontal, 16)
        }
        .padding(.horizontal, -16)
      }
      ScrollViewReader { proxy in
        ScrollView {
          VStack(spacing: 8) {
            Color.clear.frame(height: 0).id("top")
            pane(ctx, line)
          }
          .padding(.bottom, 24)
        }
        .onChange(of: trail.count) { proxy.scrollTo("top", anchor: .top) }
      }
    }
    .padding(.horizontal, 16).padding(.top, 4)
    .background(Theme.background)
    .onAppear { debugOpen(ctx) }
    // Typing again goes back to the results.
    .onChange(of: query) { resultShown = false }
  }

  /// Debug builds open a list with `BROWSE_CHIP=book|suggest|shelves|mine|recent`, and with
  /// `BROWSE_ROW=1` tap its first row, for screenshots.
  private func debugOpen(_ ctx: BrowseContext) {
    #if DEBUG
      let env = ProcessInfo.processInfo.environment
      guard chip == nil, let raw = env["BROWSE_CHIP"],
        let c = BrowseChipId.allCases.first(where: { "\($0)" == raw })
      else { return }
      pickChip(c)
      if env["BROWSE_ROW"] == "1", let first = rootItems(ctx, c).compactMap({ if case .row(let r) = $0 { r } else { nil } }).first {
        tapRow(first)
      }
    #endif
  }

  @ViewBuilder private func pane(_ ctx: BrowseContext, _ line: [String]) -> some View {
    if searching {
      if !query.trimmingCharacters(in: .whitespaces).isEmpty {
        BrowseListView(items: searchItems(query, ctx.reps, ctx.index, ctx.tree, ctx.catalog)) { row, first in rowView(ctx, row) }
      }
    } else if let chip {
      let items = trail.last?.items ?? (chip == .shelves ? nil : rootItems(ctx, chip))
      BrowseCrumbs(crumbs: [chip.label] + trail.map(\.label), filter: items == nil ? nil : $filter) { trail = Array(trail.prefix($0)) }
      if let items {
        BrowseListView(items: filtered(items, filter)) { row, _ in rowView(ctx, row) }
      } else {
        ShelvesGrid(catalog: ctx.catalog) { label, rows in trail = [BrowseLevel(label: label, items: rows.map { .row($0) })] }
      }
    } else {
      NextMovesList(moves: nextMoves(ctx.index, ctx.tree, ctx.catalog, line, repMoves(ctx.reps))) { play(line, $0) }
    }
  }

  private func rowView(_ ctx: BrowseContext, _ row: BrowseRow) -> some View {
    let at = nodeAt(ctx.tree, row.sans)
    let stats = at.flatMap { ctx.state.score.nodes[$0.id] }
    let held = stats.flatMap { $0.rated > 0 ? rankOf($0.rating, $0.rated).held : nil }
    return Button { tapRow(row) } label: {
      HStack(spacing: 12) {
        BrowseRowLabel(row: row)
        if let held { Text(held.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(SwiftUI.Color(hexString: held.color)) }
      }
      .padding(.horizontal, 14).padding(.vertical, 8).frame(minHeight: 56).contentShape(Rectangle())
      .modifier(RowTint(on: previewed == row.key))
    }
    .buttonStyle(.plain)
  }

  private func rootItems(_ ctx: BrowseContext, _ chip: BrowseChipId) -> [BrowseItem] {
    let key = "\(chip) \(ctx.reps.map { "\($0.id):\($0.nodes.count)" }.joined(separator: ","))"
    return memo.get(key) {
      switch chip {
      case .mine: return myLines(ctx.reps, ctx.index, ctx.tree)
      case .suggest: return suggestions(ctx.reps, ctx.index, ctx.tree, ctx.catalog).map { .row($0) }
      case .recent: return recentItems(ctx.tree, ctx.catalog, ctx.state.score)
      case .book: return bookItems(ctx.catalog)
      case .shelves: return []
      }
    }
  }

  /* actions */

  private func initialMoves(_ ctx: BrowseContext) -> [String] {
    let opening = store.state.settings.selection.opening
    return nodeById(ctx.tree, opening).sans
  }

  private func play(_ line: [String], _ san: String) {
    moves = line + [san]
    previewed = nil
  }

  private func undo(_ line: [String]) {
    moves = Array(line.dropLast())
    previewed = nil
  }

  private func tapRow(_ row: BrowseRow) {
    if searching {
      // The keyboard goes, so the board and the result's line show.
      UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
      resultShown = true
    }
    moves = row.sans
    sideSet = row.side
    previewed = row.key
    if let open = row.open { trail.append(BrowseLevel(label: row.label, items: open())) }
  }

  private func pickChip(_ next: BrowseChipId) {
    chip = chip == next ? nil : next
    trail = []
    searching = false
    query = ""
  }

  private func toggleSearch() {
    searching.toggle()
    query = ""
    resultShown = false
  }

  private func choose(_ ctx: BrowseContext, _ line: [String], _ side: ChessCore.Color) {
    // The book's own move order where it has one for this position, so ratings line up.
    let id = line.isEmpty ? "" : nodeAt(ctx.tree, line)?.id ?? line.joined(separator: " ")
    let chosenSide: ChessCore.Color? = line.isEmpty ? nil : side
    if let onChoose {
      if !id.isEmpty { onChoose(id.split(separator: " ").map(String.init), chosenSide) }
    } else {
      store.update { state in
        state.settings.selection.opening = id
        if let chosenSide { state.settings.selection.color = chosenSide == .w ? .w : .b }
      }
    }
    onClose()
  }
}

/// What the lists read, fetched once a redraw.
struct BrowseContext {
  let tree: OpeningTree
  let index: ReferenceIndex
  let catalog: PickerCatalog
  let state: AppState
  var reps: [Playbook] { state.playbookList }
}

/// The browser's lists: `CHIPS`.
enum BrowseChipId: CaseIterable {
  case mine, suggest, shelves, recent, book

  var label: String {
    switch self {
    case .mine: "My lines"
    case .suggest: "Suggestions"
    case .shelves: "Shelves"
    case .recent: "Recent"
    case .book: "Book"
    }
  }
}
