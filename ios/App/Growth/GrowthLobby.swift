import Book
import ChessCore
import Model
import Shared

/// What Growth's lobby shows, worked out from the saved state with the
/// chosen opening's own line in it: a sitting keeps that line with its
/// moves, and Save Line writes both. Where the work is, inside the opening
/// first; and for a side with nothing in it yet, where it starts.
struct GrowthLobby {
  /// Stands in for a side with no tree yet, until the first move is kept.
  static let standIn = "growth_stand_in_"

  /// How a sitting on a row begins: the hole it stands on, when not the
  /// row's own first, and the line kept with its moves.
  struct Launch {
    var hole: Hole?
    var keep: (sans: [String], source: MoveSource)?
  }

  /// The saved trees, one per side in the selection.
  let saved: [Repertoire]
  /// The same with the chosen opening's line in them: what the rows are found in.
  let reps: [Repertoire]
  let regions: [SideRegion]
  let rows: [GrowthRow]
  /// The chosen opening's own line, per side: none for Any opening or Any favorite.
  let keeps: [Color: [String]]
  /// Sides whose saved tree lacks some of that line.
  let fresh: Set<Color>
  /// Favorites a side has no line into yet.
  let unstarted: [SideRegion]
  /// White with nothing yet: the book's first moves to pick from.
  let firstMoves: [Reply]
  let whiteEmpty: Bool
  let hasMoves: Bool
  /// Positions past the book the engine is still to be asked about.
  let asking: [String]
  /// The top row has replies inside a selected opening, not only on the way in.
  let pickInside: Bool

  init(_ state: AppState, _ tree: OpeningTree, _ index: ReferenceIndex) {
    let prefs = state.settings.growth
    let selection = state.settings.selection
    let starred = state.settings.favoriteOpenings
    let selected = regionsBySide(tree, selection, starred)
    regions = selected
    let have = repertoiresIn(state.repertoireList, selection.color)
    let saved = colorsOf(selection.color).map { color in
      have.first { $0.color == color } ?? createRepertoire(color == .w ? "White" : "Black", color, "\(Self.standIn)\(color.rawValue)")
    }
    self.saved = saved
    var keeps: [Color: [String]] = [:]
    if !isAnyFavorite(selection) {
      for region in selected where region.node.depth > 0 { keeps[region.side] = openingLine(index, region.node, region.side) }
    }
    self.keeps = keeps
    var fresh = Set<Color>()
    let reps = saved.map { rep -> Repertoire in
      guard let line = keeps[rep.color] else { return rep }
      let kept = addLine(rep, line, .fixed(.picker))
      if kept.added > 0 { fresh.insert(rep.color) }
      return kept.rep
    }
    self.fresh = fresh
    self.reps = reps
    hasMoves = saved.contains { !$0.nodes.isEmpty }
    whiteEmpty = reps.contains { $0.color == .w && $0.nodes.isEmpty }
    firstMoves = whiteEmpty ? optionsAt(index, START_FEN, 5) : []
    asking = prefs.pastBook
      ? reps.flatMap { enginePositions($0, index, GrowthOptions(minShare: prefs.minShare, maxPly: prefs.maxPly)) } : []
    let found = acrossRegions(selected, reps, { rep, node in
      growthRows([rep], index, GrowthOptions(
        minShare: prefs.minShare, maxPly: prefs.maxPly, starred: starred, region: (tree, node), pastBook: prefs.pastBook))
    }, \.id)
    // Replies inside a selected opening come before the ones on the way in.
    let inside = Set(found.filter { row in selected.contains { $0.side == row.color && rowReaches(tree, $0.node, row) } }.map(\.id))
    rows = found.jsSorted { a, b in
      let first = (inside.contains(b.id) ? 1 : 0) - (inside.contains(a.id) ? 1 : 0)
      if first != 0 { return Double(first) }
      if b.score != a.score { return b.score - a.score }
      if a.depth != b.depth { return Double(a.depth - b.depth) }
      return Double(JS.localeCompare(a.name, b.name))
    }
    unstarted = selected.filter { region in
      guard region.node.depth > 0, let rep = reps.first(where: { $0.color == region.side }) else { return false }
      return !reachesOpening(rep, tree, region.node)
    }
    pickInside = rows.first.map { inside.contains($0.id) } ?? false
  }

  /// Where the chosen opening's line is new, the reply at its end; otherwise the top row.
  var pick: GrowthRow? {
    for (side, line) in keeps where fresh.contains(side) {
      if let tip = holeAtTip(rows, line) { return tip.row }
    }
    return recommended(rows)
  }

  /// A sitting on a row keeps its side's opening line, and starts at the
  /// line's end while that line is new.
  func launch(_ row: GrowthRow) -> Launch {
    guard let line = keeps[row.color] else { return Launch() }
    let hole = fresh.contains(row.color) ? holeAtTip([row], line)?.hole : nil
    return Launch(hole: hole, keep: (line, .picker))
  }

  /// The favorite Start begins, ahead of the rows: one the Playbook does not
  /// reach yet, unless the top row already works inside one.
  var opening: SideRegion? { pickInside ? nil : unstarted.first }

  /// A sitting that keeps a line not yet in a side's tree and starts on the
  /// reply most worth answering at its end: a favorite's own moves, or a first move.
  static func lineStart(
    _ state: AppState, _ tree: OpeningTree, _ index: ReferenceIndex, _ side: Color, _ line: [String], region: OpeningNode?,
    source: MoveSource
  ) -> (row: GrowthRow, launch: Launch)? {
    let prefs = state.settings.growth
    let rep = state.repertoireList.first { $0.color == side }
      ?? createRepertoire(side == .w ? "White" : "Black", side, "\(standIn)\(side.rawValue)")
    let kept = addLine(rep, line, .fixed(source)).rep
    let rows = growthRows([kept], index, GrowthOptions(
      minShare: prefs.minShare, maxPly: prefs.maxPly, starred: state.settings.favoriteOpenings,
      region: region.map { (tree: tree, node: $0) }, pastBook: prefs.pastBook))
    guard let tip = holeAtTip(rows, line) else { return nil }
    return (tip.row, Launch(hole: tip.hole, keep: (line, source)))
  }

  var subtitle: String { rows.count == 1 ? "1 opening to extend" : "\(rows.count) openings to extend" }

  /// Why there is nothing to extend, and what to change.
  func emptyHint(_ prefs: GrowthPrefs, _ selection: Selection) -> String {
    let scope = isAnyFavorite(selection)
      ? " in your favorites" : regions.first.map { $0.node.depth > 0 ? " in \($0.node.name)" : "" } ?? ""
    return "Your Playbook meets every reply strong players choose in \(JS.string(prefs.minShare))% of games or more\(scope), "
      + "down to \(Int((Double(prefs.maxPly) / 2).rounded(.up))) moves. Lower the threshold below, or widen the opening, to keep going."
  }
}

/// What a row holds: replies to answer.
func repliesLabel(_ row: GrowthRow) -> String {
  row.holes.count == 1 ? "1 reply" : "\(row.holes.count) replies"
}
