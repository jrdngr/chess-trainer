import Book
import ChessCore

/// What Growth changes in the app's state: `useStore`'s addLine for Growth; its removes are the Playbook's.
extension AppState {
  /// Grow a line in a side's tree, Growth's moves labelled Growth or Engine.
  public mutating func addGrowthLine(_ repertoireId: String, _ line: [String], _ index: ReferenceIndex) {
    addLine(repertoireId, line, .each(growthSource(index)), via: .growth)
  }
}

