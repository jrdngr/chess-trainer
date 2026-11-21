import ChessCore
import Foundation
import Model
import Shared
import Testing

/// The opening name functions in Golden/cases/functions/picker.json, set up as
/// `src/Golden/cases/picker.cases.ts` sets them up.
@Test func openingNames() throws {
  let tree = openingTree(bookIndex)
  let catalog = pickerCatalog(tree)
  try check("picker", [
    "browse.shortName": { shortName($0[0].string).json },
    "browse.lineName": { lineName(tree, catalog, line($0[0].string)).json },
  ], only: ["browse.shortName", "browse.lineName"])
}
