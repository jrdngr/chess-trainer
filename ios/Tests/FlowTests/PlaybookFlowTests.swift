import ChessCore
import Foundation
import Game
import Model
import Testing

private func everyNode(_ list: [MapNode]) -> [MapNode] { list.flatMap { [$0] + everyNode($0.children) } }

/// An opening's page on the tree: Grow starts a Play run at the hole the curve allows under it,
/// growing there at once and leaving Home's selection as it was; Select makes Middlegame play out
/// a line through it, and Delete takes it until the undo puts it back.
@MainActor @Test func anOpeningsPageGrowsSelectsAndDeletes() async throws {
  try await headless { app in
    onboard(app)
    let owned = everyNode(app.map(.w)).filter { $0.owned && $0.line.count > 1 }
    let node = try #require(owned.first { if case .ready = app.page($0).grow { true } else { false } })
    guard case .ready(let gap) = app.page(node).grow else { return }
    #expect(gap.line.starts(with: node.line), "the hole is under the opening")
    let selection = app.state.settings.selection
    try await app.grow(node)
    #expect(app.screen == .play)
    let run = try #require(app.run)
    #expect(run.run.played == gap.line, "the run opens at the reply with no answer")
    #expect(run.fill?.gap.line == gap.line, "growth is open there")
    let answer = try #require(app.choices.first)
    try await app.move(answer)
    let rep = try #require(app.state.playbooks[gap.playbookId])
    #expect(nodeAtLine(rep, gap.line + [answer]) != nil, "the answer is in the Playbook")
    #expect(app.state.settings.selection == selection, "Home's selection is untouched")
    await app.home()

    try app.select(side: .w, opening: node.id)
    try await app.openMiddlegame()
    let handoff = try #require(app.run?.handoff)
    #expect(handoff.line.starts(with: node.line), "the line drawn goes through the selected opening")
    await app.home()

    let named = try #require(everyNode(app.map(.w)).first { $0.owned && $0.family != nil })
    #expect(throws: HeadlessApp.Failure.self) { try app.delete(named) }
    let branch = try #require(everyNode(app.map(.w)).first { $0.owned && app.state.canDelete($0.color, $0.line) })
    let undo = try app.delete(branch)
    #expect(!everyNode(app.map(.w)).contains { $0.id == branch.id && $0.owned })
    app.undo(undo)
    #expect(everyNode(app.map(.w)).contains { $0.id == branch.id && $0.owned })
  }
}

/// Turning an opening off: a second White opening bought, the first turned off from its page,
/// Play on Any Opening keeps to the one still on, and Enable on the tree brings it back.
@MainActor @Test func anOpeningTurnsOffAndBackOn() async throws {
  try await headless { app in
    onboard(app)
    let first = try #require(everyNode(app.map(.w)).first { $0.owned && $0.family != nil })
    #expect(throws: HeadlessApp.Failure.self) { try app.turnOpening(first, on: false) }
    let sale = try #require(everyNode(app.map(.w)).first { $0.forSale && $0.line.first != first.line.first })
    app.store.update { $0.pawns = 500 }
    try app.buyFamily(sale)
    try app.turnOpening(first, on: false)
    #expect(everyNode(app.map(.w)).contains { $0.id == first.id && $0.off })
    try app.select(side: .w, opening: ANY_OPENING)
    for _ in 0..<3 {
      await app.openPlay()
      let run = try #require(app.run)
      #expect(!run.run.played.starts(with: first.line), "Any Opening keeps out of it")
      await app.home()
    }
    try app.turnOpening(first, on: true)
    #expect(everyNode(app.map(.w)).contains { $0.id == first.id && !$0.off })
  }
}
