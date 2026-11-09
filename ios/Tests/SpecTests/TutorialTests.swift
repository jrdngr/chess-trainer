import Foundation
import ChessCore
import Model
import Testing

/// Plays a tutorial game the way the run does, both sides from the pure
/// functions: the opponent's replies, your forced moves, and growth's one
/// answer (the script's, else the book's most played). Stops where the game
/// asks you to end it, or where your move is left to you.
private func playThrough(_ game: TutorialGame) -> (played: [String], line: [String]) {
  var played: [String] = []
  var line = game.opening.sans
  var grown = false
  while played.count < 40 {
    let mine = (played.count % 2 == 0) == (game.color == .w)
    if !mine {
      guard let reply = tutorialReply(game, played: played, line: line, bookIndex) else { break }
      played.append(reply)
      continue
    }
    if !grown && tutorialGrowsHere(game, played: played, line: line) {
      grown = true
      line = played
      for _ in 0..<game.growth {
        guard let answer = tutorialScripted(game, played) ?? bookTop(bookIndex, played) else { break }
        played.append(answer)
        line = played
        if ownPast(game.color, line, game.opening.sans) >= game.growth { break }
        guard let reply = tutorialReply(game, played: played, line: line, bookIndex) else { break }
        played.append(reply)
        line = played
      }
      continue
    }
    if tutorialEndCue(game, played: played, line: line, scored: 0, bookIndex) { break }
    guard let move = tutorialExpected(game, played: played, line: line, bookIndex) else { break }
    played.append(move)
  }
  return (played, line)
}

/// Game 1 forces White's line and three common moves past it, the opponent
/// following the script, then asks you to end it after its reply.
@Test func firstGamePlaysTheLineThenThreeCommonMoves() throws {
  let game = try #require(tutorialGame(1, RECOMMENDED_OPENINGS))
  let (played, mine) = playThrough(game)
  #expect(mine == line("e4 e5 Nf3 Nc6"))
  #expect(Array(played.prefix(8)) == line("e4 e5 Nf3 Nc6 Bc4 Bc5 c3 Nf6"))
  #expect(played.count == 10)
  #expect(ownPast(.w, played, mine) == 3)
  #expect(tutorialEndCue(game, played: played, line: mine, scored: 0, bookIndex))
  // Every forced move past the line is a common move, so it gets the quiet tick.
  #expect(commonPlies(bookIndex, played, from: 4) == Set(4..<10))
}

/// Game 2 grows the Italian by 3.Bc4 Bc5 4.c3, one answer at each step,
/// then three common moves past the new line.
@Test func secondGameGrowsTwoMovesThenEnds() throws {
  let game = try #require(tutorialGame(2, RECOMMENDED_OPENINGS))
  #expect(tutorialGrowsHere(game, played: line("e4 e5 Nf3 Nc6"), line: game.opening.sans))
  #expect(!tutorialGrowsHere(game, played: line("e4 e5 Nf3"), line: game.opening.sans))
  let (played, mine) = playThrough(game)
  #expect(mine == line("e4 e5 Nf3 Nc6 Bc4 Bc5 c3"))
  #expect(ownPast(.w, played, mine) == 3)
  #expect(tutorialEndCue(game, played: played, line: mine, scored: 0, bookIndex))
}

/// Game 3 forces Black's line and two common moves, then the opponent turns
/// to the engine, and the game asks you to end it only after three scored moves.
@Test func thirdGameHandsOverToTheEngine() throws {
  let game = try #require(tutorialGame(3, RECOMMENDED_OPENINGS))
  let (played, mine) = playThrough(game)
  #expect(played == line("e4 e5 Nf3 Nc6 Bc4 Bc5 c3 Nf6"))
  #expect(mine == game.opening.sans)
  // White's next move is the engine's, and yours is free.
  #expect(tutorialReply(game, played: played, line: mine, bookIndex) == nil)
  let after = played + ["d4", "exd4"]
  #expect(tutorialExpected(game, played: after, line: mine, bookIndex) == nil)
  #expect(!tutorialEndCue(game, played: after, line: mine, scored: 2, bookIndex))
  #expect(tutorialEndCue(game, played: after, line: mine, scored: 3, bookIndex))
}

/// Game 4 forces only your line, grows after the opponent's scripted 3.Bc4,
/// and never asks you to end it; game 5 forces nothing.
@Test func laterGamesLeaveTheMovesToYou() throws {
  let four = try #require(tutorialGame(4, RECOMMENDED_OPENINGS))
  #expect(tutorialExpected(four, played: line("e4"), line: four.opening.sans, bookIndex) == "e5")
  #expect(tutorialReply(four, played: line("e4 e5 Nf3 Nc6"), line: four.opening.sans, bookIndex) == "Bc4")
  #expect(tutorialGrowsHere(four, played: line("e4 e5 Nf3 Nc6 Bc4"), line: four.opening.sans))
  let grown = line("e4 e5 Nf3 Nc6 Bc4 Nf6 Ng5")
  #expect(tutorialExpected(four, played: grown, line: Array(grown.prefix(6)), bookIndex) == nil)
  #expect(!tutorialEndCue(four, played: grown, line: Array(grown.prefix(6)), scored: 9, bookIndex))
  let five = try #require(tutorialGame(5, RECOMMENDED_OPENINGS))
  #expect(tutorialReply(five, played: [], line: five.opening.sans, bookIndex) == "d4")
  #expect(tutorialExpected(five, played: line("d4"), line: five.opening.sans, bookIndex) == nil)
  #expect(five.tips.isEmpty)
}

/// Every opening on offer fits its slot and leaves the book something to play
/// past it, so growth and the common moves have moves to give.
@Test func offeredOpeningsFitTheirSlots() {
  for slot in TutorialSlot.allCases {
    let offered = [RECOMMENDED_OPENINGS[slot]] + (CURATED_OPENINGS[slot] ?? [])
    #expect(CURATED_OPENINGS[slot]?.count == 6)
    for opening in offered {
      #expect(slot.fits(opening.sans), "\(opening.name)")
      #expect(bookTop(bookIndex, opening.sans) != nil, "\(opening.name)")
    }
  }
  #expect(!TutorialSlot.e4.fits(line("d4 d5")))
  #expect(!TutorialSlot.d4.fits(line("d4")))
  #expect(!TutorialSlot.white.fits(line("e4 e4")))
}

/// Growth's gap is the position the run reached, for either side.
@Test func tutorialGapIsWhereTheRunStands() {
  var state = AppState()
  let w = state.ensureRepertoire(.w)
  let b = state.ensureRepertoire(.b)
  #expect(tutorialGap(state.repertoires[w]!, line("e4 e5 Nf3 Nc6")).line == line("e4 e5 Nf3 Nc6"))
  let black = tutorialGap(state.repertoires[b]!, line("e4 e5 Nf3 Nc6 Bc4"))
  #expect(black.line == line("e4 e5 Nf3 Nc6 Bc4"))
  #expect(black.hole.san == "Bc4")
  #expect(black.color == .b)
}

/// Home asks one thing at a time between games: Play, then Black, then the
/// opening against 1.d4 as Black.
@Test func homeStepsFollowTheGames() {
  var tutorial = Tutorial(openings: RECOMMENDED_OPENINGS)
  #expect(tutorialStep(tutorial, color: .w, selected: []).step == .play)
  tutorial.played = 1
  #expect(tutorialStep(tutorial, color: .w, selected: []).tip == "Play your Italian opening again.")
  tutorial.played = 2
  #expect(tutorialStep(tutorial, color: .w, selected: []).step == .side)
  #expect(tutorialStep(tutorial, color: .b, selected: []).step == .play)
  tutorial.played = 4
  #expect(tutorialStep(tutorial, color: .b, selected: line("e4 e5")).step == .opening)
  #expect(tutorialStep(tutorial, color: .w, selected: line("d4 d5")).step == .opening)
  let ready = tutorialStep(tutorial, color: .b, selected: line("d4 d5 c4 e6"))
  #expect(ready.step == .play && ready.tip == nil)
  tutorial.played = 5
  #expect(tutorialStep(tutorial, color: .b, selected: []).step == .playbook)
}

/// A game counts when it reached its end; the last leaves the Playbook's
/// tips, and the tutorial ends with the last of them.
@Test func tutorialEndsWithThePlaybookTips() {
  var settings = Settings()
  settings.startTutorial(RECOMMENDED_OPENINGS)
  settings.tips = [.flashCards]
  settings.finishTutorialGame(counted: false)
  #expect(settings.tutorial?.played == 0)
  #expect(settings.tips.isEmpty)
  for _ in 0..<TUTORIAL_GAMES { settings.finishTutorialGame(counted: true) }
  #expect(settings.tutorial?.next == nil)
  #expect(homeTip(settings.tips) == .playbookTab)
  #expect(playbookTip(settings.tips, hasRows: true) == nil)
  settings.putAway(.playbookTab)
  #expect(playbookTip(settings.tips, hasRows: false) == .playbookAdd)
  settings.putAway(.playbookAdd)
  settings.putAway(.playbookMore)
  #expect(playbookTip(settings.tips, hasRows: false) == nil)
  #expect(settings.tutorial != nil)
  settings.putAway(.playbookRow)
  #expect(settings.tutorial == nil)
}

/// Skipping mid-way still leaves the Playbook's tips, with Home unlocked.
@Test func skippingKeepsThePlaybookTips() {
  var settings = Settings()
  settings.startTutorial(RECOMMENDED_OPENINGS)
  settings.skipTutorial()
  #expect(settings.tutorial == nil)
  #expect(settings.tips == TutorialTip.afterGames)
}

/// A game's tips show at their moments, in order, and only once each.
@Test func gameTipsShowAtTheirMoments() throws {
  let tips = try #require(tutorialGame(3, RECOMMENDED_OPENINGS)).tips
  #expect(tutorialTip(tips, [.start]) == nil)
  #expect(tutorialTip(tips, [.scored]) == .scores)
  #expect(TutorialTip.scores.next == .lens)
  #expect(tutorialTip(tips, [.blunder, .endCue]) == .blunder)
  #expect(tutorialTip(Array(tips.dropFirst(3)), [.endCue]) == .endRun)
}

/// The tutorial and its tips survive a save; an old save owing the page on
/// how Play works gets the Playbook's tips, and unknown tips are dropped.
@Test func tutorialSavesAndOldTipsDecode() throws {
  var settings = Settings()
  settings.startTutorial(RECOMMENDED_OPENINGS)
  settings.finishTutorialGame(counted: true)
  let data = try JSONEncoder().encode(settings)
  let back = try JSONDecoder().decode(Settings.self, from: data)
  #expect(back.tutorial == settings.tutorial)
  let old = try JSONDecoder().decode(Settings.self, from: #"{"tips":["end","firstMove","lens"]}"#.data(using: .utf8)!)
  #expect(old.tips == TutorialTip.afterGames + [.lens])
  #expect(old.tutorial == nil)
}
