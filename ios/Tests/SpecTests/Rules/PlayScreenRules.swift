import Model
import Testing

@Suite("docs/rules/play-screen.md") struct PlayScreenRules {
  /// Rule 3: the header puts the opening's family on a line over a deeper name, and nothing over a name that is its own family.
  @Test func headerShowsFamilyOverDeeperName() {
    #expect(familyAbove(bookIndex, "Sicilian Defence: Najdorf Variation") == "Sicilian Defence")
    #expect(familyAbove(bookIndex, "Queen's Gambit Declined: Exchange Variation") == "Queen's Gambit Declined")
    #expect(familyAbove(bookIndex, "Sicilian Defence") == nil)
    #expect(familyAbove(bookIndex, "Freeform") == nil)
  }
}
