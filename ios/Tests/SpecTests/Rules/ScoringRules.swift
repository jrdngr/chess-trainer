import ChessCore
import Foundation
import Model
import Testing

private let ALL = ExtrasPrefs(moments: true, missions: true)

private func move(lost: Double, after: Double = 0, moment: Bool = false, found: Bool = false) -> JudgedMove {
  JudgedMove(lost: lost, after: after, moment: moment, found: found)
}

@Suite("docs/rules/scoring.md") struct ScoringRules {
  /// Rule 1: what a moment is, what finding one pays, and what missing one breaks.
  @Test func moments() {
    #expect(isMoment(.w, 250, 100))
    #expect(!isMoment(.w, 249, 100))
    #expect(!isMoment(.w, 99, -100))
    #expect(isMoment(.b, -250, -100))
    #expect(isMoment(.w, 10_000, 300))
    #expect(!isMoment(.w, 10_000, 10_000))
    #expect(MOMENT_FOUND == 50)
    var extras = NO_EXTRAS
    extras.moments.streak = 2
    let missed = judgedExtras(extras, ALL, .w, move(lost: 300, moment: true, found: false))
    #expect(missed.extras.moments.streak == 0)
    let found = judgedExtras(extras, ALL, .w, move(lost: 0, moment: true, found: true))
    #expect(found.earned.pawns == 6 && found.extras.pawns == 6 && found.extras.moments.streak == 3)
  }

  /// Rule 2: a missed moment's callout names the move you missed, in the missed-chance tone.
  @Test func aMissedMomentNamesTheMove() {
    let missed = judgedExtras(NO_EXTRAS, ALL, .w, move(lost: 300, moment: true, found: false)).earned
    #expect(noteFor(missed, best: "Nxe6") == Note(text: "Missed Nxe6", tone: "missed"))
    let found = judgedExtras(NO_EXTRAS, ALL, .w, move(lost: 0, moment: true, found: true)).earned
    #expect(noteFor(found, best: "Nxe6") == nil, "a find says nothing here")
  }

  /// Rule 3: the first mission is set from the eval where the prep runs out.
  @Test func firstMissionFromTheEval() {
    let pieces = "r3k3/8/8/8/8/8/8/R3K3 w - - 0 1"
    #expect(firstMission(NO_EXTRAS, missions: true, .w, 200, pieces).mission?.kind == .convert)
    #expect(firstMission(NO_EXTRAS, missions: true, .w, 200, "4k3/8/8/8/8/8/8/R3K3 w - - 0 1").mission?.kind == .edge)
    #expect(firstMission(NO_EXTRAS, missions: true, .w, 100).mission?.kind == .edge)
    #expect(firstMission(NO_EXTRAS, missions: true, .b, 100).mission?.kind == .dig)
    #expect(firstMission(NO_EXTRAS, missions: true, .w, 99).mission?.kind == .lead)
    #expect(stepMission(Mission(kind: .edge), .w, 99).result == .failed)
    #expect(stepMission(Mission(kind: .lead, moves: 14), .w, 99).result == .failed)
    #expect(stepMission(Mission(kind: .dig), .w, -50).result == .done)
    #expect(stepMission(Mission(kind: .convert, pieces: PieceCount(mine: 1, theirs: 1)), .w, 99, pieces).result == .failed)
  }

  /// Rule 4: three judged moves after a mission settles, the next is set. A mission done pays 2 pawns.
  @Test func missionsFollowEachOther() {
    var extras = NO_EXTRAS
    extras.mission = Mission(kind: .edge)
    extras = judgedExtras(extras, ALL, .w, move(lost: 0, after: 0)).extras
    #expect(extras.mission == nil && extras.missions.failed == 1)
    extras = judgedExtras(extras, ALL, .w, move(lost: 0, after: -200)).extras
    extras = judgedExtras(extras, ALL, .w, move(lost: 0, after: -200)).extras
    #expect(extras.mission == nil)
    extras = judgedExtras(extras, ALL, .w, move(lost: 0, after: -200)).extras
    #expect(extras.mission?.kind == .dig)
    #expect(extras.pawns == 0)
    var edge = NO_EXTRAS
    edge.mission = Mission(kind: .edge, held: EDGE_MOVES - 1)
    let done = judgedExtras(edge, ALL, .w, move(lost: 0, after: 150))
    #expect(done.earned.pawns == 6 && done.extras.missions.done == 1)
  }
}
