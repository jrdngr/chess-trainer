import Book
import ChessCore

/// The tutorial a new profile plays: its Playbook starts with three openings
/// (one for White, Black's answers to 1.e4 and 1.d4), and five games teach
/// the game on them. Between games Home asks for one step at a time; after
/// the fifth, the Playbook tab's tips, and then everything is unlocked.
///
/// 1. White, your line played through, then a few common moves; Next run ends it.
/// 2. White again, with growth: one answer offered at each step.
/// 3. Black against 1.e4: your line, a few common moves, then scored moves; you end it.
/// 4. Black again, with growth: any answer; played until you blunder.
/// 5. Black against 1.d4, told only that the game goes on past your prep.

/// One of the three openings the tutorial needs.
public enum TutorialSlot: String, Sendable, Codable, CaseIterable, Identifiable {
  case white, e4, d4

  public var id: String { rawValue }

  public var color: Color { self == .white ? .w : .b }

  public var label: String {
    switch self {
    case .white: "White"
    case .e4: "Against 1.e4"
    case .d4: "Against 1.d4"
    }
  }

  /// Whether a line can fill this slot: White's any line of at least one
  /// move, Black's one that starts with the slot's first move and holds a Black move.
  public func fits(_ sans: [String]) -> Bool {
    guard walkSan(sans).fens.count == sans.count + 1 else { return false }
    switch self {
    case .white: return !sans.isEmpty
    case .e4: return sans.first == "e4" && sans.count >= 2
    case .d4: return sans.first == "d4" && sans.count >= 2
    }
  }
}

/// An opening the tutorial plays: its name, its moves, and the moves both
/// sides play past it in the tutorial's games where the book alone would
/// pick other ones.
public struct TutorialOpening: Equatable, Sendable, Codable {
  public var name: String
  public var sans: [String]
  public var script: [String]

  public init(name: String, sans: [String], script: [String] = []) {
    self.name = name
    self.sans = sans
    self.script = script
  }

  /// The name as a tip says it, "Italian" for "Italian Game".
  public var shortName: String {
    for suffix in [" Game", " Opening"] where name.hasSuffix(suffix) { return String(name.dropLast(suffix.count)) }
    return name
  }
}

/// The three openings, one per slot.
public struct TutorialOpenings: Equatable, Sendable, Codable {
  public var white: TutorialOpening
  public var e4: TutorialOpening
  public var d4: TutorialOpening

  public init(white: TutorialOpening, e4: TutorialOpening, d4: TutorialOpening) {
    self.white = white
    self.e4 = e4
    self.d4 = d4
  }

  public subscript(slot: TutorialSlot) -> TutorialOpening {
    switch slot {
    case .white: white
    case .e4: e4
    case .d4: d4
    }
  }

  /// What goes in the Playbook.
  public var seeds: [SeedOpening] {
    TutorialSlot.allCases.map { SeedOpening(sans: self[$0].sans, color: $0.color) }
  }
}

/// The Italian's first two moves, grown to 3.Bc4 and 4.c3 in game 2; 1...e5 against 1.e4,
/// grown to 3...Bc5 and 4...Nf6 in game 4; the Queen's Gambit Declined against 1.d4.
public let RECOMMENDED_OPENINGS = TutorialOpenings(
  white: TutorialOpening(name: "Italian Game", sans: ["e4", "e5", "Nf3", "Nc6"], script: ["e4", "e5", "Nf3", "Nc6", "Bc4", "Bc5", "c3", "Nf6"]),
  e4: TutorialOpening(name: "Open Game", sans: ["e4", "e5", "Nf3", "Nc6"], script: ["e4", "e5", "Nf3", "Nc6", "Bc4", "Bc5", "c3", "Nf6"]),
  d4: TutorialOpening(name: "Queen's Gambit Declined", sans: ["d4", "d5", "c4", "e6"]))

/// The openings Choose my own offers for each slot, before More openings.
public let CURATED_OPENINGS: [TutorialSlot: [TutorialOpening]] = [
  .white: [
    TutorialOpening(name: "Italian Game", sans: ["e4", "e5", "Nf3", "Nc6", "Bc4"]),
    TutorialOpening(name: "Ruy Lopez", sans: ["e4", "e5", "Nf3", "Nc6", "Bb5"]),
    TutorialOpening(name: "Scotch Game", sans: ["e4", "e5", "Nf3", "Nc6", "d4"]),
    TutorialOpening(name: "Queen's Gambit", sans: ["d4", "d5", "c4"]),
    TutorialOpening(name: "London System", sans: ["d4", "d5", "Bf4"]),
    TutorialOpening(name: "English Opening", sans: ["c4"]),
  ],
  .e4: [
    TutorialOpening(name: "Open Game", sans: ["e4", "e5", "Nf3", "Nc6"]),
    TutorialOpening(name: "Sicilian Defense", sans: ["e4", "c5"]),
    TutorialOpening(name: "French Defense", sans: ["e4", "e6", "d4", "d5"]),
    TutorialOpening(name: "Caro-Kann Defense", sans: ["e4", "c6", "d4", "d5"]),
    TutorialOpening(name: "Scandinavian Defense", sans: ["e4", "d5", "exd5", "Qxd5"]),
    TutorialOpening(name: "Pirc Defense", sans: ["e4", "d6", "d4", "Nf6"]),
  ],
  .d4: [
    TutorialOpening(name: "Queen's Gambit Declined", sans: ["d4", "d5", "c4", "e6"]),
    TutorialOpening(name: "Slav Defense", sans: ["d4", "d5", "c4", "c6"]),
    TutorialOpening(name: "King's Indian Defense", sans: ["d4", "Nf6", "c4", "g6", "Nc3", "Bg7"]),
    TutorialOpening(name: "Nimzo-Indian Defense", sans: ["d4", "Nf6", "c4", "e6", "Nc3", "Bb4"]),
    TutorialOpening(name: "Gr\u{00fc}nfeld Defense", sans: ["d4", "Nf6", "c4", "g6", "Nc3", "d5"]),
    TutorialOpening(name: "Dutch Defense", sans: ["d4", "f5"]),
  ],
]

/// Where a profile stands in the tutorial: its openings and how many games are done.
public struct Tutorial: Equatable, Sendable, Codable {
  public var openings: TutorialOpenings
  /// Games finished, 0...5.
  public var played: Int

  public init(openings: TutorialOpenings, played: Int = 0) {
    self.openings = openings
    self.played = played
  }

  /// The next game, while there is one.
  public var next: TutorialGame? { tutorialGame(played + 1, openings) }
}

public let TUTORIAL_GAMES = 5

/// One of the tutorial's games.
public struct TutorialGame: Equatable, Sendable {
  public var number: Int
  public var color: Color
  public var opening: TutorialOpening
  /// Your moves added at the end of your line, 0 for none.
  public var growth = 0
  /// Growth offers one answer only: the scripted move, else the book's most played.
  public var oneOption = false
  /// Your line's moves, and the moves past it up to `pastMoves`, are the only ones the board takes.
  public var forced = false
  /// Your moves past your line before the game asks you to end it; past them, a game with `scored` goes on.
  public var pastMoves: Int?
  /// Your moves the engine scores before the game asks you to end it. The opponent turns to the engine after `pastMoves`.
  public var scored: Int?
  /// The tips this game can show, in order.
  public var tips: [TutorialTip] = []
}

/// The tutorial's game `n`, 1...5.
public func tutorialGame(_ n: Int, _ openings: TutorialOpenings) -> TutorialGame? {
  switch n {
  case 1:
    TutorialGame(number: 1, color: .w, opening: openings.white, forced: true, pastMoves: 3,
                 tips: [.flashCards, .prepBar, .lineDone, .checkMark, .nextRun])
  case 2:
    TutorialGame(number: 2, color: .w, opening: openings.white, growth: 2, oneOption: true, forced: true, pastMoves: 3,
                 tips: [.extendLines, .answerRow, .doneButton, .saved, .endRun])
  case 3:
    TutorialGame(number: 3, color: .b, opening: openings.e4, forced: true, pastMoves: 2, scored: 3,
                 tips: [.scores, .lens, .blunder, .endRun])
  case 4:
    TutorialGame(number: 4, color: .b, opening: openings.e4, growth: 2, forced: true, tips: [.pickAny, .keepPlaying])
  case 5:
    TutorialGame(number: 5, color: .b, opening: openings.d4, tips: [.playOn])
  default:
    nil
  }
}

/// A tutorial game's round: its side, from move one, steered along its line.
public func tutorialRound(_ tree: OpeningTree, _ game: TutorialGame) -> AutoRound {
  AutoRound(pick: Recommendation(focus: .test, opening: tree.root, color: game.color, start: .first), at: nil, aim: game.opening.sans)
}

/// The next move of a line `played` is still on, if it is.
private func along(_ line: [String], _ played: [String]) -> String? {
  played.count < line.count && Array(line.prefix(played.count)) == played ? line[played.count] : nil
}

/// The move a tutorial game shows with an arrow: the one it insists on, or
/// in a free game the next move of your line while you're still on it.
public func tutorialShown(_ game: TutorialGame, played: [String], line: [String], _ index: ReferenceIndex) -> String? {
  tutorialExpected(game, played: played, line: line, index) ?? along(line, played)
}

/// The book's most played move here, nil where the book has none.
public func bookTop(_ index: ReferenceIndex, _ played: [String]) -> String? {
  let walked = walkSan(played)
  guard walked.fens.count == played.count + 1 else { return nil }
  return bookMoves(index, walked.fens[played.count]).first
}

/// The game's script past its line, where `played` still follows it.
public func tutorialScripted(_ game: TutorialGame, _ played: [String]) -> String? {
  along(game.opening.script, played)
}

/// Your moves played past `line`.
public func ownPast(_ color: Color, _ played: [String], _ line: [String]) -> Int {
  guard played.count > line.count else { return 0 }
  return (line.count..<played.count).filter { ($0 % 2 == 0) == (color == .w) }.count
}

/// The opponent's move in a tutorial game: along your line, then the script,
/// then the book's most played. Nil hands the move to the engine: past the
/// book, and in a game with scored moves once your forced moves past the line are done.
public func tutorialReply(_ game: TutorialGame, played: [String], line: [String], _ index: ReferenceIndex) -> String? {
  if let next = along(line, played) { return next }
  if let next = tutorialScripted(game, played) { return next }
  if game.scored != nil, ownPast(game.color, played, line) >= game.pastMoves ?? 0 { return nil }
  return bookTop(index, played)
}

/// The one move the board takes on your turn in a forced game: your line's,
/// then past it the script's or the book's most played, until `pastMoves`. Nil leaves the move to you.
public func tutorialExpected(_ game: TutorialGame, played: [String], line: [String], _ index: ReferenceIndex) -> String? {
  guard game.forced else { return nil }
  if let next = along(line, played) { return next }
  guard let past = game.pastMoves, ownPast(game.color, played, line) < past else { return nil }
  return tutorialScripted(game, played) ?? bookTop(index, played)
}

/// Whether the game now asks you to end it with the X: after its moves past
/// your line, or its scored moves, or where a forced game runs out of common moves early.
public func tutorialEndCue(_ game: TutorialGame, played: [String], line: [String], scored: Int, _ index: ReferenceIndex) -> Bool {
  guard played.count >= line.count else { return false }
  if let wanted = game.scored { return scored >= wanted }
  guard let past = game.pastMoves else { return false }
  if ownPast(game.color, played, line) >= past { return true }
  return game.forced && tutorialExpected(game, played: played, line: line, index) == nil
}

/// The gap a tutorial game grows at: the position `played` reaches.
public func tutorialGap(_ rep: Repertoire, _ played: [String]) -> Gap {
  let fens = walkSan(played).fens
  let before = fens.count >= 2 ? fens[fens.count - 2] : START_FEN
  let hole = Hole(
    path: Array(played.dropLast()), fen: before, san: played.last ?? "", share: 100, games: 0, after: fens.last ?? START_FEN,
    nodeId: nil, reach: 1)
  return Gap(kind: .noAnswer, repertoireId: rep.id, color: rep.color, hole: hole, importance: 1, name: "", missing: 1)
}

/// Whether a tutorial game grows at this turn: its growth not yet started,
/// your line played, and the opponent's reply to it at most.
public func tutorialGrowsHere(_ game: TutorialGame, played: [String], line: [String]) -> Bool {
  game.growth > 0 && played.count >= line.count && played.count <= line.count + 1 && Array(played.prefix(line.count)) == line
}

/// Where a tutorial game stands, as far as its tips care.
public enum TutorialMoment: Sendable, Hashable {
  /// Your first move.
  case start
  /// Your line under way, after your first move.
  case moved
  /// Your first move past your line.
  case pastLine
  /// Your next move, once your first move past your line has shown its \u{2713}.
  case pastCommon
  case growthOpen
  case growthEnded
  /// A move of yours was scored.
  case scored
  case blunder
  /// The game asks you to end it.
  case endCue
  /// Your prep just ended, and the board says so.
  case leftPrep
}

/// The tutorial's tips: in its games, then the Playbook tab's at its end.
public enum TutorialTip: String, Sendable, Codable, CaseIterable {
  case flashCards, prepBar, lineDone, checkMark, nextRun
  case extendLines, answerRow, doneButton, saved, endRun
  case scores, lens, blunder
  case pickAny, keepPlaying
  case playOn
  /// Home, after the last game: the Playbook tab.
  case playbookTab
  /// The Playbook tab, the first time it opens: its + button, its more menu, an opening's row.
  case playbookAdd, playbookMore, playbookRow

  public var text: String {
    switch self {
    case .flashCards:
      "Chess Playbook turns your openings into flashcards. You\u{2019}re graded on correctness and speed. We\u{2019}ll tell you which moves to play for this part of the tutorial."
    case .prepBar: "The prep bar fills as you play your line."
    case .lineDone: "That\u{2019}s your prep. Keep following the arrows."
    case .checkMark: "A \u{2713} means you\u{2019}re still playing common moves."
    case .nextRun: "Once your prep is done, tap \u{201C}Next run\u{201D} to start a new game."
    case .extendLines: "Extend the lines in your Playbook as you master them."
    case .answerRow: "Tap the answer or play it on the board."
    case .doneButton: "We\u{2019}ll suggest a few moves at a time. Tap Done to stop adding new moves early."
    case .saved: "Your new moves are saved. Keep playing on the board."
    case .endRun: "End the run."
    case .scores: "Outside of your lines, each move gets a score telling you how good (or bad) it was."
    case .lens: "Tap a lens for hints, then tap the board to turn it off."
    case .blunder: "A blunder ends the game."
    case .pickAny: "Pick any answer you like. The list shows how often each is played."
    case .keepPlaying: "Keep playing on the board."
    case .playOn: "Your prep is done, but the game isn\u{2019}t. Keep playing until you blunder, or tap \u{201C}Next run\u{201D}."
    case .playbookTab: "Your openings live in the Playbook."
    case .playbookAdd: "Tap + to add openings you already know."
    case .playbookMore: "Import your games."
    case .playbookRow: "Tap an opening to see its lines. Swipe left on it to remove it."
    }
  }

  /// When the tip shows; nil for one that follows another put away.
  public var moment: TutorialMoment? {
    switch self {
    case .flashCards: .start
    case .prepBar: .moved
    case .lineDone: .pastLine
    case .checkMark: .pastCommon
    case .nextRun, .endRun: .endCue
    case .playOn: .leftPrep
    case .extendLines, .pickAny: .growthOpen
    case .saved, .keepPlaying: .growthEnded
    case .scores: .scored
    case .blunder: .blunder
    case .answerRow, .doneButton, .lens, .playbookTab, .playbookAdd, .playbookMore, .playbookRow: nil
    }
  }

  /// The tip that follows this one once it is put away.
  public var next: TutorialTip? {
    switch self {
    case .extendLines: .answerRow
    case .answerRow: .doneButton
    case .scores: .lens
    default: nil
    }
  }

  /// The Playbook tab's tips, in the order they show.
  public static let playbook: [TutorialTip] = [.playbookAdd, .playbookMore, .playbookRow]

  /// What is left once the games are over: the Playbook tab on Home, then the tab's own.
  public static let afterGames: [TutorialTip] = [.playbookTab] + playbook

  /// Saved tips, by name; names this version doesn't know are dropped.
  /// "end" was Home's page on how Play works, from before the tutorial.
  public static func decoded(_ names: [String]) -> [TutorialTip] {
    names.flatMap { name in name == "end" ? afterGames : TutorialTip(rawValue: name).map { [$0] } ?? [] }
  }
}

/// The first of a game's tips still to show whose moment has come.
public func tutorialTip(_ pending: [TutorialTip], _ now: Set<TutorialMoment>) -> TutorialTip? {
  pending.first { $0.moment.map(now.contains) ?? false }
}

/// Home's tip to show now: the Playbook tab's, once the games are over.
public func homeTip(_ pending: [TutorialTip]) -> TutorialTip? {
  pending.contains(.playbookTab) ? .playbookTab : nil
}

/// The Playbook tab's tip to show now, once Home's is put away. The opening
/// row's waits until there is a row to point at.
public func playbookTip(_ pending: [TutorialTip], hasRows: Bool) -> TutorialTip? {
  guard !pending.contains(.playbookTab) else { return nil }
  return pending.first { TutorialTip.playbook.contains($0) && ($0 != .playbookRow || hasRows) }
}

/// What Home asks for between the tutorial's games.
public enum TutorialStep: Sendable, Equatable {
  /// Tap Play.
  case play
  /// Pick Black with the side button.
  case side
  /// Pick the opening against 1.d4 with the opening row.
  case opening
  /// The games are over: the Playbook tab.
  case playbook
}

/// Home's one step between games, and the tip on it. `selected` is the
/// selected opening's moves.
public func tutorialStep(_ tutorial: Tutorial, color: ColorChoice, selected: [String]) -> (step: TutorialStep, tip: String?) {
  let white = tutorial.openings.white.shortName
  switch tutorial.played {
  case 0: return (.play, "Play your \(white) opening.")
  case 1: return (.play, "Play your \(white) opening again.")
  case 2: return color == .b ? (.play, "Now play as Black.") : (.side, "Switch to Black.")
  case 3: return (.play, "Play again. This time you\u{2019}ll choose your own new moves.")
  case 4:
    if color == .b && selected.first == "d4" { return (.play, nil) }
    return (.opening, "Pick a specific opening. Your opponent will always play the other side of what you pick.")
  default: return (.playbook, nil)
  }
}

/// The tip in the opening sheet, on the opening that answers 1.d4.
public let D4_ROW_TIP = "Your answer to 1.d4."

extension Settings {
  /// Starts the tutorial on these openings.
  public mutating func startTutorial(_ openings: TutorialOpenings) {
    tutorial = Tutorial(openings: openings)
    selection = Selection(color: .w, opening: ANY_OPENING)
    tips = []
  }

  /// A tutorial game over: counted when it reached its end, and after the last one the Playbook's tips.
  public mutating func finishTutorialGame(counted: Bool) {
    tips = []
    guard var tutorial, counted else { return }
    tutorial.played += 1
    self.tutorial = tutorial
    if tutorial.played >= TUTORIAL_GAMES { tips = TutorialTip.afterGames }
  }

  /// The tutorial skipped: the Playbook's tips are still to show.
  public mutating func skipTutorial() {
    tutorial = nil
    tips = TutorialTip.afterGames
  }

  /// A tip put away. The tutorial ends with the Playbook tab's last.
  public mutating func putAway(_ tip: TutorialTip) {
    tips.removeAll { $0 == tip }
    if let tutorial, tutorial.played >= TUTORIAL_GAMES, !tips.contains(where: { TutorialTip.afterGames.contains($0) }) {
      self.tutorial = nil
    }
  }
}

/// The plies of `played` from `from` on that are common moves: ones the book plays in at least BOOK_SHARE of its games.
public func commonPlies(_ index: ReferenceIndex, _ played: [String], from: Int = 0) -> Set<Int> {
  let fens = walkSan(played).fens
  var out = Set<Int>()
  for ply in played.indices where ply >= from && ply < fens.count - 1 {
    if bookMoves(index, fens[ply]).contains(played[ply]) { out.insert(ply) }
  }
  return out
}

/* ── a first game with nothing saved, after the tutorial was skipped ── */

/// The first game's round: White, from move one, in no opening yet.
public func firstGameRound(_ tree: OpeningTree) -> AutoRound {
  AutoRound(pick: Recommendation(focus: .test, opening: tree.root, color: .w, start: .first), at: nil)
}

/// The gap a game with nothing saved for a side starts at: that side's first
/// move, before any reply.
public func firstMoveGap(_ rep: Repertoire, _ index: ReferenceIndex) -> Gap {
  let hole = Hole(path: [], fen: START_FEN, san: "", share: 100, games: 0, after: START_FEN, nodeId: nil, reach: 1)
  return Gap(kind: .noAnswer, repertoireId: rep.id, color: rep.color, hole: hole, importance: 1, name: "", missing: 1)
}
