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

  /// Rule 3: the tree stands on four columns, each branch row starting under its opening; a row of
  /// more than four hangs off the opening's trunk in lines of three beside it, the last of up to four.
  @Test func rowsHangOffTheTrunk() throws {
    #expect(mapColumns(3, parent: 0) == [[0, 1, 2]])
    #expect(mapColumns(3, parent: 3) == [[1, 2, 3]], "no room to the right: the row ends at the edge")
    #expect(mapColumns(10, parent: 1) == [[0, 2, 3], [0, 2, 3], [0, 1, 2, 3]])
    #expect(mapColumns(5, parent: 0) == [[1, 2, 3], [0, 1]])

    let tree = openingTree(bookIndex)
    var state = AppState()
    state.addLine(state.ensurePlaybook(.w), line("e4 e5 Nf3 Nc6 Bb5 a6"), .fixed(.book))
    let roots = playbookMap(state, tree, side: .w)
    let path = [roots[0].id]
    let rows = mapRows(roots, path: path)
    let wide = try #require(rows.last)
    try #require(wide.count > MAP_COLUMNS)
    let layout = mapLayout(rows, path: path, width: 402)
    let columns = (0..<MAP_COLUMNS).map { mapColumn($0, width: 402) }
    let spots = try wide.map { try #require(layout.spots[$0.id]) }
    #expect(spots.allSatisfy { spot in columns.contains(spot.x) && spot.x - spot.width / 2 >= 0 && spot.x + spot.width / 2 <= 402 })
    #expect(Set(spots.map { "\($0.x),\($0.y)" }).count == spots.count, "no two openings in one place")
    let parent = try #require(layout.spots[roots[0].id])
    let lines = Dictionary(grouping: spots, by: \.y).sorted { $0.key < $1.key }.map(\.value)
    #expect(lines.allSatisfy { $0.count <= MAP_COLUMNS })
    #expect(lines.dropLast().allSatisfy { $0.allSatisfy { $0.x != parent.x } }, "the trunk's column stays clear")
    #expect(lines.last?.contains { $0.x == parent.x } == true, "the trunk ends in the last line")

    let links = mapLinks(layout, rows, path: path)
    for spot in spots {
      #expect(links.contains { $0.points.last == MapPoint(spot.x, spot.y - MAP_LINK_GAP) }, "every opening has its link")
    }
    let trunk = links.filter { $0.points.allSatisfy { $0.x == parent.x } }
    #expect(trunk.map(\.points.first!.y).min() ?? 0 > parent.y + MAP_DISC, "the trunk starts under its opening")
  }

  /// Rule 3: the open path runs straight down from each opening to the first of its branches.
  @Test func theOpenPathIsStraight() throws {
    let tree = openingTree(bookIndex)
    var state = AppState()
    state.addLine(state.ensurePlaybook(.w), line("d4 d5 c4 e6 Nc3 Nf6"), .fixed(.book))
    let roots = playbookMap(state, tree, side: .w)
    let d4 = try #require(roots.first { $0.id == "d4" })
    let child = try #require(d4.children.first)
    let path = [d4.id, child.id]
    let rows = mapRows(roots, path: path)
    let layout = mapLayout(rows, path: path, width: 393)
    let top = try #require(layout.spots[d4.id]), below = try #require(layout.spots[child.id])
    #expect(top.x == below.x)
    let hot = mapLinks(layout, rows, path: path).filter { $0.kind == .path }
    #expect(!hot.isEmpty && hot.allSatisfy { $0.points.allSatisfy { $0.x == top.x } })
  }

  /// Rule 3: what a locked opening shows under its name.
  @Test func lockedOpeningsSayWhen() {
    #expect(mapWhen(.owned) == nil)
    #expect(mapWhen(.next(runs: 2)) == "~2 games")
    #expect(mapWhen(.next(runs: 0)) == "Next game")
    #expect(mapWhen(.locked(.games(40))) == "Game 40")
    #expect(mapWhen(.locked(.green(7, of: 9))) == "Green 7/9")
  }

  /// Rule 4: an opening's page shows its form: its last answers and their average.
  @Test func anOpeningsPageIsAboutItsPosition() throws {
    let tree = openingTree(bookIndex)
    var state = AppState()
    state.addLine(state.ensurePlaybook(.w), line("d4 d5 c4 e6 Nc3 Nf6"), .fixed(.book))
    let qgd = try #require(deepestNodeAlong(tree, line("d4 d5 c4 e6")))
    let fen = walkSan(qgd.sans).fens.last!
    for _ in 0..<4 { state.logEvent(AppEvent(kind: "prep-answer", color: .w, san: "Nc3", fen: fen, text: "easy")) }
    var page = nodePage(state, tree, side: .w, id: qgd.id, line: qgd.sans)
    #expect(page.answers == [1, 1, 1, 1] && page.form == nil, "no form under 5 answers")
    state.logEvent(AppEvent(kind: "prep-miss", color: .w, san: "h3", fen: fen, best: "Nc3"))
    page = nodePage(state, tree, side: .w, id: qgd.id, line: qgd.sans)
    #expect(page.form == 0.8)
  }

  /// Rule 4: an opening you reach in another order than the book's opens at your own moves.
  @Test func aTransposedOpeningOpensAtYourLine() throws {
    let tree = openingTree(bookIndex)
    var state = AppState()
    let yours = line("d4 d5 c4 e6 Nc3 Nf6 cxd5 exd5 Bg5")
    state.addLine(state.ensurePlaybook(.w), yours, .fixed(.book))
    let named = try #require(tree.byKey[positionKey(walkSan(yours).fens.last!)])
    try #require(named.sans != yours, "the book names this position by another move order")
    func find(_ nodes: [MapNode]) -> MapNode? {
      nodes.lazy.compactMap { $0.id == named.id ? $0 : find($0.children) }.first
    }
    let node = try #require(find(playbookMap(state, tree, side: .w)))
    #expect(node.line == yours)
    #expect(nodeAtLine(state.playbookList[0], node.line) != nil)
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

  /// Rule 5: Grow starts a Play run at the hole, the moves to it played for you, growing there whatever the
  /// answer at the hole; a hole at Black's first move starts from move one.
  @Test func growStartsARunAtTheHole() throws {
    let tree = openingTree(bookIndex)
    let gap = try #require(curveHoles([rep(.w, ["c4 e5 Nc3 Nf6 Nf3 Nc6"])], bookIndex, tree: tree).first)
    let round = growRound(tree, gap)
    #expect(round.at == gap.line && round.aim == gap.line && round.grow?.line == gap.line)
    #expect(round.pick.color == .w && gap.line.starts(with: round.pick.opening.sans))

    var first = gap
    first.hole.path = []
    first.color = .b
    let opening = growRound(tree, first)
    #expect(opening.at == nil && opening.grow?.hole.path == [], "Black's first answer is added from move one")
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

  /// Rule 4: View lines lists your Playbook's moves from the board's position, in its order, both sides'.
  @Test func viewLinesListsYourNextMoves() {
    var state = AppState()
    let id = state.ensurePlaybook(.b)
    state.addLine(id, line("d4 Nf6 c4 g6 Nf3 Bg7"), .fixed(.book))
    state.addLine(id, line("d4 Nf6 c4 g6 Nc3 Bg7"), .fixed(.book))
    state.addLine(id, line("d4 Nf6 Bf4 d5"), .fixed(.book))
    #expect(state.nextMoves(.b, []) == ["d4"])
    #expect(state.nextMoves(.b, line("d4 Nf6")) == ["c4", "Bf4"], "their replies, in the Playbook's order")
    #expect(state.nextMoves(.b, line("d4 Nf6 c4 g6 Nc3")) == ["Bg7"], "your move")
    #expect(state.nextMoves(.b, line("d4 Nf6 c4 g6 Nc3 Bg7")).isEmpty, "the line ends")
    #expect(state.nextMoves(.b, line("e4")).isEmpty, "not your line")
    #expect(state.nextMoves(.w, []).isEmpty, "no White Playbook")
  }

  /// Rule 4: each move View lines lists is followed by up to the next 3 of its line: your preferred
  /// move on your turn, the first reply in your Playbook on theirs.
  @Test func viewLinesShowsTheLineAfterEachMove() throws {
    var state = AppState()
    let id = state.ensurePlaybook(.b)
    state.addLine(id, line("d4 Nf6 c4 g6 Nf3 Bg7 g3 O-O"), .fixed(.book))
    state.addLine(id, line("d4 Nf6 c4 g6 Nf3 Bg7 Nc3 O-O"), .fixed(.book))
    state.addLine(id, line("d4 Nf6 c4 e6"), .fixed(.book))
    let rep = state.playbookList[0]
    let e6 = try #require(nodeAtLine(rep, line("d4 Nf6 c4 e6")))
    state.playbooks[id] = setPreferred(rep, e6.id)
    #expect(state.lineAfter(.b, line("d4 Nf6")) == line("c4 e6"), "your preferred move, then the line ends")
    #expect(state.lineAfter(.b, line("d4 Nf6 c4 g6")) == line("Nf3 Bg7 g3"), "their first reply, cut at 3")
    #expect(state.lineAfter(.b, line("d4 Nf6 c4 g6 Nf3 Bg7 g3 O-O")).isEmpty, "the end of a line")
  }

  /// Rule 7: in View lines, Delete takes the move on the board past the opening and everything after it;
  /// the move before it lists what is left.
  @Test func viewLinesDeletesTheMoveOnTheBoard() throws {
    var state = AppState()
    let id = state.ensurePlaybook(.b)
    state.addLine(id, line("d4 Nf6 c4 g6 Nc3 Bg7 e4 d6 f3 O-O Be3 c5"), .fixed(.book))
    state.addLine(id, line("d4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O Be2 e5"), .fixed(.book))
    let samisch = line("d4 Nf6 c4 g6 Nc3 Bg7 e4 d6 f3")
    #expect(state.movesUnder(.b, samisch) == 4)
    let removed = state.removeNodeAt(.b, samisch)
    let undo = try #require(removed)
    #expect(state.nextMoves(.b, line("d4 Nf6 c4 g6 Nc3 Bg7 e4 d6")) == ["Nf3"])
    state.undo(undo)
    #expect(state.nextMoves(.b, line("d4 Nf6 c4 g6 Nc3 Bg7 e4 d6")) == ["f3", "Nf3"])
  }

  /// Rule 8: only Sharp, Solid, Gambit and System tag an opening, down through the lines under it.
  @Test func onlyFourShelvesTag() throws {
    let tree = openingTree(bookIndex)
    func tag(_ moves: String) throws -> String? { shelfOf(tree, try #require(tree.byId[moves]))?.id }
    #expect(try tag("e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6") == "sharp", "the Najdorf")
    #expect(try tag("e4 e5 f4") == "gambits", "the King's Gambit, on Gambits and Sharp, takes the first")
    #expect(try tag("d4 d5 c4") == nil, "the Queen's Gambit sits only on Classical")
    #expect(try tag("e4 e5 Nf3 Nc6 Bb5") == nil, "the Ruy Lopez sits only on Classical")
  }
}
