import Foundation
import Model
import Testing

@Suite("docs/rules/tips.md") struct TipsRules {
  /// Rule 1: a tip shown is seen for good, and a save keeps what has been seen.
  @Test func aTipShowsOnce() throws {
    var settings = Settings()
    #expect(!settings.seen(.prepBar))
    settings.see(.prepBar)
    #expect(settings.seen(.prepBar))
    let saved = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
    #expect(saved.seenTips == [.prepBar])
    let old = try JSONDecoder().decode(Settings.self, from: Data(#"{"seenTips":["prepBar","goHome"],"tips":["lens"]}"#.utf8))
    #expect(old.seenTips == [.prepBar], "names this version doesn't know are dropped")
  }

  /// Rule 3: Home's tip is a bought side or opening picker's, at its control; the Shop tab counts what you can buy.
  @Test func homeShowsBoughtPickersAndTheShopCountsBuyables() {
    var s = AppState()
    #expect(s.homeTip == nil && s.buyableCount == 0, "nothing to buy, nothing bought")
    s.pawns = 20
    #expect(s.homeTip == nil, "no tip for the Shop")
    #expect(s.buyableCount == 2, "the side picker and the Pawns lens")
    let bought = s.buy("sidePicker")
    #expect(bought && s.homeTip == .sidePicker)
    #expect(s.buyableCount == 0, "10 pawns left buy nothing")
    s.settings.see(.sidePicker)
    s.pawns = 20
    _ = s.buy("lensPawns")
    #expect(s.homeTip == nil, "the lenses have their tip in a game")
  }

  /// Rule 4: a profile from before the tips has seen them all.
  @Test func oldProfilesHaveSeenEveryTip() throws {
    #expect(AppState().settings.seenTips.isEmpty)
    var old = try decodeSave(Data(#"{"version":4}"#.utf8))
    old.migrate(bookIndex)
    #expect(GameTip.allCases.allSatisfy(old.settings.seen))
  }
}
