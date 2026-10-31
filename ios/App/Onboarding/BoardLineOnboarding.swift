import Model

extension BoardLine {
  /// A line from the board, as onboarding takes it in.
  var onboarding: OnboardingLine { OnboardingLine(sans: sans, color: color, lost: lost) }
}
