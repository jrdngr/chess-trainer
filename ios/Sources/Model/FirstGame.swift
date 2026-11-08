import Book
import ChessCore

/// A new player's first game: White, nothing saved, adding moves from move
/// one. Tips explain the game as it goes, each once, then Home's controls,
/// then the Playbook tab's the first time it opens. Skipping the first game
/// skips only its own tips.

/// The first game's tips, in the order they show.
public enum FirstGameTip: String, Sendable, Codable, CaseIterable {
  /// Adding moves at move one.
  case firstMove
  /// Adding moves after the opponent's first reply.
  case reply
  /// Moves added, the game going on: the board takes moves again.
  case keepPlaying
  /// The moves just added, on the prep bar.
  case lineIn
  /// Past your line, still in the book.
  case book
  /// Out of the book.
  case outOfBook
  /// The lenses, once out of the book.
  case lens
  /// After the first game, on Home: the opening row.
  case opening
  /// Home: the Play button.
  case play
  /// Home: the Playbook tab, last.
  case playbookTab
  /// The Playbook tab, the first time it opens: its + button.
  case playbookAdd
  /// The Playbook tab: its more menu.
  case playbookMore
  /// The Playbook tab: an opening's row, once there is one.
  case playbookRow

  public var text: String {
    switch self {
    case .firstMove: "Pick your first move. It goes in your Playbook."
    case .reply: "Black played a common response. Pick your next move."
    case .keepPlaying: "Keep playing moves on the board."
    case .lineIn: "Every move is a flash card you get quizzed on while you play a real game."
    case .book: "Book moves played after your saved lines aren\u{2019}t graded."
    case .outOfBook: "Once you\u{2019}re out of the book, the game runs until you blunder."
    case .lens: "Hold a lens for hints."
    case .opening: "Pick the openings your opponent steers toward."
    case .play: "Play a game until you blunder."
    case .playbookTab: "Your openings live in the Playbook. Know what you want to play? Add it there yourself."
    case .playbookAdd: "Tap + to add openings you already know."
    case .playbookMore: "Import your games."
    case .playbookRow: "Tap an opening to see its lines and grow it."
    }
  }

  /// Shown during the game, before its end: the goal card waits until these are done.
  public var inGame: Bool { !FirstGameTip.home.contains(self) && !FirstGameTip.playbook.contains(self) }

  /// Home's tips, in the order they show after the first game.
  public static let home: [FirstGameTip] = [.opening, .play, .playbookTab]

  /// The Playbook tab's tips, in the order they show.
  public static let playbook: [FirstGameTip] = [.playbookAdd, .playbookMore, .playbookRow]

  /// Every tip after the first game's: a profile that skips the first game still gets these.
  public static let afterFirstGame: [FirstGameTip] = home + playbook

  /// Saved tips, by name. "end" was Home's page on how Play works, now Home's
  /// tips; names this version doesn't know are dropped.
  public static func decoded(_ names: [String]) -> [FirstGameTip] {
    names.flatMap { name in name == "end" ? afterFirstGame : FirstGameTip(rawValue: name).map { [$0] } ?? [] }
  }
}

/// The tips left once the first game ends: Home's and the Playbook tab's, those still to show.
public func tipsAfterFirstGame(_ pending: [FirstGameTip]) -> [FirstGameTip] {
  pending.filter { !$0.inGame }
}

/// Home's tip to show now: the first game is over and Home's tips not all seen.
public func homeTip(_ pending: [FirstGameTip]) -> FirstGameTip? {
  guard !pending.contains(where: \.inGame) else { return nil }
  return pending.first { FirstGameTip.home.contains($0) }
}

/// The Playbook tab's tip to show now, once the first game is over. The
/// opening row's tip waits until there is a row to point at.
public func playbookTip(_ pending: [FirstGameTip], hasRows: Bool) -> FirstGameTip? {
  guard !pending.contains(where: \.inGame) else { return nil }
  return pending.first { FirstGameTip.playbook.contains($0) && ($0 != .playbookRow || hasRows) }
}

/// Where the first game stands, as far as its tips care.
public enum FirstGameMoment: Sendable, Equatable {
  /// Adding moves; `ply` is how many moves have been played.
  case adding(ply: Int)
  /// Moves just added, the game going on, before the prep bar's tip.
  case grown
  /// The moves just added, the game going on.
  case lineIn
  case book
  case outOfBook
}

/// The tip to show at a moment, if one is still to show there. A tip whose
/// moment the game went past without stopping is dropped, so `pending`
/// loses everything before the one returned.
public func tipAt(_ pending: [FirstGameTip], _ moment: FirstGameMoment) -> (tip: FirstGameTip, rest: [FirstGameTip])? {
  let wanted: FirstGameTip = switch moment {
  case .adding(let ply): ply == 0 ? .firstMove : .reply
  case .grown: .keepPlaying
  case .lineIn: .lineIn
  case .book: .book
  case .outOfBook: .outOfBook
  }
  guard let at = pending.firstIndex(of: wanted) else { return nil }
  return (wanted, Array(pending[(at + 1)...]))
}

/// The first game's round: White, from move one, in no opening yet.
public func firstGameRound(_ tree: OpeningTree) -> AutoRound {
  AutoRound(pick: Recommendation(focus: .test, opening: tree.root, color: .w, start: .first), at: nil)
}

/// The gap a game with nothing saved for a side starts at: that side's first
/// move, before any reply.
public func firstMoveGap(_ rep: Repertoire, _ index: ReferenceIndex) -> Gap {
  let hole = Hole(path: [], fen: START_FEN, san: "", share: 100, games: 0, after: START_FEN, nodeId: nil, reach: 1)
  return Gap(kind: .noAnswer, repertoireId: rep.id, color: rep.color, hole: hole, importance: 1, name: "", missing: 1)
}

/// Black's reply to White's first move in the tutorial's first game: the symmetric
/// answer to 1.e4 and 1.d4, so a new player starts in a calm opening. Nil
/// after any other move, and past move one.
public func firstGameReply(_ played: [String]) -> String? {
  switch played {
  case ["e4"]: "e5"
  case ["d4"]: "d5"
  default: nil
  }
}
