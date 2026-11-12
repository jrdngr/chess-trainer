import ChessCore

/// What your mistakes say, as Play reads it: `evidenceIn`.

/// The positions in the selection you got wrong with a move prepared, from your logged mistakes.
public func evidenceIn(_ state: AppState, _ tree: OpeningTree, _ selection: Selection) -> [RepairItem] {
  let region = regionOf(tree, selection)
  let reps = playbooksIn(state.playbookList, selection.color)
  return buildRepairs(reps, state.mistakes).filter { lineInRegion(tree, region, $0.path) }
}

/// The evidence as the recommendation weighs it.
public func repairRefs(_ items: [RepairItem]) -> [RepairRef] {
  items.map { RepairRef(kind: "offprep", color: $0.color, fen: $0.fen) }
}

/// The evidence as `weaknessFromCards` reads it.
public func slips(_ items: [RepairItem]) -> [Slip] {
  items.map { Slip(kind: "offprep", playbookId: $0.playbookId, key: $0.key, games: 1) }
}
