import ChessCore
import Model
import Testing

@Test func moveQualityLines() {
  #expect(moveQuality(SCORE_SLIGHT) == nil)
  #expect(moveQuality(SCORE_SLIGHT + 1) == .dubious)
  #expect(moveQuality(BLUNDER_LIMIT) == .dubious)
  #expect(moveQuality(BLUNDER_LIMIT + 1) == .blunder)
}

@Test func savedPliesStopsWhereTheTreeEnds() {
  let tree = rep(.w, ["d4 d5 c4 e6", "d4 Nf6 c4"])
  #expect(savedPlies(tree, line("d4 d5 c4 e6 Nc3")) == 4)
  #expect(savedPlies(tree, line("d4 d5 Nf3")) == 2)
  #expect(savedPlies(tree, line("d4 Nf6 c4")) == 3)
  #expect(savedPlies(tree, line("e4 e5")) == 0)
  #expect(savedPlies(nil, line("d4")) == 0)
}
