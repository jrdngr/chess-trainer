import ChessCore
import Foundation
import Model
import Testing

/// A White Italian and Black answers to 1.e4 and 1.d4.
private func starter() -> AppState {
  var state = AppState()
  let w = state.ensurePlaybook(.w), b = state.ensurePlaybook(.b)
  state.addLine(w, line("e4 e5 Nf3 Nc6 Bc4"), .fixed(.book))
  state.addLine(b, line("e4 e5 Nf3 Nc6"), .fixed(.book))
  state.addLine(b, line("d4 d5 c4 e6"), .fixed(.book))
  return state
}

@Suite("docs/rules/families.md") struct FamiliesRules {
  /// Rule 1.
  @Test func aFamilyIsTheFirstMoveThatIsYours() {
    #expect(familyLine(line("e4 c5 Nf3"), .w) == ["e4"])
    #expect(familyLine(line("e4 c5 Nf3"), .b) == ["e4", "c5"])
    #expect(familyLine(line("e4"), .b) == nil)
  }

  /// Rule 2.
  @Test func yourFamiliesComeFromYourLines() {
    let state = starter()
    #expect(state.ownedFamilies(.w) == [["e4"]])
    #expect(Set(state.ownedFamilies(.b)) == [["e4", "e5"], ["d4", "d5"]])
  }

  /// Rule 3: common first moves for White, common answers under them for Black, yours left out.
  @Test func theRestAreForSale() {
    let tree = openingTree(bookIndex)
    let state = starter()
    let white = playbookMap(state, tree, side: .w)
    #expect(white.contains { $0.family == ["d4"] && $0.forSale })
    #expect(!white.contains { $0.family == ["e4"] && $0.forSale })
    let black = playbookMap(state, tree, side: .b)
    let e4 = black.first { $0.line == ["e4"] }
    #expect(e4?.owned == true)
    #expect(e4?.children.contains { $0.family == ["e4", "c5"] && $0.forSale } == true)
    // No answer to 1.c4 yet: it shows as the way to its answers.
    let c4 = black.first { $0.line == ["c4"] }
    #expect(c4?.state == .way && c4?.children.allSatisfy { $0.forSale } == true)
    #expect(familyChoices(bookIndex, .w).allSatisfy { $0.count == 1 })
  }

  /// Rule 4: 2,000, then 500 more each; White and Black apart.
  @Test func pricesRise() {
    let tree = openingTree(bookIndex)
    var state = starter()
    state.pawns = 10_000
    #expect(state.families.price(.w) == 2_000)
    let d4 = state.buyFamily(["d4"], .w, tree)
    #expect(d4 && state.pawns == 8_000)
    #expect(state.families.price(.w) == 2_500 && state.families.price(.b) == 2_000)
    let again = state.buyFamily(["d4"], .w, tree)
    #expect(!again, "a family is bought once")
    var poor = starter()
    poor.pawns = 1_999
    let short = poor.buyFamily(["d4"], .w, tree)
    #expect(!short && poor.pawns == 1_999)
  }

  /// Rule 5: the family's line, one fill of your moves.
  @Test func buyingAddsTheFamilysLine() {
    let tree = openingTree(bookIndex)
    let seed = familySeed(tree, ["e4", "c5"], .b, size: 3)
    #expect(seed.starts(with: ["e4", "c5"]))
    #expect(seed.enumerated().filter { $0.offset % 2 == 1 }.count <= 3, "at most 3 of your moves")
    var state = starter()
    state.pawns = 2_000
    _ = state.buyFamily(["e4", "c5"], .b, tree)
    #expect(nodeAtLine(state.playbookList.first { $0.color == .b }!, seed) != nil)
  }

  /// Rule 6: one token to start, one more per 3 bought, at most 1; a swap drops the old family.
  @Test func swapTokens() {
    let tree = openingTree(bookIndex)
    var state = starter()
    #expect(state.families.tokens == 1)
    let swapped = state.swapFamily(["e4"], for: ["d4"], .w, tree)
    #expect(swapped && state.ownedFamilies(.w) == [["d4"]] && state.families.tokens == 0)
    let none = state.swapFamily(["d4"], for: ["c4"], .w, tree)
    #expect(!none, "no token left")
    state.pawns = 100_000
    for family in [["e4"], ["c4"], ["Nf3"]] { _ = state.buyFamily(family, .w, tree) }
    #expect(state.families.tokens == 1, "the third family bought earns one")
    for family in [["e4", "c5"], ["e4", "e6"], ["e4", "c6"]] { _ = state.buyFamily(family, .b, tree) }
    #expect(state.families.tokens == 1, "held at most 1")
  }
}
