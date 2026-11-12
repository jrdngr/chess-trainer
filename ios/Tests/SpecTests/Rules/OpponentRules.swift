import ChessCore
import Foundation
import Model
import Testing

private let RUY = "e4 e5 Nf3 Nc6 Bb5 a6 Ba4 Nf6"
private let NAJDORF = "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6"

/// A Drill run in an opening, as `beginRun` deals it.
private func begin(
  _ reps: [Playbook], _ node: OpeningNode, _ color: ColorChoice, at: [String]? = nil, seed: Double,
  steer: Steer = .popular, weakness: Weakness? = nil, seen: Seen? = nil, aim: [String]? = nil
) throws -> Begun {
  var opts = BeginOptions(tree: openingTree(bookIndex), reps: reps, node: node, color: color)
  opts.at = at
  opts.seed = seed
  opts.steer = steer
  opts.weakness = weakness
  opts.seen = seen
  opts.aim = aim
  return try #require(beginRun(opts))
}

private let seeds: [Double] = [1, 2, 3, 4, 5, 6, 7, 8]

@Suite("docs/rules/opponent.md") struct OpponentRules {
  /// Rule 1: the line drawn passes through the start and reaches the run's opening.
  @Test func drawsOneOfYourLinesInTheOpening() throws {
    let tree = openingTree(bookIndex)
    let black = rep(.b, ["d4 d5 c4 e6 Nc3 Nf6 Bg5 Be7", "d4 d5 c4 c6 Nf3 Nf6 Nc3 dxc4", "e4 e5 Nf3 Nc6"])
    let qgd = try #require(tree.byId["d4 d5 c4 e6"])
    for seed in seeds {
      let run = try begin([black], qgd, .b, at: line("d4"), seed: seed).run
      #expect(run.target == line("d4 d5 c4 e6 Nc3 Nf6 Bg5 Be7"))
    }
  }

  /// Rule 2: a line asking 4 of your moves beats a shorter one, however popular.
  @Test func longerLinesFirst() throws {
    let tree = openingTree(bookIndex)
    let white = rep(.w, [RUY, "e4 c5 Nf3"])
    for seed in seeds { #expect(try begin([white], tree.root, .w, seed: seed).run.target == line(RUY)) }
  }

  /// Rule 3: the line the last run played isn't drawn again while another is there.
  @Test func notTheSameLineTwiceRunning() throws {
    let tree = openingTree(bookIndex)
    let white = rep(.w, [RUY, NAJDORF])
    let seen = Seen(at: markSeen([:], line(RUY), 5), round: 5)
    for seed in seeds { #expect(try begin([white], tree.root, .w, seed: seed, seen: seen).run.target == line(NAJDORF)) }
  }

  /// Rule 4: Review leans weak and Test popular; only a weak lean reads weakness.
  @Test func reviewWeighsWeakness() throws {
    #expect(LEAN_FOR == [.test: .popular, .review: .weak])
    let tree = openingTree(bookIndex)
    let white = rep(.w, [RUY, NAJDORF])
    let sicilian = Set(walkSan(line(NAJDORF)).fens.dropFirst(2).map(positionKey))
    let weakness: Weakness = { _, key in sicilian.contains(key) ? 10_000 : 1 }
    for seed in seeds {
      #expect(try begin([white], tree.root, .w, seed: seed, steer: .weak, weakness: weakness).run.target == line(NAJDORF))
    }
    let popular = try seeds.map { try begin([white], tree.root, .w, seed: $0, weakness: weakness).run.target }
    #expect(popular.contains(line(RUY)))
  }

  /// Rule 5: a gap's line is followed while the run is on it.
  @Test func followsTheGapLine() throws {
    let tree = openingTree(bookIndex)
    let aim = line("e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3")
    let run = try begin([rep(.w, [RUY, NAJDORF])], tree.root, .w, seed: 1, aim: aim).run
    #expect(run.target == aim)
  }

  /// Rule 6: off the drawn line, a line through the new position is drawn.
  @Test func redrawsWhereTheRunStands() throws {
    let tree = openingTree(bookIndex)
    let white = rep(.w, [RUY, NAJDORF])
    let begun = try begin([white], tree.root, .w, seed: 1, seen: Seen(at: markSeen([:], line(NAJDORF), 5), round: 5))
    #expect(begun.run.target == line(RUY))
    var run = begun.run
    run.played = line("e4 c5")
    run.fen = walkSan(run.played).fens[2]
    #expect(begun.redraw(run).target == line(NAJDORF))
  }

  /// Rule 7: with no line to follow, a reply you have or a book move.
  @Test func repliesYouHaveOrBookMoves() throws {
    let tree = openingTree(bookIndex)
    let white = rep(.w, ["e4 e5 Nf3"])
    let source = regionSource(tree, tree.root, white, .w)
    let afterE4 = walkSan(line("e4")).fens[1]
    let replies = source.weightsAt(afterE4, line("e4")).map(\.san)
    let book = bookMoves(bookIndex, afterE4)
    #expect(replies.contains("e5"))
    #expect(replies.allSatisfy { $0 == "e5" || book.contains($0) })
    #expect(Set(book).isSubset(of: Set(replies)))
  }

  /// Rule 8: the engine's level is your strength to the nearest 50.
  @Test func engineAtYourStrength() {
    #expect(levelMatching(PlayerStrength(rating: 1234)) == levelFor(rating: 1250))
    #expect(levelMatching(PlayerStrength(rating: 1224)) == levelFor(rating: 1200))
  }

  /// Rule 9: strength starts at 1200 and moves at most 40 a move.
  @Test func strengthFollowsWhatMovesCost() {
    let start = PlayerStrength()
    #expect(start.rating == 1200)
    #expect(updatedStrength(start, lost: 0).rating == 1221)
    #expect(updatedStrength(start, lost: 70).rating == 1200)
    #expect(updatedStrength(start, lost: 300).rating == 1160)
    #expect(updatedStrength(start, lost: 5000).rating == 1160)
    #expect(updatedStrength(PlayerStrength(rating: 2200), lost: 0).rating == 2200)
  }
}
