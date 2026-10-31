import Book
import ChessCore
import Model
import Shared

/// What Growth's lobby shows, worked out from the saved state: `Lobby.tsx`.
/// Where the work is, shallowest first; and for a side with nothing in it
/// yet, where it starts.
struct GrowthLobby {
  /// Stands in for a side with no tree yet, until the first move is kept.
  static let standIn = "growth_stand_in_"

  let reps: [Repertoire]
  let regions: [SideRegion]
  let rows: [GrowthRow]
  /// Selected openings a side has no line into and no work on the way to.
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
    regions = regionsBySide(tree, selection, starred)
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
    rows = acrossRegions(regions, reps, { rep, node in
      growthRows([rep], index, GrowthOptions(
        minShare: prefs.minShare, maxPly: prefs.maxPly, starred: starred, region: (tree, node), pastBook: prefs.pastBook))
    }, \.id).jsSorted { a, b in
      if b.score != a.score { return b.score - a.score }
      if a.depth != b.depth { return Double(a.depth - b.depth) }
      return Double(JS.localeCompare(a.name, b.name))
    }
    unstarted = regions.filter { region in
      guard let rep = reps.first(where: { $0.color == region.side }), !reachesOpening(rep, tree, region.node) else { return false }
      let opts = GrowthOptions(minShare: prefs.minShare, maxPly: prefs.maxPly, region: (tree, region.node), pastBook: prefs.pastBook)
      return growthRows([rep], index, opts).isEmpty
    }
  }

  var pick: GrowthRow? { recommended(rows) }

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
