import ChessCore

/// Setups: plans that are several moves, with names players use.
/// `src/model/setups.ts`.
///
/// A habit is one exact move, but g3 means a fianchetto, and so does Bg2. Like
/// the kin sets, this is chess knowledge written down. Moves every opening
/// plays (Nf3, d4, O-O) are in no setup. Moves are written as `sameMove`
/// writes them: no check or capture marks.
public struct Setup: Equatable, Sendable {
  public var id: String
  public var color: Color
  /// How a reason says you use it: "You fianchetto in 3 Slav lines".
  public var doing: String
  /// Every move of the setup.
  public var moves: [String]
  /// The moves a line has to play to be using the setup.
  public var core: [String]
  /// The moves that make it this setup rather than a common move: e3 is the London only beside Bf4.
  public var sign: [String]
}

public let SETUPS: [Setup] = [
  Setup(id: "w-kingside-fianchetto", color: .w, doing: "fianchetto", moves: ["g3", "Bg2"], core: ["g3"], sign: ["g3"]),
  Setup(id: "w-queenside-fianchetto", color: .w, doing: "fianchetto queenside", moves: ["b3", "Bb2"], core: ["b3"], sign: ["b3"]),
  Setup(id: "w-london", color: .w, doing: "play the London setup", moves: ["Bf4", "e3", "c3"], core: ["Bf4", "e3"], sign: ["Bf4"]),
  Setup(id: "w-colle", color: .w, doing: "play the Colle setup", moves: ["e3", "Bd3", "c3"], core: ["e3", "Bd3", "c3"], sign: ["c3"]),
  Setup(id: "w-stonewall", color: .w, doing: "play the Stonewall", moves: ["f4", "e3", "c3"], core: ["f4", "e3"], sign: ["f4"]),
  Setup(id: "w-kia", color: .w, doing: "play the King's Indian Attack", moves: ["g3", "Bg2", "d3"], core: ["g3", "d3"], sign: ["g3", "d3"]),

  Setup(id: "b-kingside-fianchetto", color: .b, doing: "fianchetto", moves: ["g6", "Bg7"], core: ["g6"], sign: ["g6"]),
  Setup(id: "b-queenside-fianchetto", color: .b, doing: "fianchetto queenside", moves: ["b6", "Bb7"], core: ["b6"], sign: ["b6"]),
  Setup(id: "b-kid", color: .b, doing: "play the King's Indian setup", moves: ["g6", "Bg7", "d6"], core: ["g6", "d6"], sign: ["g6", "d6"]),
  Setup(id: "b-stonewall", color: .b, doing: "play the Stonewall", moves: ["f5", "e6", "d5", "c6"], core: ["f5", "e6", "d5"], sign: ["f5"]),
  Setup(id: "b-slav", color: .b, doing: "play the Slav setup", moves: ["c6", "d5", "Bf5"], core: ["c6", "d5", "Bf5"], sign: ["c6", "d5"]),
  Setup(id: "b-hedgehog", color: .b, doing: "play the Hedgehog", moves: ["b6", "Bb7", "e6", "d6", "a6"], core: ["b6", "e6", "d6"], sign: ["b6", "d6"]),
]

/// Whether a line with these moves of yours (as `sameMove` writes them) is using a setup.
public func usesSetup(_ setup: Setup, _ moves: Set<String>) -> Bool {
  setup.core.allSatisfy { moves.contains($0) }
}

/// Whether a move of the setup, added to these, counts toward it: the line has its sign.
public func signsSetup(_ setup: Setup, _ moves: Set<String>, _ move: String) -> Bool {
  setup.moves.contains(move) && setup.sign.allSatisfy { $0 == move || moves.contains($0) }
}

/// The setups a move (as `sameMove` writes it) belongs to, for a side.
public func setupsWith(_ color: Color, _ move: String) -> [Setup] {
  SETUPS.filter { $0.color == color && $0.moves.contains(move) }
}

public func setupsFor(_ color: Color) -> [Setup] {
  SETUPS.filter { $0.color == color }
}
