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
    #expect(roots.filter { !$0.owned }.allSatisfy { $0.state == .way }, "other first moves hold the openings for sale there")
    func all(_ list: [MapNode]) -> [MapNode] { list.flatMap { [$0] + all($0.children) } }
    let nodes = all(roots)
    let next = nodes.filter { if case .next = $0.state { return true } else { return false } }
    #expect(next.count == 1)
    #expect(next.first?.gap?.id == curvePlaybookGaps(state, tree).first?.id)
    #expect(nextMapNode(state, tree)?.id == next.first?.id, "Home's line opens the tree at it")
    // The Italian is for sale under 1.e4, after what you have.
    let e4 = roots[0]
    #expect(all([e4]).contains { $0.family == "italian" && $0.forSale })
    #expect(e4.children.first?.owned == true)
    #expect(nodes.filter(\.owned).allSatisfy { $0.lines >= 1 && $0.gap == nil })
    #expect(nodes.filter { !$0.owned && !$0.forSale && $0.state != .way }.allSatisfy { $0.gap != nil && $0.children.isEmpty })
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

  /// Rule 4: an opening's page counts your moves to it and under it, and its form is its last answers.
  @Test func anOpeningsPageIsAboutItsPosition() throws {
    let tree = openingTree(bookIndex)
    var state = AppState()
    state.addLine(state.ensurePlaybook(.w), line("d4 d5 c4 e6 Nc3 Nf6"), .fixed(.book))
    state.addLine(state.playbookList[0].id, line("e4 e5 Nf3"), .fixed(.book))
    let qgd = try #require(deepestNodeAlong(tree, line("d4 d5 c4 e6")))
    for _ in 0..<4 { state.form[.w][qgd.id, default: []].append(1) }
    var page = nodePage(state, tree, side: .w, id: qgd.id, line: qgd.sans)
    #expect(page.movesKnown == 3, "d4, c4 and Nc3; not the 1.e4 line")
    #expect(page.answers == [1, 1, 1, 1] && page.form == nil, "no form under 5 answers")
    state.form[.w][qgd.id, default: []].append(0)
    page = nodePage(state, tree, side: .w, id: qgd.id, line: qgd.sans)
    #expect(page.form == 0.8)
    let holes = curveHoles(curveSides(state), bookIndex, tree: tree)
    #expect(page.linesToGrow == holes.filter { $0.line.count > 4 && $0.line.starts(with: qgd.sans) }.count)
    #expect(page.linesToGrow > 0)
  }

  /// Rule 5: Grow takes the first hole under the opening an open level allows; else it says what it waits for.
  @Test func growWaitsForTheCurve() throws {
    let tree = openingTree(bookIndex)
    let all = curveHoles([rep(.w, ["c4 e5 Nc3 Nf6 Nf3 Nc6"])], bookIndex, tree: tree)
    let depth = all.filter { curveLevel($0) == 0 }
    let first = all.filter { curveLevel($0) == 1 }
    try #require(!depth.isEmpty && !first.isEmpty)
    let green = CurveGate(games: 40, green: 3, openings: 3)
    #expect(nodeGrow(depth, all, green) == .ready(depth[0]))
    #expect(nodeGrow(first, all, green) == .after(next: depth[0], count: depth.count), "depth holes elsewhere grow first")
    let short = CurveGate(games: 25, green: 2, openings: 3)
    #expect(nodeGrow(first, first, short) == .level(1, games: 25, gamesNeeded: 40, green: 2, openings: 3))
    #expect(nodeGrow([], all, green) == .none)
  }

  /// Rule 7: Delete takes the opening's last move and everything after it, and the undo puts it back.
  @Test func deleteTakesTheOpeningAndUndoes() throws {
    var state = AppState()
    state.addLine(state.ensurePlaybook(.w), line("d4 d5 c4 e6 Nc3 Nf6"), .fixed(.book))
    state.addLine(state.playbookList[0].id, line("d4 d5 c4 c6 Nf3"), .fixed(.book))
    let qgd = line("d4 d5 c4 e6")
    #expect(state.movesUnder(.w, qgd) == 3)
    let removed = state.removeNodeAt(.w, qgd)
    let undo = try #require(removed)
    let rep = state.playbookList[0]
    #expect(nodeAtLine(rep, qgd) == nil)
    #expect(nodeAtLine(rep, line("d4 d5 c4 c6 Nf3")) != nil, "the Slav stays")
    state.undo(undo)
    #expect(nodeAtLine(state.playbookList[0], line("d4 d5 c4 e6 Nc3 Nf6")) != nil)
  }
}
