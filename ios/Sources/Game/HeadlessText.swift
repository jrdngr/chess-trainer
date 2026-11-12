import ChessCore
import Model

/// The headless app as text: what a player would see on screen, for the command line and for agents.
extension HeadlessApp {
  /// The screen, the board and what is going on, then what flashed by since the last report.
  public func report() -> String {
    var lines: [String] = ["[\(screen.rawValue)]"]
    switch screen {
    case .welcome: lines.append("Welcome. `intro` reads it; then `recommend` starts the tutorial, or `skip [starter]` skips it.")
    case .onboarding: lines.append("Onboarding. `recommend` starts the tutorial with recommended openings, or `skip [starter]` skips it.")
    case .home: lines += homeLines()
    case .play, .middlegame: lines += runLines()
    case .growth: lines += growthLines()
    case .endgame: lines += endgameLines()
    }
    let flashed = takeSignals().compactMap(Self.describe)
    if !flashed.isEmpty { lines.append("Shown: " + flashed.joined(separator: " · ")) }
    return lines.joined(separator: "\n")
  }

  private func homeLines() -> [String] {
    let selection = state.settings.selection
    var lines = ["Play: \(colorLabel(selection.color)), \(state.settings.start.rawValue), \(openingName(tree, selection.opening))"]
    if let tutorial = state.settings.tutorial { lines.append("Tutorial: \(tutorial.played) of \(TUTORIAL_GAMES) games played") }
    let recs = recommendations.prefix(5)
    if !recs.isEmpty {
      lines.append("Recommendations:")
      for (i, gap) in recs.enumerated() {
        lines.append("  \(i + 1). \(gap.name) (\(gap.color == .w ? "White" : "Black")): \(sansToMoveText(gap.line))")
      }
    }
    return lines
  }

  private func runLines() -> [String] {
    if let building = middlegame?.building { return ["Building the handoff: \(building.joined(separator: " › "))"] }
    guard let model = run else { return [play?.nothing == true ? "Nothing to practice yet: the Playbook has no lines in this selection." : "No round."] }
    var lines = ["\(model.headerName) · you play \(model.run.color == .w ? "White" : "Black")"]
    lines.append(board(model.shownFen, model.run.color))
    lines.append("Moves: \(sansToMoveText(model.run.played))")
    if let label = model.label { lines.append("Prep: \(label.rawValue)") }
    if let game = model.tutorialGame { lines.append("Tutorial game \(game.number) of \(TUTORIAL_GAMES)") }
    if let tip = model.tip { lines.append("Tip: \(tip.rawValue)") }
    if let finish = model.finish {
      lines.append("Over: \(endingTitle(finish.how, model.run.played.count))")
      if model.phase == .blunder, let blunder = model.blunder {
        lines.append("Blunder: \(blunder.move.san)" + (blunder.threat.map { ", threat \($0.san)" } ?? "") + ". `continue` for the end screen.")
      }
      lines.append(play != nil ? "`next` deals the next round; `home` leaves." : "`next` plays another line; `home` leaves.")
      return lines
    }
    if model.fill != nil {
      lines.append("Adding moves: \(choices.joined(separator: ", ")). Play one, `undo`, or `done`.")
    } else if model.holeGap != nil {
      lines.append("A reply with no answer: `grow` adds moves here.")
    }
    if let expected = model.expected { lines.append("The tutorial wants \(expected).") }
    lines.append(model.myTurn ? "Your move." : model.thinking ? "Opponent thinking." : "Waiting.")
    return lines
  }

  private func growthLines() -> [String] {
    guard let growth else { return [] }
    var lines = ["Growth · \(growth.launch.row.name) · you play \(growth.run.color == .w ? "White" : "Black")"]
    lines.append(board(growth.fen, growth.run.color))
    lines.append("Moves: \(sansToMoveText(growth.run.path))")
    lines.append("Added: \(growth.addedSans.isEmpty ? "nothing yet" : growth.addedSans.joined(separator: ", "))")
    switch growth.phase {
    case .hole: lines.append("Answers: \(choices.joined(separator: ", ")). Play one.")
    case .done, .lost: lines.append("Done: \(growth.verdictText). `save` keeps the moves, `more` adds another batch.")
    default: lines.append("Walking your line.")
    }
    return lines
  }

  private func endgameLines() -> [String] {
    guard let game = endgame?.game else {
      let record = state.endgames
      return ["Endgames: \(record.due.count) due. `practice`, or `ending <id>`: " + record.entries.prefix(8).map(\.id).joined(separator: ", ")]
    }
    var lines = ["\(game.entry.name) · goal: \(game.entry.goal.label) · you play \(game.color == .w ? "White" : "Black")"]
    lines.append(board(game.fen, game.color))
    lines.append("Moves: \(game.moves.joined(separator: " "))")
    if let note = game.note { lines.append(note) }
    if let outcome = game.outcome {
      switch outcome {
      case .success(let text, _): lines.append("Over: \(text). `next` for the next ending.")
      case .failure(let text): lines.append("Over: \(text). `next` for the next ending.")
      }
    } else {
      lines.append(game.myTurn ? "Your move." : "Opponent thinking.")
    }
    return lines
  }

  /// The board from `side`'s seat, uppercase White, with coordinates.
  public func board(_ fen: String, _ side: ChessCore.Color) -> String {
    var cells = Array(repeating: Array(repeating: ".", count: 8), count: 8)
    for piece in piecesFromFen(fen) {
      let scalars = Array(piece.square.unicodeScalars)
      let file = Int(scalars[0].value) - 97, rank = Int(scalars[1].value) - 49
      let letter = piece.type.rawValue
      cells[rank][file] = piece.color == .w ? letter.uppercased() : letter
    }
    let ranks = side == .w ? Array((0..<8).reversed()) : Array(0..<8)
    let files = side == .w ? Array(0..<8) : Array((0..<8).reversed())
    var rows = ranks.map { r in "\(r + 1) " + files.map { cells[r][$0] }.joined(separator: " ") }
    rows.append("  " + files.map { String(UnicodeScalar(UInt8(97 + $0))) }.joined(separator: " "))
    return rows.joined(separator: "\n")
  }

  /// A signal as a few words; nil for a buzz.
  static func describe(_ signal: GameSignal) -> String? {
    switch signal {
    case .buzz, .success, .edgeFlash: return nil
    case .callout(let text, _): return text
    case .pop(let pop): return "\(pop.book ? "book" : pop.found ? "✓" : "score") \(pop.text) on \(pop.square)"
    case .miss(let miss): return "missed: \(miss.expected) was prepared"
    case .toast(let text): return text
    }
  }
}

extension GrowthModel {
  /// What the end of a batch says.
  public var verdictText: String {
    let sans = addedSans
    if sans.isEmpty { return session.edge ? "End of the book" : "Nothing to add here" }
    return sans.count == 1 ? "\(sans[0]) added" : "\(sans.count) moves added"
  }
}
