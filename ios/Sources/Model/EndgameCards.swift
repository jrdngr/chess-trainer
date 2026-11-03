import ChessCore

/// The card before an ending: a few pages, each a teaching position with
/// marked squares and a caption, and on some pages a short line to step
/// through. The Plan lens reads the same pages to name the step a live game is on.

/// What a marked square means on a card.
public enum CardTone: String, Sendable, CaseIterable {
  /// A line a piece holds: the rook's rank, the queen's lines, the bishops' wall.
  case line
  /// The squares the defending king is shut in.
  case box
  /// Squares to reach: key squares, the square a pawn queens behind.
  case key
  /// A pawn's square, for the race.
  case zone
  /// The square or king the page is about.
  case focus
  /// The rank the rook builds the bridge on.
  case bridge
}

public struct CardMark: Equatable, Sendable {
  public var tone: CardTone
  public var squares: [String]
}

public struct CardLegend: Equatable, Sendable {
  public var tone: CardTone
  public var label: String
}

/// One move in a page's line. Its marks are added to the page's once it is played.
public struct CardStep: Equatable, Sendable {
  public var from: String
  public var to: String
  public var caption: String
  public var marks: [CardMark]
  public var promotion: PieceType?
}

public struct CardPage: Equatable, Sendable {
  public var title: String
  public var fen: String
  public var caption: String
  public var marks: [CardMark]
  public var legend: [CardLegend]
  public var steps: [CardStep]
}

/// The card shown before every round of an ending, and on asking.
public struct EndgameIntro: Equatable, Sendable {
  /// The side the card is seen from: the one meant to win, or the one holding the draw.
  public var side: Color
  public var pages: [CardPage]
}

public extension CardPage {
  /// The position after the first `played` steps, and the squares marked by then, by tone.
  func after(_ played: Int) -> (fen: String, marks: [String: CardTone], last: (from: String, to: String)?) {
    var fen = self.fen
    var marks: [String: CardTone] = [:]
    for mark in self.marks { for square in mark.squares { marks[square] = mark.tone } }
    var last: (from: String, to: String)?
    for step in steps.prefix(played) {
      guard let move = applyMove(fen, from: step.from, to: step.to, promotion: step.promotion) else { break }
      fen = move.after
      last = (step.from, step.to)
      for mark in step.marks { for square in mark.squares { marks[square] = mark.tone } }
    }
    return (fen, marks, last)
  }
}

/* ── building the cards ── */

private let FILES = Array("abcdefgh")

/// Every square from file `f1` to `f2` and rank `r1` to `r2`.
private func span(_ f1: Character, _ f2: Character, _ r1: Int, _ r2: Int) -> [String] {
  let a = FILES.firstIndex(of: f1)!, b = FILES.firstIndex(of: f2)!
  return (r1...r2).flatMap { r in (a...b).map { "\(FILES[$0])\(r)" } }
}
private func rowOf(_ r: Int, _ f1: Character = "a", _ f2: Character = "h") -> [String] { span(f1, f2, r, r) }
private func fileOf(_ f: Character, _ r1: Int = 1, _ r2: Int = 8) -> [String] { span(f, f, r1, r2) }

private func join(_ parts: [String]...) -> [String] { parts.flatMap { $0 } }
private func mark(_ tone: CardTone, _ squares: [String]) -> CardMark { CardMark(tone: tone, squares: squares) }
private func legend(_ tone: CardTone, _ label: String) -> CardLegend { CardLegend(tone: tone, label: label) }
private func step(_ from: String, _ to: String, _ caption: String, _ marks: [CardMark] = [], promotion: PieceType? = nil) -> CardStep {
  CardStep(from: from, to: to, caption: caption, marks: marks, promotion: promotion)
}
/// A page; `fen` is the placement and the side to move.
private func page(
  _ title: String, _ fen: String, _ caption: String, marks: [CardMark] = [], legend: [CardLegend] = [], steps: [CardStep] = []
) -> CardPage {
  CardPage(title: title, fen: "\(fen) - - 0 1", caption: caption, marks: marks, legend: legend, steps: steps)
}

let QUEEN_MATE_CARD = EndgameIntro(side: .w, pages: [
  page("Box the king in", "8/8/8/4k3/8/3Q4/8/2K5 b",
       "Put your queen a knight\u{2019}s move from their king. Its lines wall the king in.",
       marks: [mark(.line, join(fileOf("d", 4, 8), ["d1", "d2"], rowOf(3, "a", "c"), rowOf(3, "e", "h"),
                                ["e4", "f5", "g6", "h7", "c4", "b5", "a6", "e2", "f1", "c2", "b1"]))],
       legend: [legend(.line, "Squares the queen takes")]),
  page("Shrink the box", "8/8/8/4k3/8/3Q4/8/2K5 b",
       "Each time their king moves, step the queen to stay a knight\u{2019}s move away. The box gets smaller every time.",
       steps: [
         step("e5", "f6", "\u{2026}Kf6"),
         step("d3", "e4", "Qe4. A knight\u{2019}s move away again.", [mark(.focus, ["e4", "f6"])]),
         step("f6", "f7", "\u{2026}Kf7"),
         step("e4", "e5", "Qe5. The king is pushed toward the corner.", [mark(.focus, ["e5", "f7"])]),
         step("f7", "g6", "\u{2026}Kg6"),
         step("e5", "f4", "Qf4. Their king is boxed into the g and h files.", [mark(.box, span("g", "h", 5, 8))]),
       ]),
  page("Bring your king", "7k/8/8/4K1Q1/8/8/8/8 b",
       "Their king has two squares left. Stop moving the queen and walk your king up.",
       marks: [mark(.focus, ["h7", "h8"])], legend: [legend(.focus, "Their last two squares")],
       steps: [
         step("h8", "h7", "\u{2026}Kh7"),
         step("e5", "f6", "Kf6. Your king comes up."),
         step("h7", "h8", "\u{2026}Kh8"),
         step("f6", "f7", "Kf7. Now the queen can land next to their king."),
         step("h8", "h7", "\u{2026}Kh7"),
         step("g5", "g7", "Qg7#. Your king protects the queen."),
       ]),
  page("Watch for stalemate", "7k/5Q2/8/3K4/8/8/8/8 b",
       "Their king can\u{2019}t move here and isn\u{2019}t in check, so the game is a draw. Before every queen move, check they still have a square.",
       marks: [mark(.line, ["g8", "g7", "h7"])]),
])

let ROOK_MATE_CARD = EndgameIntro(side: .w, pages: [
  page("Shrink the box", "8/8/8/3k4/R7/3K4/8/8 w",
       "Your rook walls their king into a box. Your king pushes it back a rank at a time until it\u{2019}s mated on the edge.",
       marks: [mark(.box, span("a", "h", 5, 8)), mark(.line, rowOf(4, "b", "h"))],
       legend: [legend(.line, "Rook\u{2019}s line"), legend(.box, "Their box")]),
  page("Cut it off", "8/8/8/4k3/8/8/8/3K3R w",
       "Put the rook on a line between the two kings. If their king attacks it, slide it to the far end of the same line.",
       steps: [step("h1", "h4", "Rh4. Their king can\u{2019}t cross the 4th rank now.", [mark(.line, rowOf(4, "a", "g"))])]),
  page("Check when the kings face", "8/8/8/3k4/R7/3K4/8/8 w",
       "The kings face each other with one square between. That\u{2019}s the moment to check.",
       marks: [mark(.focus, ["d4"])],
       steps: [
         step("a4", "a5", "Ra5+. Their king can\u{2019}t stay on the 5th rank."),
         step("d5", "e6", "\u{2026}Ke6. It has to step back to the 6th."),
         step("d3", "e4", "Ke4. Follow with your king and look for the next face-off."),
       ]),
  page("The waiting move", "8/8/4k3/R7/3K4/8/8/8 w",
       "Their king sits a knight\u{2019}s move away and won\u{2019}t face yours. Pass the move with the rook, keeping the 5th rank.",
       marks: [mark(.focus, ["e6", "d4"])],
       steps: [
         step("a5", "h5", "Rh5. Same rank, so the box stays shut. They have to move."),
         step("e6", "d6", "\u{2026}Kd6 walks into the face-off.", [mark(.focus, ["d5"])]),
         step("h5", "h6", "Rh6+. The box is down to two ranks."),
       ]),
  page("Mate on the edge", "3k4/8/3K4/8/8/8/8/R7 w",
       "Their king is on the edge, facing yours. The rook check along the edge is mate.",
       marks: [mark(.focus, ["d7"])],
       steps: [step("a1", "a8", "Ra8#. Your king covers c7, d7 and e7. The rook covers the 8th rank.",
                    [mark(.line, ["b8", "c8", "e8", "f8", "g8", "h8"])])]),
])

let BISHOPS_MATE_CARD = EndgameIntro(side: .w, pages: [
  page("Bishops side by side", "8/8/7k/8/3BB3/3K4/8/8 w",
       "Two bishops next to each other make a wall their king can\u{2019}t cross.",
       marks: [mark(.line, ["e5", "f6", "g7", "h8", "f5", "g6", "h7"])], legend: [legend(.line, "The bishops\u{2019} wall")]),
  page("Bring your king up", "8/8/7k/8/3BB3/3K4/8/8 w",
       "Walk your king up beside the bishops. It guards them and takes the squares they leave open.",
       marks: [mark(.focus, ["h4", "h5", "h6"])],
       steps: [
         step("d3", "e3", "Ke3"),
         step("h6", "h5", "\u{2026}Kh5"),
         step("e3", "f4", "Kf4. Their king is stuck on the edge.", [mark(.line, ["g5", "g4"])]),
       ]),
  page("Mate in the corner", "7k/8/4B1K1/8/5B2/8/8/8 w",
       "Drive their king into a corner. One bishop covers the escape square, and the other gives check along the long diagonal.",
       marks: [mark(.line, ["g8", "g7", "h7"])],
       steps: [step("f4", "e5", "Be5#. The light bishop covers g8. Your king covers g7 and h7.", [mark(.line, ["f6", "g7"])])]),
  page("Watch for stalemate", "7k/8/4B1K1/8/5B2/8/8/8 b",
       "The same position with them to move is stalemate. Leave their king a square until the move that mates.",
       marks: [mark(.line, ["g8", "g7", "h7"])]),
])

let KEY_SQUARES_WIN_CARD = EndgameIntro(side: .w, pages: [
  page("Reach a key square", "4k3/8/8/8/4P3/4K3/8/8 w",
       "If your king reaches one of these squares, the pawn queens whatever they do. For a pawn on the 2nd to 4th rank they are the three squares two in front.",
       marks: [mark(.key, ["d6", "e6", "f6"])], legend: [legend(.key, "Key squares")]),
  page("Further up the board", "4k3/8/8/4P3/8/4K3/8/8 w",
       "From the 5th rank on, the squares one in front count too. A rook pawn only has the two squares beside its corner, and is usually a draw.",
       marks: [mark(.key, ["d6", "e6", "f6", "d7", "e7", "f7"])], legend: [legend(.key, "Key squares")]),
  page("Lead with the king", "4k3/8/8/4K3/4P3/8/8/8 w",
       "Walk your king in front of the pawn, not behind it, and step onto a key square.",
       marks: [mark(.key, ["d6", "e6", "f6"])],
       steps: [
         step("e5", "d6", "Kd6. On a key square. The pawn will queen.", [mark(.focus, ["d6"])]),
         step("e8", "d8", "\u{2026}Kd8"),
         step("e4", "e5", "e5. Now push, keeping your king in front of the pawn or beside it."),
       ]),
])

let KEY_SQUARES_HOLD_CARD = EndgameIntro(side: .b, pages: [
  page("Keep them off the key squares", "8/8/4k3/8/4K3/4P3/8/8 w",
       "Their pawn queens if their king reaches one of these squares. Stand where you guard them.",
       marks: [mark(.line, ["d5", "e5", "f5"]), mark(.key, ["e6"])],
       legend: [legend(.line, "Their key squares"), legend(.key, "Your king")]),
  page("Step back straight", "8/4k3/4P3/3K4/8/8/8/8 w",
       "When you have to give ground, step straight back toward the queening square, never to the side.",
       marks: [mark(.key, ["e8"])],
       steps: [step("d5", "e5", "Ke5"), step("e7", "e8", "\u{2026}Ke8. Straight back, still in front of the pawn.")]),
  page("The back rank trick", "4k3/8/4P3/4K3/8/8/8/8 w",
       "When the pawn checks you from your 2nd rank, step onto the square in front of it.",
       steps: [
         step("e5", "f6", "Kf6"),
         step("e8", "f8", "\u{2026}Kf8. Face their king."),
         step("e6", "e7", "e7+"),
         step("f8", "e8", "\u{2026}Ke8. In front of the pawn."),
         step("f6", "e6", "Ke6 protects the pawn, and it\u{2019}s stalemate.", [mark(.line, ["d7", "d8", "f7", "f8"])]),
       ]),
])

let OPPOSITION_WIN_CARD = EndgameIntro(side: .w, pages: [
  page("Take the opposition", "8/8/4k3/8/4K3/8/4P3/8 b",
       "The kings face each other with one square between, and it\u{2019}s their move. They have to give way.",
       marks: [mark(.focus, ["e5"])]),
  page("Walk past", "8/8/4k3/8/4K3/8/4P3/8 b",
       "When their king steps aside, step forward on the other side.",
       steps: [
         step("e6", "d6", "\u{2026}Kd6 steps aside."),
         step("e4", "f5", "Kf5. Your king is through, and the pawn will queen.", [mark(.key, ["f5"])]),
       ]),
  page("Spare tempo", "8/8/4k3/8/4K3/8/4P3/8 w",
       "If it\u{2019}s your move with the kings facing, a pawn step passes the move back. Only do this while the pawn is well behind your king.",
       steps: [step("e2", "e3", "e3. Now it\u{2019}s their move, and they have to give way.", [mark(.focus, ["e5"])])]),
])

let OPPOSITION_HOLD_CARD = EndgameIntro(side: .b, pages: [
  page("Take the opposition", "8/3k4/8/3K4/3P4/8/8/8 w",
       "Stand in front of their pawn, facing their king with one square between. With them to move, they can\u{2019}t get past.",
       marks: [mark(.focus, ["d6"])]),
  page("Face them, then step back", "8/3k4/8/3K4/3P4/8/8/8 w",
       "Follow their king sideways to keep facing it. When the pawn steps up, step straight back.",
       steps: [
         step("d5", "e5", "Ke5"),
         step("d7", "e7", "\u{2026}Ke7. Facing again."),
         step("d4", "d5", "d5"),
         step("e7", "d7", "\u{2026}Kd7. Back in front of the pawn."),
         step("d5", "d6", "d6"),
         step("d7", "d8", "\u{2026}Kd8. Straight back."),
       ]),
  page("Stalemate on the back rank", "3k4/8/3P4/4K3/8/8/8/8 w",
       "On your back rank, keep facing their king. When the pawn checks you, step in front of it.",
       steps: [
         step("e5", "e6", "Ke6"),
         step("d8", "e8", "\u{2026}Ke8. Facing again."),
         step("d6", "d7", "d7+"),
         step("e8", "d8", "\u{2026}Kd8. In front of the pawn."),
         step("e6", "d6", "Kd6 protects the pawn, and it\u{2019}s stalemate.", [mark(.line, ["c7", "c8", "e7", "e8"])]),
       ]),
])

let SQUARE_WIN_CARD = EndgameIntro(side: .w, pages: [
  page("Outrun the king", "8/8/8/7k/1P6/8/8/1K6 w",
       "Picture a square from your pawn to its queening rank. Their king is outside it, so it can\u{2019}t catch the pawn.",
       marks: [mark(.zone, span("b", "f", 4, 8))], legend: [legend(.zone, "The pawn\u{2019}s square")]),
  page("Count it", "8/8/7k/8/8/8/1P6/K7 w",
       "A pawn on its starting rank can step two, so draw its square from one rank further up.",
       marks: [mark(.zone, span("b", "g", 3, 8))]),
  page("Run", "8/8/8/7k/1P6/8/8/1K6 w",
       "Push every move. The square shrinks with each step, and their king never gets in.",
       steps: [
         step("b4", "b5", "b5", [mark(.zone, span("b", "e", 5, 8))]),
         step("h5", "g6", "\u{2026}Kg6"),
         step("b5", "b6", "b6", [mark(.zone, span("b", "d", 6, 8))]),
         step("g6", "f7", "\u{2026}Kf7"),
         step("b6", "b7", "b7"),
         step("f7", "e7", "\u{2026}Ke7"),
         step("b7", "b8", "b8=Q. Too late for their king.", promotion: .q),
       ]),
])

let SQUARE_HOLD_CARD = EndgameIntro(side: .b, pages: [
  page("Step into the square", "8/8/8/6k1/1P6/8/8/K7 b",
       "Picture a square from their pawn to its queening rank. If your king can step into it, the pawn is caught.",
       marks: [mark(.zone, span("b", "f", 4, 8))], legend: [legend(.zone, "The pawn\u{2019}s square")]),
  page("Count it", "8/8/8/6k1/8/8/1P6/K7 b",
       "A pawn on its starting rank can step two, so draw its square from one rank further up.",
       marks: [mark(.zone, span("b", "g", 3, 8))]),
  page("Head for the path", "8/8/8/6k1/1P6/8/8/K7 b",
       "Move toward where the pawn is going, not toward the pawn. Stay inside the square as it shrinks.",
       steps: [
         step("g5", "f5", "\u{2026}Kf5. Inside the square."),
         step("b4", "b5", "b5"),
         step("f5", "e6", "\u{2026}Ke6"),
         step("b5", "b6", "b6"),
         step("e6", "d7", "\u{2026}Kd7"),
         step("b6", "b7", "b7"),
         step("d7", "c7", "\u{2026}Kc7. The pawn falls.", [mark(.key, ["b7", "b8"])]),
       ]),
])

let LUCENA_CARD = EndgameIntro(side: .w, pages: [
  page("Build a bridge", "3K4/3P1k2/8/8/8/8/r7/4R3 w",
       "Your pawn is one step from queening, but your king is in its way. A rook on the 4th rank will shelter your king from checks once it steps out.",
       marks: [mark(.bridge, rowOf(4)), mark(.focus, ["d8"])],
       legend: [legend(.bridge, "Where the bridge goes"), legend(.focus, "Your king, stuck")]),
  page("Keep their king cut off", "3K4/3P1k2/8/8/8/8/r7/4R3 w",
       "Your rook holds the e-file, so their king can\u{2019}t come over to stop the pawn. Keep that file.",
       marks: [mark(.line, fileOf("e", 2, 8))], legend: [legend(.line, "Rook\u{2019}s line")]),
  page("Lift the rook", "3K4/3P1k2/8/8/8/8/r7/4R3 w",
       "Move the rook up to the 4th rank. It still holds the e-file.",
       steps: [
         step("e1", "e4", "Re4. The bridge is ready.", [mark(.bridge, rowOf(4))]),
         step("a2", "a1", "\u{2026}Ra1. They wait, ready to check from below."),
       ]),
  page("Walk out", "3K4/3P1k2/8/8/4R3/8/8/r7 w",
       "Step out to the side away from their king. Their rook checks, and your king zigzags down beside the pawn.",
       marks: [mark(.bridge, rowOf(4))],
       steps: [
         step("d8", "c7", "Kc7. Out from in front of the pawn."),
         step("a1", "c1", "\u{2026}Rc1+"),
         step("c7", "b6", "Kb6, heading down the board."),
         step("c1", "b1", "\u{2026}Rb1+"),
         step("b6", "c6", "Kc6. Zigzag, staying close to the pawn."),
         step("b1", "c1", "\u{2026}Rc1+"),
         step("c6", "b5", "Kb5. Your king has reached the 5th rank.", [mark(.focus, ["b4"])]),
         step("c1", "b1", "\u{2026}Rb1+ checks again."),
       ]),
  page("Block the check", "8/3P1k2/8/1K6/4R3/8/8/1r6 w",
       "Your king is on the 5th rank, so the rook on the 4th can block.",
       marks: [mark(.focus, ["b4"])],
       steps: [step("e4", "b4", "Rb4. The checks are over, and the pawn queens next move.", [mark(.key, ["b2", "b3", "b4"])])]),
])

let PHILIDOR_CARD = EndgameIntro(side: .b, pages: [
  page("Hold the third rank", "4k3/R7/1r6/4PK2/8/8/8/8 b",
       "Their king and pawn haven\u{2019}t reached your third rank. Your rook on it keeps their king from coming forward.",
       marks: [mark(.key, rowOf(6, "c", "h"))], legend: [legend(.key, "Your rook\u{2019}s rank")]),
  page("King in front", "4k3/R7/1r6/4PK2/8/8/8/8 b",
       "Keep your king on the pawn\u{2019}s queening square or right next to it.",
       marks: [mark(.key, ["e8"])]),
  page("Wait on the third", "4k3/R7/1r6/4PK2/8/8/8/8 b",
       "Move the rook back and forth along your third rank. Don\u{2019}t drop it to your back rank, where it\u{2019}s passive and loses.",
       steps: [
         step("b6", "c6", "\u{2026}Rc6. Just wait.", [mark(.key, ["a6", "b6", "d6", "e6", "f6", "g6", "h6"])]),
         step("e5", "e6", "e6. The pawn steps onto your third rank.", [mark(.focus, ["e6"])]),
       ]),
  page("Check from behind", "4k3/R7/2r1P3/5K2/8/8/8/8 b",
       "Now their king has no shelter in front of the pawn. Drop the rook to the far end and check from behind.",
       steps: [
         step("c6", "c1", "\u{2026}Rc1. To the far end."),
         step("f5", "f6", "Kf6"),
         step("c1", "f1", "\u{2026}Rf1+. Keep checking from behind. Their king can\u{2019}t hide."),
       ]),
])

/* ── the Plan lens ── */

/// Where a live game stands in its ending's plan: the card page it is on and
/// the marks for the board as it is now. No mark names a move.
public struct EndgamePlan: Equatable, Sendable {
  public var page: Int
  public var marks: LensMarks
}

private let KNIGHT_STEPS = [(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)]

/// Every square `me` attacks, with lines running on through the square `through`
/// (their king, so it can't step back along a check).
private func attacked(_ grid: Grid, by me: Color, through: String?) -> Set<String> {
  var out = Set<String>()
  func add(_ f: Int, _ r: Int) { if f >= 0 && f < 8 && r >= 0 && r < 8 { out.insert(sq(f, r)) } }
  for man in grid.men where man.color == me {
    switch man.type {
    case .p:
      add(man.file - 1, man.rank + forward(me))
      add(man.file + 1, man.rank + forward(me))
    case .n: for (df, dr) in KNIGHT_STEPS { add(man.file + df, man.rank + dr) }
    case .k: for (df, dr) in KING { add(man.file + df, man.rank + dr) }
    case .b, .r, .q:
      let dirs: [(Int, Int)] = man.type == .b ? DIAG : man.type == .r ? ORTHO : DIAG + ORTHO
      for (df, dr) in dirs {
        var f = man.file + df, r = man.rank + dr
        while f >= 0 && f < 8 && r >= 0 && r < 8 {
          out.insert(sq(f, r))
          if grid.man(f, r) != nil && sq(f, r) != through { break }
          f += df
          r += dr
        }
      }
    }
  }
  return out
}

/// The squares the other side's king can walk to without stepping onto one `me` attacks or holds.
func kingBox(_ fen: String, _ me: Color) -> [String] {
  let grid = Grid(fen)
  guard let king = grid.men.first(where: { $0.type == .k && $0.color != me }) else { return [] }
  let blocked = attacked(grid, by: me, through: king.square)
  var seen: Set<String> = [king.square]
  var queue = [(king.file, king.rank)]
  while let next = queue.popLast() {
    for (df, dr) in KING {
      let f = next.0 + df, r = next.1 + dr
      guard f >= 0, f < 8, r >= 0, r < 8 else { continue }
      let square = sq(f, r)
      if seen.contains(square) || blocked.contains(square) { continue }
      if let man = grid.man(f, r), man.color == me { continue }
      seen.insert(square)
      queue.append((f, r))
    }
  }
  return seen.sorted()
}

/// The square between the kings when they face each other on a file or rank with one square between.
private func faceOff(_ grid: Grid) -> String? {
  guard let w = grid.men.first(where: { $0.type == .k && $0.color == .w }),
    let b = grid.men.first(where: { $0.type == .k && $0.color == .b })
  else { return nil }
  let df = abs(w.file - b.file), dr = abs(w.rank - b.rank)
  guard (df == 0 && dr == 2) || (dr == 0 && df == 2) else { return nil }
  return sq((w.file + b.file) / 2, (w.rank + b.rank) / 2)
}

private func tints(_ squares: [String], _ color: TintColor, _ strength: Int) -> [Tint] {
  squares.map { Tint(square: $0, color: color, strength: strength) }
}

/// The Plan lens for a library ending: which page of its card the game is on, and that step's marks.
public func endgamePlan(_ entry: EndgameEntry, _ fen: String, _ me: Color) -> EndgamePlan? {
  guard let setup = entry.setup, entry.intro != nil else { return nil }
  let grid = Grid(fen)
  guard let mine = grid.men.first(where: { $0.type == .k && $0.color == me }),
    let theirs = grid.men.first(where: { $0.type == .k && $0.color != me })
  else { return nil }
  var marks = LensMarks()
  var tinted: [Tint] = []
  var page = 0
  let face = faceOff(grid)
  let pawn = grid.men.first { $0.type == .p }

  switch setup {
  case .mate(let material):
    let box = kingBox(fen, me)
    tinted += tints(box, .red, 1)
    let onEdge = theirs.file == 0 || theirs.file == 7 || theirs.rank == 0 || theirs.rank == 7
    switch material {
    case .queen:
      page = box.count <= 2 ? 2 : 1
    case .rook:
      if let rook = grid.men.first(where: { $0.type == .r && $0.color == me }) {
        let cuts = (rook.file > min(mine.file, theirs.file) && rook.file < max(mine.file, theirs.file))
          || (rook.rank > min(mine.rank, theirs.rank) && rook.rank < max(mine.rank, theirs.rank))
        let df = abs(mine.file - theirs.file), dr = abs(mine.rank - theirs.rank)
        let knight = (df == 1 && dr == 2) || (df == 2 && dr == 1)
        if face != nil && onEdge { page = 4 } else if !cuts { page = 1 } else if face != nil { page = 2 } else if knight { page = 3 }
      }
    case .bishops:
      page = box.count <= 4 ? 2 : 1
    }
    if let face { tinted += tints([face], .amber, 3) }

  case .keySquares, .opposition:
    guard let pawn else { return nil }
    let attacker = pawn.color
    let up = rel(attacker, pawn.rank)
    let keys = keySquares(pawn.square, attacker)
    tinted += tints(keys, attacker == me ? .green : .red, 2)
    if let face { tinted += tints([face], .amber, 3) }
    let inFront = mine.file == pawn.file && rel(attacker, mine.rank) > up
    if setup == .keySquares {
      if attacker == me { page = keys.contains(mine.square) ? 2 : 0 } else { page = up >= 5 ? 2 : inFront ? 1 : 0 }
    } else {
      if attacker == me { page = face != nil && fenTurn(fen) != me ? 0 : 1 } else { page = up >= 5 ? 2 : face != nil ? 0 : 1 }
    }

  case .square:
    guard let pawn else { return nil }
    let box = pawnSquare(fen, pawn.square, pawn.color)
    marks.boxes = [box]
    let up = rel(pawn.color, pawn.rank)
    if up == 1 {
      page = 1
    } else if pawn.color != me {
      let a = coords(box.from), b = coords(box.to)
      let inside = (min(a.file, b.file)...max(a.file, b.file)).contains(mine.file) && (min(a.rank, b.rank)...max(a.rank, b.rank)).contains(mine.rank)
      page = inside ? 2 : 0
    } else {
      page = 2
    }

  case .lucena:
    guard let pawn else { return nil }
    let bridge = me == .w ? 3 : 4
    tinted += tints((0..<8).map { sq($0, bridge) }, .purpleBlue, 1)
    let queening = sq(pawn.file, pawn.rank + forward(me))
    if let rook = grid.men.first(where: { $0.type == .r && $0.color == me }) {
      let cuts = rook.file > min(pawn.file, theirs.file) && rook.file < max(pawn.file, theirs.file)
      if cuts { marks.guides = [Guide(from: sq(rook.file, 0), to: sq(rook.file, 7), tone: "cutoff")] }
      if !cuts && mine.square == queening {
        page = 1
      } else if mine.square == queening {
        page = rook.rank == bridge ? 3 : 2
      } else {
        page = rel(me, mine.rank) <= 4 ? 4 : 3
      }
    }

  case .philidor:
    guard let pawn else { return nil }
    let third = me == .w ? 2 : 5
    let queening = sq(pawn.file, me == .w ? 0 : 7)
    if rel(pawn.color, pawn.rank) >= 5 {
      page = 3
      let far = pawn.color == .w ? [0, 1] : [6, 7]
      tinted += tints(far.flatMap { r in (0..<8).map { sq($0, r) } }, .green, 1)
    } else {
      let (qf, qr) = coords(queening)
      let near = abs(mine.file - qf) <= 1 && mine.rank == qr
      page = near ? 2 : 1
      tinted += tints((0..<8).map { sq($0, third) }, .green, 2)
      if !near { tinted += tints([queening], .amber, 3) }
    }
  }

  marks.tints = tinted
  marks.caption = entry.intro?.pages[page].title
  return EndgamePlan(page: page, marks: marks)
}
