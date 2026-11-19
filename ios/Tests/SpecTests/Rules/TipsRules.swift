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

  /// Rule 2: growth's green is explained the first time it is drawn, red the first time
  /// after that; a color already explained, or never drawn, gets no tip.
  @Test func greenThenRedExplained() {
    var settings = Settings()
    let both: [NudgeTone?] = [nil, .away, .toward]
    #expect(toneTip([nil, .towardFar], seen: settings.seen) == nil, "yellow alone has no tip")
    #expect(toneTip(both, seen: settings.seen) == .greenMove, "green first when both are drawn")
    settings.see(.greenMove)
    #expect(toneTip([.toward], seen: settings.seen) == nil)
    #expect(toneTip(both, seen: settings.seen) == .redMove)
    settings.see(.redMove)
    #expect(toneTip(both, seen: settings.seen) == nil)
  }

  /// Rule 3: Home's tip is a bought side or opening picker's, at its control; the Shop tab counts what you can buy.
  @Test func homeShowsBoughtPickersAndTheShopCountsBuyables() {
    var s = AppState()
    #expect(s.homeTip == nil && s.buyableCount == 0, "nothing to buy, nothing bought")
    s.pawns = 120
    #expect(s.homeTip == nil, "no tip for the Shop")
    #expect(s.buyableCount == 2, "the side picker and the Pawns lens")
    let bought = s.buy("sidePicker")
    #expect(bought && s.homeTip == .sidePicker)
    #expect(s.buyableCount == 0, "70 pawns left buy nothing")
    s.settings.see(.sidePicker)
    s.pawns = 300
    _ = s.buy("lensPawns")
    #expect(s.homeTip == nil, "the lenses have their tip in a game")
  }

  /// Rule 3: once a streak day has paid, Home explains daily rewards at the streak ring, after any bought picker's tip.
  @Test func homeExplainsDailyRewardsOnceAStreakDayPays() {
    var s = AppState()
    s.pawns = 120
    _ = s.buy("sidePicker")
    s.pawnStreak.days = 1
    #expect(s.homeTip == .sidePicker, "a bought picker's tip first")
    s.settings.see(.sidePicker)
    #expect(s.homeTip == .dailyRewards)
    s.settings.see(.dailyRewards)
    #expect(s.homeTip == nil)
    var fresh = AppState()
    fresh.pawnStreak.days = 0
    #expect(fresh.homeTip == nil, "no streak paid yet")
  }
}
