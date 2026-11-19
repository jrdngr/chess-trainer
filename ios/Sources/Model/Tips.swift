import Book
import ChessCore

/// Tips: each has one trigger and shows once, the first time its trigger comes
/// while no other tip is up. A tap or the player's next action puts it away.

public enum GameTip: String, Sendable, Codable, CaseIterable {
  /* ── in a game ── */
  /// A Play game starts.
  case flashCards
  /// A prep move played.
  case prepBar
  /// The first ✓ on a common move past your prep.
  case prepDone
  /// A prepared move missed, the right one shown.
  case missedMove
  /// Growth opens.
  case growth
  /// Growth opens because a move is due, holding the Prep complete pawn.
  case growthPawn
  /// A green arrow shows in growth: a move that fits your patterns.
  case greenMove
  /// A red arrow shows in growth: a move that breaks one.
  case redMove
  /// A blunder ends the game.
  case blunder
  /// Pawns earned.
  case pawns
  /// The first distance pawns, out of the bar past your prep.
  case distancePawns
  /// A mission is set.
  case mission
  /// Next run shows, past your prep in a Play game.
  case nextRun
  /// The lenses owned, and the game past your prep.
  case lens
  /// A Freeform game starts.
  case freeformGame
  /// A Play game ends without a blunder, its moves left to look back on.
  case analysis
  /// Pawns paid in a game take the balance to `END_SESSION_TIP_PAWNS` or more.
  case endSession

  /* ── Home ── */
  /// A feature bought: its control on Home.
  case sidePicker, openingPicker
  /// The streak's first day paid: the streak ring on Home.
  case dailyRewards

  public var text: String {
    switch self {
    case .flashCards: "Your openings are flashcards. Each move is graded on speed and accuracy."
    case .prepBar: "The prep bar fills as you play your line."
    case .prepDone: "A \u{2713} means you\u{2019}re still playing common moves."
    case .missedMove: "Remember this move next time!"
    case .growth: "We\u{2019}ll add new moves to your openings as you get better. Pick an answer or play it on the board."
    case .growthPawn: "You must add at least one move to continue earning pawns for this opening."
    case .greenMove: "Green moves fit what you already play. They may not be the engine\u{2019}s top pick, but they keep your Playbook easier to remember."
    case .redMove: "Red moves break a pattern in your Playbook, so they\u{2019}re harder to remember."
    case .blunder: "A blunder ends the game."
    case .pawns: "You earn pawns for various accomplishments. Spend them in the Pawn Shop."
    case .distancePawns: "You earn pawns every 5 moves past your prep."
    case .mission: "Complete missions to earn pawns."
    case .nextRun: "Once your prep is done, tap \u{201C}Next run\u{201D} to end early. This can be helpful for drilling openings quickly."
    case .lens: "Tap a lens for hints."
    case .freeformGame: "Freeform lets you play any of your lines from move 1. Your opponent will always stay within your Playbook."
    case .analysis: "The game\u{2019}s over. Step through your moves or try others on the board."
    case .endSession: "Tap \u{2715} to end the session and spend your pawns in the Pawn Shop."
    case .sidePicker: "Choose your side."
    case .openingPicker: "Choose an opening to focus on."
    case .dailyRewards: "Complete your prep once a day to earn daily rewards."
    }
  }

  /// The Home tip for a feature bought: the side picker's and the opening picker's.
  public static func bought(_ feature: ShopFeature) -> GameTip? {
    switch feature {
    case .sidePicker: .sidePicker
    case .openingPicker: .openingPicker
    default: nil
    }
  }
}

/// Growth's colors, explained the first time each shows: green before red when both do.
public func toneTip(_ tones: [NudgeTone?], seen: (GameTip) -> Bool) -> GameTip? {
  if tones.contains(.toward), !seen(.greenMove) { return .greenMove }
  if tones.contains(.away), !seen(.redMove) { return .redMove }
  return nil
}

/// The balance at which a game points out its close button: enough for the cheapest feature in the Pawn Shop.
public let END_SESSION_TIP_PAWNS = 50

extension Settings {
  public func seen(_ tip: GameTip) -> Bool { seenTips.contains(tip) }

  /// A tip shown: it never shows again.
  public mutating func see(_ tip: GameTip) { seenTips.insert(tip) }
}

extension AppState {
  /// A tip shown: seen for good, and logged.
  public mutating func sawTip(_ tip: GameTip) {
    settings.see(tip)
    logEvent(AppEvent(kind: "tip", picked: tip.rawValue))
  }

  /// Home's tip now: a feature bought, at its control; else, once a streak day has paid, the daily rewards.
  public var homeTip: GameTip? {
    for feature in ShopFeature.allCases where owns(feature) {
      if let tip = GameTip.bought(feature), !settings.seen(tip) { return tip }
    }
    if pawnStreak.days > 0, !settings.seen(.dailyRewards) { return .dailyRewards }
    return nil
  }

  /// The Shop tab's badge: how many items you can buy now.
  public var buyableCount: Int { SHOP.filter { status($0) == .buyable }.count }
}

/// The plies of `played` from `from` on that are common moves: ones the book plays in at least BOOK_SHARE of its games.
public func commonPlies(_ index: ReferenceIndex, _ played: [String], from: Int = 0) -> Set<Int> {
  let fens = walkSan(played).fens
  var out = Set<Int>()
  for ply in played.indices where ply >= from && ply < fens.count - 1 {
    if bookMoves(index, fens[ply]).contains(played[ply]) { out.insert(ply) }
  }
  return out
}

/* ── a first game with nothing saved ── */

/// The first game's round: White, from move one, in no opening yet.
public func firstGameRound(_ tree: OpeningTree) -> AutoRound {
  AutoRound(pick: Recommendation(focus: .test, opening: tree.root, color: .w), at: nil)
}

/// The gap a game with nothing saved for a side starts at: that side's first
/// move, before any reply.
public func firstMoveGap(_ rep: Playbook, _ index: ReferenceIndex) -> Gap {
  let hole = Hole(path: [], fen: START_FEN, san: "", share: 100, games: 0, after: START_FEN, nodeId: nil, reach: 1)
  return Gap(kind: .noAnswer, playbookId: rep.id, color: rep.color, hole: hole, importance: 1, name: "", missing: 1)
}
