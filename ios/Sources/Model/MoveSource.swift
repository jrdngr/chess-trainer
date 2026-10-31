import Book

/// Where a move came from, said in a word or two. `src/model/moveSource.ts`.
public let SOURCE_LABELS: [MoveSource: String] = [
  .picker: "Opening picker",
  .book: "Book",
  .growth: "Growth",
  .engine: "Engine",
  .manual: "Entered by hand",
  .analysis: "Analysis",
  .import: "Imported games",
  .play: "Play game",
  .tidy: "Tidy switch",
  .board: "Play on the board",
  .seed: "Sample",
]

public func sourceLabel(_ source: MoveSource?) -> String {
  SOURCE_LABELS[source ?? .manual]!
}

/// The book has this move here.
public func inBook(_ index: ReferenceIndex, _ fen: String, _ san: String) -> Bool {
  (lookup(index, fen)?.moves ?? []).contains { $0.san == san }
}

/// Growth's label for a move: Growth for the book's, Engine past it.
public func growthSource(_ index: ReferenceIndex) -> (_ fen: String, _ san: String) -> MoveSource {
  { fen, san in inBook(index, fen, san) ? .growth : .engine }
}
