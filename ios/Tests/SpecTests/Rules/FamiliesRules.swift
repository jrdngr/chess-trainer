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

  /// Rule 6: Delete can't take an opening you have, only what's past its named position.
  @Test func openingsAreKept() throws {
    let tree = openingTree(bookIndex)
    var state = starter()
    state.addLine(state.playbookList[0].id, line("e4 e5 Nf3 Nc6 Bc4 Bc5 c3 Nf6"), .fixed(.book))
    let way = state.removeNodeAt(.w, line("e4")), named = state.removeNodeAt(.w, line("e4 e5 Nf3 Nc6 Bc4"))
    #expect(way == nil, "not the moves to it")
    #expect(named == nil, "not its named position")
    #expect(state.ownsFamily("italian"))
    let past = state.removeNodeAt(.w, line("e4 e5 Nf3 Nc6 Bc4 Bc5 c3"))
    #expect(past != nil && state.ownsFamily("italian"), "a branch past it goes")
    state.addLine(state.playbookList[0].id, line("d4 d5"), .fixed(.book))
    let outside = state.removeNodeAt(.w, line("d4"))
    #expect(outside != nil, "a line outside every opening goes")
    state.pawns = 500
    _ = state.buyFamily("london", tree)
    #expect(state.families.price(.w) == 1_000)
    let london = state.removeNodeAt(.w, line("d4 Nf6 Bf4"))
    #expect(london == nil, "nor one bought")
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

  /// Rule 8: an opening that's off sits out the automatic picks, still plays when picked itself,
  /// and the last one on in its slot can't be turned off.
  @Test func turningAnOpeningOff() throws {
    let tree = openingTree(bookIndex)
    var state = starter()
    #expect(!state.canTurnOff("italian"), "the only White opening stays on")
    state.pawns = 500
    _ = state.buyFamily("london", tree)
    #expect(state.canTurnOff("italian") && state.canTurnOff("london"))
    #expect(!state.canTurnOff("najdorf"), "only an opening you have")
    let turnedOff = state.setOpening("italian", on: false)
    #expect(turnedOff && state.isOff("italian"))
    #expect(!state.canTurnOff("london"), "London is now the last one on")
    let last = state.setOpening("london", on: false)
    #expect(!last)
    #expect(!state.canTurnOff("qgd"), "Black against 1.d4 is a slot of its own")

    let any = Selection(color: .w, opening: ANY_OPENING)
    let auto = state.forAutoPicks(tree, any)
    #expect(auto.ownedFamilies(.w).map(\.id) == ["london"], "off is cut out of Any Opening")
    #expect(state.ownedFamilies(.w).count == 2, "and kept in the Playbook")
    let italian = try #require(deepestNodeAlong(tree, line("e4 e5 Nf3 Nc6 Bc4")))
    let picked = Selection(color: .w, opening: italian.id)
    #expect(state.forAutoPicks(tree, picked).ownsFamily("italian"), "picked itself, it plays")
    #expect(!curvePlaybookGaps(state, tree).contains { $0.color == .w && $0.line.starts(with: line("e4 e5 Nf3 Nc6 Bc4")) },
      "it grows nothing next")
    let round = try #require(nextRound(state, tree, any, AutoHistory()))
    #expect(round.pick.color == .w && (round.at ?? round.aim ?? []).first != "e4", "Any Opening keeps out of it")
    let node = try #require(all(playbookMap(state, tree, side: .w)).first { $0.family == "italian" })
    #expect(node.off && node.owned)

    let turnedOn = state.setOpening("italian", on: true)
    #expect(turnedOn && !state.isOff("italian"))
    #expect(state.forAutoPicks(tree, any).ownsFamily("italian"))
  }

  /// Rule 9: the picker's first moves are those an opening you have and haven't turned off starts with.
  @Test func pickerFirstMovesAreYours() {
    let tree = openingTree(bookIndex)
    var state = starter()
    #expect(state.heldFirstMoves(.w) == ["e4"])
    #expect(state.heldFirstMoves(.b) == ["e4", "d4"], "as Black, the moves you face")
    state.pawns = 500
    _ = state.buyFamily("london", tree)
    #expect(state.heldFirstMoves(.w) == ["e4", "d4"])
    _ = state.setOpening("italian", on: false)
    #expect(state.heldFirstMoves(.w) == ["d4"], "an opening turned off gives none")
    #expect(state.heldFirstMoves(nil) == ["e4", "d4"], "Either takes both sides")
  }
}
