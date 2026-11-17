import ChessCore
import Foundation
import Model
import Testing

@Suite("docs/rules/playbook.md") struct PlaybookRules {
  /// Rule 1: a line is book for as long as the book has each move, for either side.
  @Test func bookLengthStopsAtTheFirstMoveTheBookLacks() {
    #expect(bookLength(bookIndex, line("e4 e5 Nf3 Nc6 Bc4")) == 5)
    #expect(bookLength(bookIndex, line("e4 g5 d4 h6")) == 1)
    #expect(bookLength(bookIndex, []) == 0)
  }


  /// Rule 2: the tab is a tree of the openings your lines reach, with the ones the curve
  /// will add hanging locked under the nearest one you have, and exactly one Next.
  @Test func theTreeHangsLockedOpeningsInPlace() throws {
    let tree = openingTree(bookIndex)
    var state = AppState()
    let id = state.ensurePlaybook(.w)
    state.addLine(id, line("e4 e5 Nf3 Nc6 Bb5 a6"), .fixed(.book))
    state.addLine(id, line("d4 d5 c4 e6"), .fixed(.book))
    let roots = playbookMap(state, tree, side: .w)
    #expect(roots.filter(\.owned).map(\.id) == ["e4", "d4"])
    #expect(roots.filter { !$0.owned }.allSatisfy { $0.forSale }, "the other first moves are families for sale")
    func all(_ list: [MapNode]) -> [MapNode] { list.flatMap { [$0] + all($0.children) } }
    let nodes = all(roots)
    let next = nodes.filter { if case .next = $0.state { return true } else { return false } }
    #expect(next.count == 1)
    #expect(next.first?.gap?.id == curvePlaybookGaps(state, tree).first?.id)
    #expect(nextMapNode(state, tree)?.id == next.first?.id, "Home's line opens the tree at it")
    // 1...c5 waits for level 1 under 1.e4, its first locked reply after those you have.
    let e4 = roots[0]
    let sicilian = try #require(e4.children.first { $0.line == line("e4 c5") })
    #expect(sicilian.state == .locked(.games(40)))
    #expect(e4.children.first?.owned == true)
    #expect(nodes.filter(\.owned).allSatisfy { $0.lines >= 1 && $0.gap == nil })
    #expect(nodes.filter { !$0.owned && !$0.forSale }.allSatisfy { $0.gap != nil && $0.children.isEmpty })
  }

  /// Rule 3: a tap opens an opening's branches; a tap on the open one folds it.
  @Test func tappingOpensAndFolds() throws {
    let tree = openingTree(bookIndex)
    var state = AppState()
    state.addLine(state.ensurePlaybook(.w), line("e4 e5 Nf3 Nc6 Bb5 a6"), .fixed(.book))
    let roots = playbookMap(state, tree, side: .w)
    let family = try #require(roots[0].children.first { $0.owned })
    var path = mapTap(roots, path: [], roots[0].id)
    #expect(mapRows(roots, path: path).count == 2)
    path = mapTap(roots, path: path, family.id)
    #expect(path == [roots[0].id, family.id])
    #expect(mapTap(roots, path: path, family.id) == [roots[0].id])
    #expect(mapPath(roots, to: family.id) == [roots[0].id, family.id])
  }

  /// Rule 3: a row of more than four goes on two tiers, yours above and locked below, never overlapping.
  @Test func wideRowsTakeTwoTiers() throws {
    let tree = openingTree(bookIndex)
    var state = AppState()
    state.addLine(state.ensurePlaybook(.w), line("e4 e5 Nf3 Nc6 Bb5 a6"), .fixed(.book))
    let roots = playbookMap(state, tree, side: .w)
    let rows = mapRows(roots, path: [roots[0].id])
    let wide = try #require(rows.last)
    try #require(wide.count > MAP_TIER)
    let tiers = try #require(mapTiers(wide))
    let mine = wide.filter(\.owned).count, locked = wide.count - mine
    if mine <= MAP_TIER && locked <= MAP_TIER {
      #expect(tiers.upper.allSatisfy(\.owned) && tiers.lower.allSatisfy { !$0.owned })
    } else {
      #expect(tiers.upper + tiers.lower == wide && tiers.upper.count - tiers.lower.count <= 1, "halves by rank")
    }
    let layout = mapLayout(rows, width: 402, nodeHeight: 100)
    let upper = tiers.upper.compactMap { layout.spots[$0.id] }, lower = tiers.lower.compactMap { layout.spots[$0.id] }
    #expect(lower.allSatisfy { low in upper.allSatisfy { low.y >= $0.y + 100 } })
    let xs = (upper + lower).map(\.x)
    #expect(Set(xs.map { Int($0) }).count == xs.count, "every link has its own lane")
    #expect(layout.spots.values.allSatisfy { $0.x - $0.width / 2 >= 0 && $0.x + $0.width / 2 <= 402 })
  }

  /// Rule 3: what a locked opening shows under its name.
  @Test func lockedOpeningsSayWhen() {
    #expect(mapWhen(.owned) == nil)
    #expect(mapWhen(.next(runs: 2)) == "~2 games")
    #expect(mapWhen(.next(runs: 0)) == "Next game")
    #expect(mapWhen(.locked(.games(40))) == "Game 40")
    #expect(mapWhen(.locked(.green(7, of: 9))) == "Green 7/9")
  }
}
