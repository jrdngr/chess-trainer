import ChessCore
import Model
import Testing

/// A position met first by a longer move order, then by a shorter one, keeps the answers from both.
@Test func decisionPointKeepsOptionsFromLongerRoute() {
  // 1.e3 e6 2.e4 e5 is 1.e4 e5 with a tempo lost by each side; the longer route is walked first.
  let r = rep(.w, ["e3 e6 e4 e5 Nf3", "e4 e5 Nc3"])
  let points = decisionPoints(r)
  let point = points.first { $0.pathSans == ["e4", "e5"] }
  #expect(point?.options.map(\.san).sorted() == ["Nc3", "Nf3"])
  #expect(!points.contains { $0.pathSans == ["e3", "e6", "e4", "e5"] })
}
