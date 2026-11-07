import Book
import ChessCore

/// A new player's first game: White, nothing saved, adding moves from move
/// one. Tips explain the game as it goes, each once.

/// The first game's tips, in the order they show.
public enum FirstGameTip: String, Sendable, Codable, CaseIterable {
  /// Adding moves at move one.
  case firstMove
  /// Adding moves after the opponent's first reply.
  case reply
  /// The moves just added, on the prep bar.
  case lineIn
  /// Past your line, still in the book.
  case book
  /// Out of the book.
  case outOfBook
  /// The lenses, once out of the book.
  case lens
  /// The end of the first game.
  case end

  public var text: String {
    switch self {
    case .firstMove: "Pick your first move. It goes in your Playbook."
    case .reply: "Black played a common response. Pick your next move."
    case .lineIn: "Every move is a flash card you get quizzed on while you play a real game."
    case .book: "Book moves played after your saved lines aren\u{2019}t graded."
    case .outOfBook: "Once you\u{2019}re out of the book, the game runs until you blunder."
    case .lens: "Hold a lens for hints."
    case .end: "Once you know your moves, a game will stop where your line ends so you can add more."
    }
  }

  /// Shown during the game, before its end: the goal card waits until these are done.
  public var inGame: Bool { self != .end }
}

/// Where the first game stands, as far as its tips care.
public enum FirstGameMoment: Sendable, Equatable {
  /// Adding moves; `ply` is how many moves have been played.
  case adding(ply: Int)
  /// The moves just added, the game going on.
  case lineIn
  case book
  case outOfBook
  case end
}

/// The tip to show at a moment, if one is still to show there. A tip whose
/// moment the game went past without stopping is dropped, so `pending`
/// loses everything before the one returned.
public func tipAt(_ pending: [FirstGameTip], _ moment: FirstGameMoment) -> (tip: FirstGameTip, rest: [FirstGameTip])? {
  let wanted: FirstGameTip? = switch moment {
  case .adding(let ply): ply == 0 ? .firstMove : .reply
  case .lineIn: .lineIn
  case .book: .book
  case .outOfBook: .outOfBook
  case .end: .end
  }
  guard let wanted, let at = pending.firstIndex(of: wanted) else { return nil }
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
