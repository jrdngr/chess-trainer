import ChessCore
import Engine
import Model

/// The headless app as text: what a player would see on screen, for the command line and for agents.
extension HeadlessApp {
  /// The screen, the board and what is going on, then what flashed by since the last report.
  public func report() -> String {
    var lines: [String] = ["[\(screen.rawValue)]"]
    switch screen {
    case .welcome: lines.append("Welcome. `recommend` seeds the recommended openings and starts Play, or `choose WHITE E4 D4` picks an opening per slot by id (White, Black against 1.e4, Black against 1.d4; `openings` lists them) and starts Play.")
    case .onboarding: lines.append("Choosing openings. `recommend` seeds the recommended openings and starts Play, or `choose WHITE E4 D4` picks an opening per slot by id and starts Play.")
    case .home: lines += homeLines()
    case .play, .middlegame: lines += runLines()
    case .endgame: lines += endgameLines()
    }
    let flashed = takeSignals().compactMap(Self.describe)
    if !flashed.isEmpty { lines.append("Shown: " + flashed.joined(separator: ", ")) }
    return lines.joined(separator: "\n")
  }

  private func homeLines() -> [String] {
    let selection = state.settings.selection
    var lines = ["Pawns: \(state.pawns)", "Play: \(colorLabel(selection.color)), \(state.settings.start.rawValue), \(openingName(tree, selection.opening))"]
    if let tip = state.homeTip { lines.append("Tip: \(tip.text)") }
    let locked = ShopFeature.allCases.filter { !state.owns($0) }.compactMap { shopItem($0.rawValue)?.name }
    if !locked.isEmpty { lines.append("Locked: \(locked.joined(separator: ", ")). `shop` lists the Pawn Shop.") }
    if let next = nextUp { lines.append("Next: \(next.name) \(nextWhen(next.runs))") }
    return lines
  }

  private func runLines() -> [String] {
    if let building = middlegame?.building { return ["Building the handoff: \(building.joined(separator: " › "))"] }
    guard let model = run else { return [play?.nothing == true ? "Nothing to practice yet: the Playbook has no lines in this selection." : "No round."] }
    var lines = ["\(model.headerName), you play \(model.run.color == .w ? "White" : "Black"), \(model.session.state.extras.pawns) pawns this run, \(state.pawns) in all"]
    lines.append(board(model.shownFen, model.run.color))
    lines.append("Moves: \(sansToMoveText(model.run.played))")
    if let label = model.label { lines.append("Prep: \(label.rawValue)") }
    if let tip = model.tip { lines.append("Tip: \(tip.text)") }
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
    lines.append(model.myTurn ? "Your move." : model.thinking ? "Opponent thinking." : "Waiting.")
    return lines
  }

  private func endgameLines() -> [String] {
    guard let game = endgame?.game else {
      let record = state.endgames
      return ["Endgames: \(record.due.count) due. `practice`, or `ending <id>`: " + record.entries.prefix(8).map(\.id).joined(separator: ", ")]
    }
    var lines = ["\(game.entry.name), goal \(game.entry.goal.label), you play \(game.color == .w ? "White" : "Black")"]
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

  /// The Pawn Shop: every item, its price and where it stands for you.
  public func shopReport() -> String {
    var lines = ["Pawn Shop: \(state.pawns) pawns"]
    for shelf in ShopShelf.allCases {
      lines.append(shelf.rawValue.capitalized + ":")
      for item in SHOP where item.shelf == shelf {
        let status: String
        switch state.status(item) {
        case .owned: status = "yours"
        case .buyable: status = "\(item.price), `buy \(item.id)`"
        case .short(let by): status = "\(item.price), \(by) short"
        case .locked: status = "needs " + item.needs.compactMap { shopItem($0)?.name }.joined(separator: ", ")
        case .soon: status = "\(item.price)\(item.each ? " each" : ""), coming"
        }
        lines.append("  \(item.name): \(status)")
      }
    }
    return lines.joined(separator: "\n")
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
    case .buzz, .success: return nil
    case .callout(let text, _): return text
    case .pop(let pop): return "\(pop.book ? "book" : pop.found ? "✓" : "score") \(pop.text) on \(pop.square)"
    case .miss(let miss): return "missed: \(miss.expected) was prepared"
    case .toast(let text): return text
    case .pawns(let award): return "+\(award.count) pawn\(award.count == 1 ? "" : "s"): \(award.event.rawValue)"
    }
  }
}
