import Model

/// An opening as the app names it: the last of its picker trail, "Berlin Defence".
@MainActor
func openingName(_ tree: OpeningTree, _ id: String) -> String {
  if id == ANY_FAVORITE { return "Any favorite" }
  let node = nodeById(tree, id)
  if node.depth == 0 { return "Any opening" }
  return entryForNode(pickerCatalog(tree), node)?.label ?? node.name
}

/// How a run ended, as its title: `End.tsx`.
func endingTitle(_ ending: Ending, _ plies: Int) -> String {
  switch ending {
  case .blunder: return "Blunder on move \(moveNumber(plies))"
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
  case .book: return ("In the book", Theme.book)
  case .out: return ("Out of book", Theme.text2)
  }
}

import SwiftUI
typealias SwiftUIColor = SwiftUI.Color
