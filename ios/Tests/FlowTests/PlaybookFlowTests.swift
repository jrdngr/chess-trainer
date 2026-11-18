import ChessCore
import Foundation
import Game
import Model
import Testing

private func everyNode(_ list: [MapNode]) -> [MapNode] { list.flatMap { [$0] + everyNode($0.children) } }

/// An opening's page on the tree: Grow fills the hole the curve allows under it, Middlegame
/// plays out a line through it, and Delete takes it until the undo puts it back.
@MainActor @Test func anOpeningsPageGrowsPlaysAndDeletes() async throws {
  try await headless { app in
    onboard(app)
    let owned = everyNode(app.map(.w)).filter { $0.owned && $0.line.count > 1 }
    let node = try #require(owned.first { if case .ready = app.page($0).grow { true } else { false } })
    guard case .ready(let gap) = app.page(node).grow else { return }
    #expect(gap.line.starts(with: node.line), "the hole is under the opening")
    try await app.grow(node)
    #expect(app.screen == .growth)
    await app.home()

    try await app.openMiddlegame(from: Selection(color: .w, opening: node.id))
    let handoff = try #require(app.run?.handoff)
    #expect(handoff.line.starts(with: node.line), "the line drawn goes through the opening")
    await app.home()

    let undo = try app.delete(node)
    #expect(!everyNode(app.map(.w)).contains { $0.id == node.id && $0.owned })
    app.undo(undo)
    #expect(everyNode(app.map(.w)).contains { $0.id == node.id && $0.owned })
  }
}
