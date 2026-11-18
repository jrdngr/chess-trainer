import ChessCore
import Foundation
import Model
import Testing

@Suite("docs/rules/dev-tools.md") struct DevToolsRules {
  /// Rule 2: owning an item owns what it needs; taking it away takes what needs it; Endgames follows.
  @Test func shopItemsComeWithWhatTheyNeed() {
    var s = AppState()
    s.devSetOwned("freeform", true)
    #expect(s.unlocked == ["sidePicker", "openingPicker", "freeform"])
    s.devSetOwned("sidePicker", false)
    #expect(s.unlocked.isEmpty)

    s.devSetOwned("endgamesRook", true)
    #expect(s.owns(.endgames))
    #expect(Set(s.endgames.entries.map(\.family)) == ["mates", "rook"])
    s.devSetOwned("endgamesRook", false)
    #expect(Set(s.endgames.entries.map(\.family)) == ["mates"])

    s.devSetAllOwned(true)
    #expect(s.unlocked == Set(ShopFeature.allCases.map(\.rawValue)))
    s.devSetAllOwned(false)
    #expect(s.unlocked.isEmpty)
  }

  /// Rule 3: the balance never goes below 0.
  @Test func pawnsStopAtZero() {
    var s = AppState()
    s.devAddPawns(1_000)
    s.devAddPawns(-5_000)
    #expect(s.pawns == 0)
  }

  /// Rule 4: openings go in and out free, without moving the ladder; out takes their moves and form.
  @Test func openingsInAndOutAreFree() throws {
    let tree = openingTree(bookIndex)
    var s = AppState()
    s.recommend(tree)
    let price = s.families.price(.w)
    let added = s.devSetOpening("london", owned: true, tree)
    #expect(added && s.ownsFamily("london"))
    #expect(s.pawns == 0 && s.families.price(.w) == price)

    s.form.openings["d4 d5 Bf4"] = [1, 1, 1, 1, 1]
    let dropped = s.devSetOpening("london", owned: false, tree)
    #expect(dropped && !s.ownsFamily("london"))
    #expect(s.form.openings["d4 d5 Bf4"] == nil)
    #expect(s.ownsFamily("italian"), "the other openings stay")
    #expect(s.families.price(.w) == price)

    s.devSetTokens(5)
    #expect(s.families.tokens == MAX_SWAP_TOKENS)
    s.devSetTokens(-1)
    #expect(s.families.tokens == 0)
  }

  /// Rule 5: an unseen tip shows again at its trigger.
  @Test func anUnseenTipShowsAgain() {
    var s = AppState()
    s.devSetOwned("sidePicker", true)
    s.sawTip(.sidePicker)
    #expect(s.homeTip == nil)
    s.devSetTip(.sidePicker, seen: false)
    #expect(s.homeTip == .sidePicker)
    s.devSetAllTips(seen: true)
    #expect(s.homeTip == nil && s.settings.seenTips == Set(GameTip.allCases))
  }

  /// Rule 6: the next game goes on from a streak set by hand: freezes cover missed days, and a
  /// repair is offered for yesterday.
  @Test func theStreakGoesOnFromWhereItWasSet() {
    let now = 1_790_845_200_000.0
    var s = AppState()
    s.devSetStreak(days: 5, freezes: 0, lastPlayed: 2, now: now)
    #expect(s.pawnStreak.day == daysBefore(now)[1])
    #expect(repairOffered(s.pawnStreak, today: dayKey(now), past: daysBefore(now)))

    s.devSetStreak(days: 5, freezes: 1, lastPlayed: 2, now: now)
    let paid = s.finishedGame(now: now)
    #expect(s.pawnStreak.days == 7 && s.pawnStreak.freezes == 0)
    #expect(paid == streakPawns(7))

    s.devSetStreak(days: 0, freezes: 2, lastPlayed: 0, now: now)
    #expect(s.pawnStreak == PawnStreak(freezes: 2))
  }

  /// Rule 7: games added count toward the level gates, and form set green opens them.
  @Test func growthGatesCountWhatIsSet() {
    let tree = openingTree(bookIndex)
    var s = AppState()
    s.recommend(tree)
    let owned = ownedOpenings(curveSides(s), tree)
    #expect(!owned.isEmpty)
    s.devAddPlayGames(40)
    for o in owned { s.devSetForm(o.node.id, o.color, .green) }
    let gate = curveGate(s, tree)
    #expect(gate.games == 40 && gate.allGreen && gate.met(1))

    s.devSetForm(owned[0].node.id, owned[0].color, .red)
    #expect(!curveGate(s, tree).allGreen)
    s.devSetForm(owned[0].node.id, owned[0].color, .none)
    #expect(s.form.scores(owned[0].node.id, owned[0].color).isEmpty)
  }
}
