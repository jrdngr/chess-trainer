import ChessCore
import Foundation
import Game
import Model
import Testing

/// Tidy from the Playbook tab: the count matches the list, Switch these moves puts the
/// offered move in place of yours and drops the count, and Undo brings it all back.
@MainActor @Test func tidySwitchesAMoveAndUndoes() async throws {
  try await headless { app in
    onboard(app, recommended: false)
    var id = ""
    app.store.update { state in
      id = state.ensurePlaybook(.w)
      state.addLine(id, ["d4", "Nf6", "c4", "e6", "g3", "d5", "Bg2", "Be7", "Nf3"], .fixed(.book))
      state.addLine(id, ["d4", "d5", "c4", "e6", "Nc3", "Nf6", "Bg5", "Be7", "e3"], .fixed(.book))
    }
    #expect(app.tidyCount == nil, "no count before the first scan")
    let finds = await app.tidyFinds()
    let find = try #require(finds.first)
    #expect(app.tidyCount == finds.count)
    #expect(find.path == ["d4", "d5", "c4", "e6"] && find.mine == "Nc3" && find.suggestion == "g3")
    let before = try #require(app.state.playbooks[id])
    let undo = try app.tidySwitch(find)
    let after = try #require(app.state.playbooks[id])
    #expect(nodeAtLine(after, ["d4", "d5", "c4", "e6", "Nc3"]) == nil)
    #expect(nodeAtLine(after, ["d4", "d5", "c4", "e6", "g3"]) != nil)
    #expect(await app.tidyFinds().count == finds.count - 1)
    app.undo(undo)
    #expect(app.state.playbooks[id] == before)
    #expect(await app.tidyFinds().count == finds.count)
  }
}
