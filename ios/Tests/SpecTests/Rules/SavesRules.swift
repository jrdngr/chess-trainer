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

  /// Rule 2: a save at the current version reads as it is; an older one, or one without a version, is a fresh start.
  @Test func olderSavesAreWiped() throws {
    var state = AppState()
    state.recommend(openingTree(bookIndex))
    state.pawns = 1_234
    let data = try JSONEncoder().encode(state)
    #expect(try decodeSave(data) == state)

    var old = state
    old.version = SAVE_VERSION - 1
    #expect(try decodeSave(JSONEncoder().encode(old)) == AppState())
    #expect(try decodeSave(Data(#"{"pawns":3}"#.utf8)) == AppState())
  }

  /// Rule 3: only a save at the current version that reads whole can be restored.
  @Test func onlyCurrentSavesRestore() throws {
    var state = AppState()
    state.pawns = 50
    #expect(isCurrentSave(try JSONEncoder().encode(state)))
    state.version = SAVE_VERSION - 1
    #expect(!isCurrentSave(try JSONEncoder().encode(state)))
    #expect(!isCurrentSave(Data(#"{"pawns":3}"#.utf8)))
    #expect(!isCurrentSave(Data("not json".utf8)))
  }
}
