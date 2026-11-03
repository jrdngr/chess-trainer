import Model

/// What the reveal at the end of a batch offers: another run on what is now
/// most worth extending.
extension GrowthModel {
  /// What the verdict says.
  var verdict: (tone: GrowthVerdict.Tone, text: String) {
    let sans = addedSans
    if sans.isEmpty { return (.warn, session.edge ? "End of the book" : "Nothing to add here") }
    return (.ok, sans.count == 1 ? "\(sans[0]) added" : "\(sans.count) moves added")
  }

  /// The row another run starts on: whatever the moves just added leave most worth extending.
  func nextRow() -> GrowthRow? {
    guard let live else { return nil }
    let next = recommended(growthRows([live], index, GrowthOptions(
      minShare: launch.find.minShare, maxPly: launch.find.maxPly, starred: store.state.settings.favoriteOpenings,
      region: (tree, launch.opening), pastBook: prefs.pastBook)))
    if let next {
      log(AppEvent(kind: "growth-start", via: .growth, rows: [next.name], picked: next.name, start: "new run"))
    }
    return next
  }
}
