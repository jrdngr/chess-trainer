import ChessCore
import Foundation
import Model
import Testing

@Suite("docs/rules/saves.md") struct SavesRules {
  /// Rule 1: a new save starts at the current version; a save from before versions starts at 0.
  @Test func saveVersionDefaults() throws {
    #expect(AppState().version == SAVE_VERSION)
    let old = try JSONDecoder().decode(AppState.self, from: Data("{}".utf8))
    #expect(old.version == 0)
  }

  /// Rule 3: version 2 counts schedules in runs: a card's days become three runs each, and an
  /// Endgame position waits its interval in Endgame rounds, or is due if it was failed last.
  @Test func migrationSchedulesByRuns() throws {
    var state = AppState()
    state.version = 1
    var card = createCard("rep_w#k", "rep_w", "k", "fen", 0)
    card.stage = .review
    card.interval = 4
    state.cards[card.id] = card
    state.endgames.cards["won"] = EndgameCard(dueRound: 0, interval: 2.5, reps: 2, lapses: 0)
    state.endgames.cards["lost"] = EndgameCard(dueRound: 0, interval: 0, reps: 1, lapses: 1)
    let changed = state.migrate(bookIndex)
    #expect(changed)
    #expect(state.cards[card.id]?.interval == 12)
    #expect(state.endgames.cards["won"]?.dueRound == 8)
    #expect(state.endgames.due.isEmpty)
    #expect(state.endgames.cards["lost"]?.dueRound == 0)
  }

  /// Rule 3: an Endgame card saved with a date instead of a round reads as due at once.
  @Test func anEndgameCardWithADateReadsAsDue() throws {
    let data = Data(#"{"due":1790845200000.5,"interval":2.5,"reps":2,"lapses":0}"#.utf8)
    #expect(try JSONDecoder().decode(EndgameCard.self, from: data).dueRound == 0)
  }

  /// Rule 4: a save from before version 3 reads under the new names: Playbook keys,
  /// run modes and Play settings, with the old Play mode's tallies kept apart.
  @Test func oldNamesReadUnderTheNewOnes() throws {
    var state = AppState()
    let id = state.ensurePlaybook(.w)
    state.addLine(id, line("e4 e5"), .fixed(.book))
    state.answered(id, START_FEN, "e4", .good)
    state.runRecord.global.best = 12
    state.settings.play.moveScores = false
    state.settings.selection = Selection(color: .either, opening: ANY_OPENING)
    state.score.global.byMode[.oldPlay]?.rounds = 2
    state.score.global.byMode[.run]?.rounds = 5
    state.score.rounds = [RoundRecord(mode: .run, openingId: "", color: .w, answered: 1, correct: 1, perfect: true, at: 0)]
    state.recordGame(GameRecord(
      id: "g", mode: .play, at: 0, color: .w, picked: state.settings.selection, opening: "", moves: ["e4"], result: "*", termination: "ended"))
    state.events = [AppEvent(kind: "add", via: .playbook, playbookId: id), AppEvent(kind: "remove-playbook", playbookId: id)]
    // The same save as version 2 wrote it.
    var old = String(decoding: try JSONEncoder().encode(state), as: UTF8.self)
    for (new, was) in [
      ("\"playbookId\"", "\"repertoireId\""), ("\"playbooks\"", "\"repertoires\""), ("\"playbookOrder\"", "\"repertoireOrder\""),
      ("\"runRecord\"", "\"survival\""), ("\"version\":\(SAVE_VERSION)", "\"version\":2"), ("\"run\":{", "\"survival\":{"), ("\"oldPlay\":{", "\"run\":{"),
      ("\"mode\":\"run\"", "\"mode\":\"survival\""), ("\"mode\":\"play\"", "\"mode\":\"autopilot\""), ("\"via\":\"playbook\"", "\"via\":\"repertoire\""),
      ("\"remove-playbook\"", "\"remove-repertoire\""),
      ("\"play\":{", "\"autopilot\":{"), ("\"either\"", "\"random\""),
    ] {
      #expect(old.contains(new), "\(new) is not in the save")
      old = old.replacingOccurrences(of: new, with: was)
    }
    var read = try decodeSave(Data(old.utf8))
    #expect(read.version == 2)
    read.version = SAVE_VERSION
    #expect(read == state)
  }

  /// Rule 5: version 4 drops Middlegame's bests in points and keeps its counts.
  @Test func middlegameRecordsDropTheirPoints() throws {
    var state = AppState()
    state.version = 3
    let tree = openingTree(bookIndex)
    state.middlegame = recordRun(RunRecord(), tree, line("d4 d5 c4"), 140)
    state.middlegame = recordEndedRun(state.middlegame, tree, line("d4 d5 c4"))
    state.migrate(bookIndex)
    #expect(state.middlegame.global.best == 0 && state.middlegame.global.recent.isEmpty)
    #expect(state.middlegame.global.runs == 1 && state.middlegame.global.ended == 1)
    #expect(state.middlegame.openings.values.allSatisfy { $0.best == 0 && $0.runs == 1 })
  }

  /// A current save reads as it is.
  @Test func currentSavesReadAsTheyAre() throws {
    var state = AppState()
    state.addLine(state.ensurePlaybook(.w), line("e4 e5"), .fixed(.book))
    let data = try JSONEncoder().encode(state)
    #expect(renamedSave(data) == data)
    #expect(try decodeSave(data) == state)
  }

  /// Rule 4: a save renamed on load and written back before its version was raised reads as it is.
  @Test func renamedSaveWrittenBackEarlyReadsAsItIs() throws {
    var state = AppState()
    state.addLine(state.ensurePlaybook(.w), line("e4 e5"), .fixed(.book))
    state.settings.play.moveScores = false
    state.score.global.byMode[.run]?.rounds = 5
    state.recordGame(GameRecord(
      id: "g", mode: .play, at: 0, color: .w, picked: state.settings.selection, opening: "", moves: ["e4"], result: "*", termination: "ended"))
    state.version = 0
    let data = try JSONEncoder().encode(state)
    #expect(renamedSave(data) == data)
    #expect(try decodeSave(data) == state)
  }

  /// Rule 6: version 5 gives a profile from before the Pawn Shop every feature; a new one owns none.
  @Test func profilesFromBeforeTheShopOwnEveryFeature() throws {
    #expect(AppState().unlocked.isEmpty)
    var old = try decodeSave(Data(#"{"version":4,"pawns":3}"#.utf8))
    old.migrate(bookIndex)
    #expect(ShopFeature.allCases.allSatisfy(old.owns))
    #expect(old.pawns == 3)
  }
}
