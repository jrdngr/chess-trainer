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
  /// A blunder ends the game.
  case blunder
  /// Pawns earned.
  case pawns
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

  /* ── Home ── */
  /// A feature bought: its control on Home.
  case sidePicker, openingPicker

  /* ── the Playbook tab ── */
  /// The tab opened.
  case playbook

  public var text: String {
    switch self {
    case .flashCards: "Your openings are flashcards. Each move is graded on speed and accuracy."
    case .prepBar: "The prep bar fills as you play your line."
    case .prepDone: "A \u{2713} means you\u{2019}re still playing common moves."
    case .missedMove: "Remember this move next time!"
    case .growth: "We\u{2019}ll add new moves to your openings as you get better. Pick an answer or play it on the board."
    case .growthPawn: "You must add at least one move to continue earning pawns for this opening."
    case .blunder: "A blunder ends the game."
    case .pawns: "You earn pawns for various accomplishments. Spend them in the Pawn Shop."
    case .mission: "Complete missions to earn pawns."
    case .nextRun: "Once your prep is done, tap \u{201C}Next run\u{201D} to end early. This can be helpful for drilling openings quickly."
    case .lens: "Tap a lens for hints."
    case .freeformGame: "Freeform lets you play any of your lines from move 1. Your opponent will always stay within your Playbook."
    case .analysis: "The game\u{2019}s over. Step through your moves or try others on the board."
    case .sidePicker: "Choose your side."
    case .openingPicker: "Choose an opening to focus on."
    case .playbook: "Your openings live here as a tree. Tap one to see its branches, and + to add one."
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

  /// Home's tip now: a feature bought, at its control.
  public var homeTip: GameTip? {
    for feature in ShopFeature.allCases where owns(feature) {
      if let tip = GameTip.bought(feature), !settings.seen(tip) { return tip }
    }
    return nil
  }

  /// The Shop tab's badge: how many items you can buy now.
  public var buyableCount: Int { SHOP.filter { status($0) == .buyable }.count }

  /// A profile from before the tips has seen every one.
  public mutating func seeAllTips() {
    settings.seenTips = Set(GameTip.allCases)
  }
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
