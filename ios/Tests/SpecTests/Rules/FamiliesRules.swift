import ChessCore
import Foundation
import Model
import Testing

/// The Italian as White, 1...e5 and the Queen's Gambit Declined as Black.
private func starter() -> AppState {
  var state = AppState()
  let w = state.ensurePlaybook(.w), b = state.ensurePlaybook(.b)
  state.addLine(w, line("e4 e5 Nf3 Nc6 Bc4 Bc5"), .fixed(.book))
  state.addLine(b, line("e4 e5 Nf3 Nc6"), .fixed(.book))
  state.addLine(b, line("d4 d5 c4 e6 Nc3 Nf6"), .fixed(.book))
  return state
}

private func all(_ list: [MapNode]) -> [MapNode] { list.flatMap { [$0] + all($0.children) } }

@Suite("docs/rules/families.md") struct FamiliesRules {
  /// Rule 1: every opening on the list is a book line ending on its own side's move, and none sits inside another.
  @Test func theListIsCurated() {
    let tree = openingTree(bookIndex)
    #expect(OPENING_LIST.count == Set(OPENING_LIST.map(\.id)).count)
    for opening in OPENING_LIST {
      for root in opening.roots {
        #expect(walkSan(root).moves.count == root.count, "\(opening.id) is legal")
        #expect(bookLength(bookIndex, root) == root.count, "\(opening.id) is in the book")
        #expect(movedBy(root.count - 1, opening.color), "\(opening.id) ends on its side's move")
        #expect(deepestNodeAlong(tree, root) != nil)
        let inside = OPENING_LIST.filter { $0.id != opening.id && $0.color == opening.color && $0.holds(root) }
        #expect(inside.isEmpty, "\(opening.id) is inside \(inside.map(\.id))")
      }
    }
  }

  /// Rule 2: you have an opening when a line of your Playbook is in it.
  @Test func yourOpeningsComeFromYourLines() {
    let state = starter()
    #expect(state.ownedFamilies(.w).map(\.id) == ["italian"])
    #expect(state.ownedFamilies(.b).map(\.id) == ["openGame", "qgd"])
  }

  /// Rule 3: the rest are for sale, under your nearest opening on their way, else under their first move.
  @Test func theRestAreForSale() {
    let tree = openingTree(bookIndex)
    let state = starter()
    let white = all(playbookMap(state, tree, side: .w))
    #expect(Set(white.filter(\.forSale).compactMap(\.family)) == Set(openingList(.w).map(\.id)).subtracting(["italian"]))
    let d4 = playbookMap(state, tree, side: .w).first { $0.line == ["d4"] }
    #expect(d4?.state == .way)
    #expect(d4?.children.contains { $0.family == "london" } == true)
    let e4 = playbookMap(state, tree, side: .w).first { $0.line == ["e4"] }
    #expect(e4?.owned == true)
    #expect(all(e4.map { [$0] } ?? []).contains { $0.family == "ruy" && $0.forSale })
  }

  /// Rule 4: 500, then 500 more each; White and Black apart.
  @Test func pricesRise() {
    let tree = openingTree(bookIndex)
    var state = starter()
    state.pawns = 10_000
    #expect(state.families.price(.w) == 500)
    let london = state.buyFamily("london", tree)
    #expect(london && state.pawns == 9_500)
    #expect(state.families.price(.w) == 1_000 && state.families.price(.b) == 500)
    let again = state.buyFamily("london", tree)
    #expect(!again, "an opening is bought once")
    var poor = starter()
    poor.pawns = 499
    let short = poor.buyFamily("london", tree)
    #expect(!short && poor.pawns == 499)
  }

  /// Rule 5: buying adds a seed line from each of its roots.
  @Test func buyingAddsItsLines() {
    let tree = openingTree(bookIndex)
    var state = starter()
    state.pawns = 2_000
    let bought = state.buyFamily("london", tree)
    #expect(bought)
    let rep = state.playbookList.first { $0.color == .w }!
    for root in curatedOpening("london")!.roots {
      #expect(nodeAtLine(rep, familySeed(tree, root, .w, size: MOVES_PER_FILL)) != nil)
    }
    #expect(state.ownsFamily("london"))
  }

  /// Rule 6: one token to start, one more per 3 bought, at most 1; a swap drops the old opening but keeps shared moves.
  @Test func swapTokens() {
    let tree = openingTree(bookIndex)
    var state = starter()
    #expect(state.families.tokens == 1)
    let swapped = state.swapFamily("italian", for: "ruy", tree)
    #expect(swapped && state.ownedFamilies(.w).map(\.id) == ["ruy"] && state.families.tokens == 0)
    let rep = state.playbookList.first { $0.color == .w }!
    #expect(nodeAtLine(rep, line("e4 e5 Nf3 Nc6 Bc4")) == nil)
    #expect(nodeAtLine(rep, line("e4 e5 Nf3 Nc6 Bb5")) != nil, "the moves on the way are kept")
    let none = state.swapFamily("ruy", for: "london", tree)
    #expect(!none, "no token left")
    state.pawns = 100_000
    for id in ["london", "english", "catalan"] { _ = state.buyFamily(id, tree) }
    #expect(state.families.tokens == 1, "the third bought earns one")
    for id in ["french", "caro", "slav"] { _ = state.buyFamily(id, tree) }
    #expect(state.families.tokens == 1, "held at most 1")
  }

  /// Rule 7: the choosing tree offers only what a slot takes, and the picks go in free.
  @Test func choosingFillsThreeSlotsFree() {
    let tree = openingTree(bookIndex)
    #expect(choiceSlot("london") == .w)
    #expect(choiceSlot("najdorf") == .e4)
    #expect(choiceSlot("slav") == .d4)
    #expect(choiceSlot("nope") == nil)
    #expect(choosingMap(tree, slot: .e4).map(\.line) == [["e4"]])
    #expect(choosingMap(tree, slot: .d4).map(\.line) == [["d4"]])
    #expect(choosingMap(tree, slot: .w).allSatisfy { $0.color == .w })
    var state = AppState()
    state.choose(tree, ["london", "najdorf", "slav"])
    #expect(state.settings.onboarded)
    #expect(state.ownedFamilies(.w).map(\.id) == ["london"])
    #expect(state.ownedFamilies(.b).map(\.id) == ["najdorf", "slav"])
    #expect(state.families.bought.isEmpty)
    #expect(state.families.price(.w) == FAMILY_FIRST_PRICE)
  }

  /// Rule 7: the slots fill in order, and a filled one can be opened again to change its pick.
  @Test func choosingFillsSlotsInOrder() {
    var choosing = Choosing()
    #expect(choosing.slot == .w)
    #expect(!choosing.canOpen(.e4), "a later slot waits")
    let early = choosing.pick("najdorf")
    #expect(!early, "only the slot being filled takes a pick")
    let white = choosing.pick("london")
    #expect(white && choosing.slot == .e4)
    let wrong = choosing.pick("slav")
    #expect(!wrong)
    let e4 = choosing.pick("najdorf")
    #expect(e4 && choosing.slot == .d4)
    #expect(choosing.ids == nil)
    choosing.open(.w)
    #expect(choosing.slot == .w)
    let changed = choosing.pick("english")
    #expect(changed && choosing.slot == .d4, "back to the first empty slot")
    let d4 = choosing.pick("slav")
    #expect(d4 && choosing.ids == ["english", "najdorf", "slav"])
  }
}
