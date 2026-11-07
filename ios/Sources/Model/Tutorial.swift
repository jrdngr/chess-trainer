import ChessCore

/// The playable tutorial: one scripted game as White in the Italian, fully on
/// rails. Each step is the move to play and the opponent's reply.

public enum TutorialPhase: String, Sendable {
  /// A move from the lent Playbook: ticked with your time.
  case prep
  /// A book move past the prep: ticked in the book's color.
  case book
  /// Out of book: the Pawns lens shows the push to play.
  case out
}

public struct TutorialStep: Equatable, Sendable {
  public var san: String
  public var reply: String?
  public var phase: TutorialPhase
}

/// 1.e4 e5 2.Nf3 Nc6 3.Bc4 from the lent Playbook, 4.c3 from the book, then
/// out of book the push 5.d4.
public let TUTORIAL_STEPS: [TutorialStep] = [
  TutorialStep(san: "e4", reply: "e5", phase: .prep),
  TutorialStep(san: "Nf3", reply: "Nc6", phase: .prep),
  TutorialStep(san: "Bc4", reply: "Bc5", phase: .prep),
  TutorialStep(san: "c3", reply: "Nf6", phase: .book),
  TutorialStep(san: "d4", reply: nil, phase: .out),
]

/// The moves the tutorial lends you as your Playbook.
public var TUTORIAL_PREP: Int { TUTORIAL_STEPS.filter { $0.phase == .prep }.count }

/// The tick and time a tutorial move earns over its square.
public func tutorialPop(square: String, seconds: Double, book: Bool) -> Pop {
  Pop(square: square, text: secondsText(seconds), tone: speedTone(seconds), found: true, book: book)
}
