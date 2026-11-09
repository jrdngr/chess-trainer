import Model

/// An opening as the app names it: the last of its picker trail, "Berlin Defence".
@MainActor
func openingName(_ tree: OpeningTree, _ id: String) -> String {
  let node = nodeById(tree, id)
  if node.depth == 0 { return "Any Opening" }
  return entryForNode(pickerCatalog(tree), node)?.label ?? node.name
}

/// How a run ended, as its title.
func endingTitle(_ ending: Ending, _ plies: Int) -> String {
  switch ending {
  case .blunder(_, _, _, _, let slip):
    // An endgame run ends on the result it gave away, not on a blunder.
    if let slip, let text = slipText(slip.from, slip.to) { return "\(text) on move \(moveNumber(plies))" }
    return "Blunder on move \(moveNumber(plies))"
  case .won: return "Checkmate, you won"
  case .lost: return "Checkmate, you lost"
  case .ended: return "Ended on move \(moveNumber(plies))"
  case .draw: return "Drawn"
  }
}

/// What the prompt says of your prep, and its color.
func prepStatusText(_ label: PrepLabel) -> (text: String, color: SwiftUIColor) {
  switch label {
  case .on: return ("On prep", Theme.warn)
  case .complete: return ("Prep complete", Theme.good)
  case .off: return ("Off prep", Theme.bad)
  // Past your line the common moves aren't called out: the line is simply done.
  case .book, .out: return ("Prep complete", Theme.good)
  case .middlegame: return ("Middlegame", PlanColors.plan)
  }
}

import SwiftUI
typealias SwiftUIColor = SwiftUI.Color
