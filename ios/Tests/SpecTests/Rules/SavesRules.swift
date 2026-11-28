import ChessCore
import Foundation
@testable import Model
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

  /// Rule 4: a sealed save opens to the save it holds; one edited after sealing, an unsealed
  /// one, or a sealed older one doesn't.
  @Test func onlySealedSavesOpen() throws {
    var state = AppState()
    state.pawns = 50
    let save = try JSONEncoder().encode(state)
    #expect(openSealedSave(sealSave(save)) == save)
    #expect(openSealedSave(save) == nil)

    state.pawns = 99_999
    var file = try #require(JSONSerialization.jsonObject(with: sealSave(save)) as? [String: Any])
    file["save"] = try JSONEncoder().encode(state).base64EncodedString()
    #expect(openSealedSave(try JSONSerialization.data(withJSONObject: file)) == nil)

    state.version = SAVE_VERSION - 1
    #expect(openSealedSave(sealSave(try JSONEncoder().encode(state))) == nil)
  }

  /// Rule 4: a seal names its key; one under a key number the app doesn't have doesn't open,
  /// even when the seal matches that key.
  @Test func aSealUnderAnUnknownKeyDoesntOpen() throws {
    let save = try JSONEncoder().encode(AppState())
    let key = [UInt8](repeating: 7, count: 32)
    let sealed = try #require(JSONSerialization.jsonObject(with: sealSave(save)) as? [String: Any])
    #expect(sealed["key"] as? Int == 1)
    #expect(openSealedSave(sealSave(save, keyNumber: 99, key: key)) == nil)
  }

  /// Rule 4: the seal is HMAC-SHA256 (RFC 4231 test cases 2 and 6, the second with a key
  /// longer than a block).
  @Test func sealIsHmacSha256() {
    let hex = { (bytes: [UInt8]) in bytes.map { String(format: "%02x", $0) }.joined() }
    #expect(
      hex(hmacSHA256(key: Array("Jefe".utf8), message: Array("what do ya want for nothing?".utf8)))
        == "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843")
    #expect(
      hex(hmacSHA256(
        key: [UInt8](repeating: 0xaa, count: 131),
        message: Array("Test Using Larger Than Block-Size Key - Hash Key First".utf8)))
        == "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54")
  }
}
