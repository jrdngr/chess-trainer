import ChessCore

/// The playable tutorial: one scripted game as White in the Italian, fully on
/// rails. Each step is the move to play and the opponent's reply.

public enum TutorialPhase: String, Sendable {
  /// A move from the lent Playbook: ticked with your time.
  case prep
  /// A book move past the prep: ticked in the book's color.
  case book
  /// Out of book: a move shown by an arrow, not ticked.
  case out
  /// Out of book: hold Pawns, and its lens shows the break to play.
  case lens
}

public struct TutorialStep: Equatable, Sendable {
  public var san: String
  public var reply: String?
  public var phase: TutorialPhase
  /// The instruction over the note.
  public var title: String
  /// The line under the instruction.
  public var note: String?
}

/// 1.e4 e5 2.Nf3 Nc6 from the lent Playbook, 3.Bc4 Bc5 from the book, out of
/// book 4.c3 Nf6, then the break 5.d4 the Pawns lens shows.
public let TUTORIAL_STEPS: [TutorialStep] = [
  TutorialStep(
    san: "e4", reply: "e5", phase: .prep, title: "Play e4.",
    note: "Your Playbook contains the openings you play. Every move from one is a flash card that you get quizzed on in a real game."),
  TutorialStep(
    san: "Nf3", reply: "Nc6", phase: .prep, title: "Play Nf3.",
    note: "Make the correct move from your opening line and you\u{2019}ll get points for that line."),
  TutorialStep(
    san: "Bc4", reply: "Bc5", phase: .book, title: "Play Bc4.",
    note: "Once you get to the end of the line, the game will let you know when you\u{2019}re still in the book."),
  TutorialStep(
    san: "c3", reply: "Nf6", phase: .out, title: "Out of book.",
    note: "Once you\u{2019}re out of the book, you keep playing until you blunder."),
  TutorialStep(
    san: "d4", reply: nil, phase: .lens, title: "Hold the \u{201C}Pawns\u{201D} button.",
    note: "Lenses show what matters in the position and hint at what to do next."),
]

/// The lens step's instruction once Pawns has been held.
public let TUTORIAL_LENS_PLAY = "Play the suggested move."

/// The instruction and note for a step; the lens step's instruction moves on
/// once Pawns is held, and its note stays.
public func tutorialText(_ step: TutorialStep, pawnsHeld: Bool) -> (title: String, note: String?) {
  (step.phase == .lens && pawnsHeld ? TUTORIAL_LENS_PLAY : step.title, step.note)
}

/// The moves the tutorial lends you as your Playbook.
public var TUTORIAL_PREP: Int { TUTORIAL_STEPS.filter { $0.phase == .prep }.count }

/// The tick and time a tutorial move earns over its square.
public func tutorialPop(square: String, seconds: Double, book: Bool) -> Pop {
  Pop(square: square, text: secondsText(seconds), tone: speedTone(seconds), found: true, book: book)
}
