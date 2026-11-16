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
  /// The prep runs out.
  case prepDone
  /// A move past the book gets its score.
  case scores
  /// Growth opens.
  case growth
  /// A blunder ends the game.
  case blunder
  /// Pawns earned.
  case pawns
  /// A mission is set.
  case mission
  /// The board glows for a moment.
  case moment
  /// The lenses owned, and the game past your prep.
  case lens
  /// A Freeform game starts.
  case freeformGame
  /// A Middlegame round reaches the board.
  case middlegameRound
  /// An Endgames round starts.
  case endgamesRound

  /* ── Home ── */
  /// Enough pawns for something in the Pawn Shop: the shop's tab.
  case shop
  /// A feature bought: its control on Home.
  case sidePicker, openingPicker, freeform, recommendations, middlegame, endgames

  /* ── the Playbook tab ── */
  /// The tab opened.
  case playbook

  public var text: String {
    switch self {
    case .flashCards: "Your openings are flashcards. Each prep move is graded on being right and fast."
    case .prepBar: "The prep bar fills as you play your line."
    case .prepDone: "That\u{2019}s your prep. A \u{2713} means you\u{2019}re still playing common moves."
    case .scores: "Past your prep, each move gets a score for how good (or bad) it was."
    case .growth: "Pick an answer or play it on the board. Tap Done to stop adding early."
    case .blunder: "A blunder ends the game. The arrow shows the threat."
    case .pawns: "You earn pawns for good play. Spend them in the Pawn Shop."
    case .mission: "A mission: meet it this game for \(pawnsFor(.mission)) pawns."
    case .moment: "When the board glows, there\u{2019}s a strong move. Find it."
    case .lens: "Tap a lens for hints."
    case .freeformGame: "Play any of your lines. Your opponent follows what you play."
    case .middlegameRound: "Your line plays itself out to the middlegame. Then the game is yours."
    case .endgamesRound: "Win it or hold it: the card says which."
    case .shop: "You have enough pawns for something in the Pawn Shop."
    case .sidePicker: "Pick White or Black here."
    case .openingPicker: "Play Any Opening, or pick one of yours."
    case .freeform: "Freeform plays whole games from move 1. Drill starts where you need practice."
    case .recommendations: "Gaps in your Playbook. Tap one to fill it."
    case .middlegame: "Play on from the middlegame of your lines."
    case .endgames: "Endings from your games, to win or hold."
    case .playbook: "Your openings live here. Tap + to add one, and swipe left on one to delete it."
    }
  }

  /// The Home tip for a feature bought; the lenses have theirs in a game.
  public static func bought(_ feature: ShopFeature) -> GameTip? {
    switch feature {
    case .sidePicker: .sidePicker
    case .lensPawns, .lensPieces, .lensKings, .lensEval: nil
    case .openingPicker: .openingPicker
    case .freeform: .freeform
    case .recommendations: .recommendations
    case .middlegame: .middlegame
    case .endgames: .endgames
    }
  }
}

extension Settings {
  public func seen(_ tip: GameTip) -> Bool { seenTips.contains(tip) }

  /// A tip shown: it never shows again.
  public mutating func see(_ tip: GameTip) { seenTips.insert(tip) }
}

extension AppState {
  /// Home's tip now: a feature bought, at its control, then the Pawn Shop's tab once something there is yours to buy.
  public var homeTip: GameTip? {
    for feature in ShopFeature.allCases where owns(feature) {
      if let tip = GameTip.bought(feature), !settings.seen(tip) { return tip }
    }
    if !settings.seen(.shop), SHOP.contains(where: { status($0) == .buyable }) { return .shop }
    return nil
  }

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
