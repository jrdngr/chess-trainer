import ChessCore

/// The playable tutorial: one scripted game as White in the Italian, fully on
/// rails. Each step is the move to play and the opponent's reply.

public enum TutorialPhase: String, Sendable {
  /// A move from the lent Playbook: ticked with your time.
  case prep
  /// A book move past the prep: ticked in the book's color.
  case book
  /// Out of book: the Pawns lens shows the break to play.
  case out
}

public struct TutorialStep: Equatable, Sendable {
  public var san: String
  public var reply: String?
  public var phase: TutorialPhase
  /// The line under the instruction.
  public var note: String
}

/// 1.e4 e5 2.Nf3 Nc6 from the lent Playbook, 3.Bc4 Bc5 from the book, then
/// out of book the break 4.d4 the Pawns lens shows.
public let TUTORIAL_STEPS: [TutorialStep] = [
  TutorialStep(
    san: "e4", reply: "e5", phase: .prep,
    note: "Your openings are saved as lines. Every move from one is a flash card."),
  TutorialStep(
    san: "Nf3", reply: "Nc6", phase: .prep,
    note: "Right and fast raises your rating for the opening. The tick and time show how you did."),
  TutorialStep(
    san: "Bc4", reply: "Bc5", phase: .book,
    note: "Your line ends here. The book shows strong players' moves, and you're never graded on them."),
  TutorialStep(
    san: "d4", reply: nil, phase: .out,
    note: "Now it's a real game until you blunder."),
]

/// The out-of-book step's line once Pawns is held.
public let TUTORIAL_LENS_NOTE = "Lenses show what matters in the position and hint at what to do next."

/// The instruction for a step: the move to play, or out of book, Hold Pawns
/// until it is held.
public func tutorialInstruction(_ step: TutorialStep, pawnsHeld: Bool) -> String {
  guard step.phase == .out else { return "Play \(step.san)." }
  return pawnsHeld ? "Play the suggested move." : "Hold Pawns."
}

/// The moves the tutorial lends you as your Playbook.
public var TUTORIAL_PREP: Int { TUTORIAL_STEPS.filter { $0.phase == .prep }.count }

/// The tick and time a tutorial move earns over its square.
public func tutorialPop(square: String, seconds: Double, book: Bool) -> Pop {
  Pop(square: square, text: secondsText(seconds), tone: speedTone(seconds), found: true, book: book)
}
