import Model
import Testing

/// The Eval lens tints your last judged move's squares by what it did to the eval, and only while it is your latest move.
@Test func evalLensTintsYourLastJudgedMove() {
  func tints(_ swing: Double?, ply: Int = 8, played: Int = 10) -> [String] {
    evalLensTints(JudgedMark(ply: ply, san: "Nc7+", from: "b5", to: "c7", swing: swing), played: played)
      .map { "\($0.square):\($0.color.rawValue):\($0.strength)" }
  }
  #expect(tints(310) == ["b5:green:3", "c7:green:3"])
  #expect(tints(-40) == ["b5:amber:3", "c7:amber:3"])
  #expect(tints(-41) == ["b5:red:3", "c7:red:3"])
  // Before the reply, the move is still the last one on the board.
  #expect(tints(-90, ply: 9, played: 10) == ["b5:red:3", "c7:red:3"])
  // A later move of yours took its place.
  #expect(tints(310, ply: 7, played: 10).isEmpty)
  // Nothing changed, or the swing crossed a mate: no tint.
  #expect(tints(0).isEmpty)
  #expect(tints(nil).isEmpty)
  #expect(evalLensTints(nil, played: 10).isEmpty)
}
