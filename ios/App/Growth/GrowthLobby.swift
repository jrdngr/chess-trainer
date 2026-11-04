import Book
import ChessCore
import Model
import Shared

/// What Growth's lobby shows, worked out from the saved state.
/// Where the work is, shallowest first; and for a side with nothing in it
/// yet, where it starts.
struct GrowthLobby {
  /// Stands in for a side with no tree yet, until the first move is kept.
  static let standIn = "growth_stand_in_"

  let reps: [Repertoire]
  let regions: [SideRegion]
  let rows: [GrowthRow]
  /// Selected openings a side has no line into yet.
  let unstarted: [SideRegion]
  /// White with nothing yet: the book's first moves to pick from.
  let firstMoves: [Reply]
  let whiteEmpty: Bool
  let hasMoves: Bool
  /// Positions past the book the engine is still to be asked about.
  let asking: [String]

  init(_ state: AppState, _ tree: OpeningTree, _ index: ReferenceIndex) {
    let prefs = state.settings.growth
    let selection = state.settings.selection
    let starred = state.settings.favoriteOpenings
    let selected = regionsBySide(tree, selection, starred)
    regions = selected
    let have = repertoiresIn(state.repertoireList, selection.color)
    let reps = colorsOf(selection.color).map { color in
      have.first { $0.color == color } ?? createRepertoire(color == .w ? "White" : "Black", color, "\(Self.standIn)\(color.rawValue)")
    }
    self.reps = reps
    hasMoves = reps.contains { !$0.nodes.isEmpty }
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
      guard let rep = reps.first(where: { $0.color == region.side }) else { return false }
      return !reachesOpening(rep, tree, region.node)
    }
    pickInside = rows.first.map { inside.contains($0.id) } ?? false
  }

  /// The top row has replies inside a selected opening, not only on the way in.
  let pickInside: Bool

  var pick: GrowthRow? { recommended(rows) }

  /// The opening Start keeps and begins, ahead of the rows: one the
  /// Playbook does not reach yet, unless the top row already works inside one.
  var opening: SideRegion? { pickInside ? nil : unstarted.first }

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
