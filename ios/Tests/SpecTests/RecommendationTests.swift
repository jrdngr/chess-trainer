import ChessCore
import Foundation
import Model
import Testing

/// The recommendation engine on the real book.

/// Home shows three: the top gap of each kind, then the next most important,
/// with breadth gaps listed first.
@Test func homeShowsEachKind() {
  let tree = openingTree(bookIndex)
  let found = gaps([rep(.w, ["e4 c5 d4 cxd4 c3", "d4 d5 c4"])], bookIndex, tree: tree)
  let top = topGaps(found)
  #expect(top.count == 3)
  #expect(top.contains { $0.kind == .tooShort })
  #expect(top.first?.line == line("d4 Nf6"))
  #expect(top.map(\.kind) == top.map(\.kind).sorted { a, _ in a == .noAnswer })
  // Only depth gaps: all three slots go to them.
  let deep = gaps([rep(.b, ["e4 e5", "d4 d5", "Nf3 d5", "c4 e5"])], bookIndex, tree: tree)
  #expect(topGaps(deep).count == min(3, deep.count))
}

/// The basics come first: with only a White Ruy Lopez, Home's three are
/// Black's answers to 1.e4 and 1.d4, then the top White gap.
@Test func basicsLeadHome() throws {
  let tree = openingTree(bookIndex)
  var state = AppState()
  state.addLine(state.ensurePlaybook(.w), line("e4 e5 Nf3 Nc6 Bb5"), .fixed(.book))
  let top = topGaps(playbookGaps(state, tree))
  #expect(top.map(\.line) == [line("e4"), line("d4"), try #require(gaps(state.playbookList, bookIndex, tree: tree).first).line])
  #expect(top.prefix(2).allSatisfy { $0.color == .b && $0.basic && $0.playbookId == "" })
  // Answering 1.e4 leaves 1.d4 as the only basic.
  state.addLine(state.ensurePlaybook(.b), line("e4 e5"), .fixed(.book))
  #expect(playbookGaps(state, tree).filter(\.basic).map(\.line) == [line("d4")])
}

/// With only Black lines, White's first move leads; a reply kept with no answer is still missing.
@Test func whiteFirstMoveIsABasic() {
  let tree = openingTree(bookIndex)
  var state = AppState()
  let black = rep(.b, ["e4 c5", "d4"])
  state.playbooks[black.id] = black
  state.playbookOrder = [black.id]
  let found = playbookGaps(state, tree)
  #expect(found.filter(\.basic).map(\.line) == [[], line("d4")])
  #expect(found.first?.color == .w)
}

/// More shows ten: five "Too short" when there are five, the rest by importance.
@Test func moreShowsTenWithFiveTooShort() {
  let tree = openingTree(bookIndex)
  var state = AppState()
  for set in STARTER_SETS { state.seed(tree, set) }
  let all = playbookGaps(state, tree)
  let short = all.filter { $0.kind == .tooShort }
  #expect(all.count > 10 && short.count >= 5)
  let more = moreGaps(all)
  #expect(more.count == 10)
  #expect(more.filter { $0.kind == .tooShort }.count >= 5)
  // Every "No answer yet" shown outranks every one left out.
  let shownAnswers = more.filter { $0.kind == .noAnswer }
  let leftAnswers = all.filter { g in g.kind == .noAnswer && !more.contains { $0.id == g.id } }
  #expect(shownAnswers.allSatisfy { a in leftAnswers.allSatisfy { a.importance >= $0.importance } })
  #expect(more.map(\.kind) == more.map(\.kind).sorted { a, _ in a == .noAnswer })
}
