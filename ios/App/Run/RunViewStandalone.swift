import ChessCore
import Game
import Model
import SwiftUI

/// What a run you set up shows that Play's round does not.
extension RunView {
  /// The opening the run is announced as, by its trail.
  var introTrail: [String] {
    guard let catalog = store.catalog else { return [openingName(model.tree, model.introOpening)] }
    return selectionTrail(model.tree, catalog, model.introOpening)
  }
}
