import ChessCore

/// What your games say, as Autopilot reads it: `evidenceIn` in
/// `store/recommendation.ts`, and `evidenceFor` in `model/growth.ts`.

/// What your games say about the selection: the positions you got wrong with
/// a move prepared, and the ones you kept reaching with nothing.
public func evidenceIn(_ state: AppState, _ tree: OpeningTree, _ selection: Selection) -> [RepairItem] {
  let region = regionOf(tree, selection)
  let reps = repertoiresIn(state.repertoireList, selection.color)
  return buildRepairs(state.importedGames, reps, RepairOptions(mistakes: state.mistakes))
    .filter { lineInRegion(tree, region, $0.path) }
}

/// The evidence as the recommendation weighs it.
public func repairRefs(_ items: [RepairItem]) -> [RepairRef] {
  items.map { RepairRef(kind: $0.kind.rawValue, color: $0.color, fen: $0.fen) }
}

/// The evidence as `weaknessFromCards` reads it.
public func slips(_ items: [RepairItem]) -> [Slip] {
  items.map { Slip(kind: $0.kind.rawValue, repertoireId: $0.repertoireId, key: $0.key, games: $0.games) }
}

/// How much a hole is worth filling, by how often your games reached it with nothing prepared.
public func evidenceFor(_ items: [RepairItem]) -> (Hole) -> Double {
  var games: [String: Int] = [:]
  for item in items where item.kind == .unprepared { games[positionKey(item.fen), default: 0] += item.games }
  if games.isEmpty { return { _ in 1 } }
  return { hole in 1 + Double(games[positionKey(hole.after)] ?? 0) }
}

extension AppState {
  /// Replace the imported games, keeping the ones played here: `setImportedGames`.
  public mutating func setImportedGames(_ games: [ImportedGame]) {
    importedGames = playGames(importedGames) + importedOnly(games)
  }
}
