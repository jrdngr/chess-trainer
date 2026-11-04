import Model

/// What the reveal at the end of a batch says.
extension GrowthModel {
  /// What the verdict says.
  var verdict: (tone: GrowthVerdict.Tone, text: String) {
    let sans = addedSans
    if sans.isEmpty { return (.warn, session.edge ? "End of the book" : "Nothing to add here") }
    return (.ok, sans.count == 1 ? "\(sans[0]) added" : "\(sans.count) moves added")
  }
}
