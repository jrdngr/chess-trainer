import Game
import Model

/// What the reveal at the end of a batch says.
extension GrowthModel {
  /// What the verdict says.
  var verdict: (tone: GrowthVerdict.Tone, text: String) {
    (addedSans.isEmpty ? .warn : .ok, verdictText)
  }
}
