import Model

/// What the reveal at the end of a batch offers: practice the opening just
/// grown, or another run on what is now most worth extending.
extension GrowthModel {
  /// The opening grown, and how much practice it is owed, read from the live tree.
  var practice: (opening: OpeningNode, owed: PracticeOwed)? {
    guard phase == .done, let live else { return nil }
    let opening = offerOpening(tree, launch.opening, nil, run.path)
    return (opening, practiceOwed(live, tree, opening, store.state.score.rounds))
  }

  /// The card points back once the opening owes its cap of practice.
  var pointsBack: Bool { practice.map { atPracticeCap($0.owed) } ?? false }

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
