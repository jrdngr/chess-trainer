import Model

/// An opening as the app names it: the last of its picker trail, "Berlin Defense".
@MainActor
public func openingName(_ tree: OpeningTree, _ id: String) -> String {
  let node = nodeById(tree, id)
  if node.depth == 0 { return "Any Opening" }
  return entryForNode(pickerCatalog(tree), node)?.label ?? node.name
}

/// How a run ended, as its title.
public func endingTitle(_ ending: Ending) -> String {
  switch ending {
  case .blunder(_, _, _, _, let slip):
    // An endgame run ends on the result it gave away, not on a blunder: "Win slipped to Draw".
    if let slip, slip.to < slip.from { return "\(resultWord(slip.from)) slipped to \(resultWord(slip.to))" }
    return "Blunder"
  case .won: return "Checkmate, you won"
  case .lost: return "Checkmate, you lost"
  case .ended: return "Ended"
  case .draw: return "Drawn"
  }
}

/// An endgame result as a title word.
private func resultWord(_ result: EndResult) -> String { result == .win ? "Win" : result == .draw ? "Draw" : "Loss" }

/// `Math.round`.
public func JSRound(_ x: Double) -> Double {
  let down = x.rounded(.down)
  return x - down >= 0.5 ? down + 1 : down
}
