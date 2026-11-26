import Foundation
import Testing
import Engine

struct AcknowledgmentsTests {
  static let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../Sources").standardized

  /// Each license the app shows is the vendored LICENSE file, word for word, so an updated vendor copy can't leave a stale notice.
  @Test(arguments: [("Caissa", "Caissa/LICENSE"), ("Caissa-Nets", "Engine/CaissaNet/LICENSE"), ("Fathom", "Fathom/LICENSE")])
  func shownLicenseMatchesTheVendoredFile(name: String, path: String) throws {
    let file = try String(contentsOf: Self.sources.appendingPathComponent(path), encoding: .utf8)
    let shown = try #require(Acknowledgments.all.first { $0.name == name })
    #expect(shown.license == file.trimmingCharacters(in: .whitespacesAndNewlines))
  }

  /// Every vendored LICENSE under Sources has an acknowledgment.
  @Test func everyVendoredLicenseIsShown() throws {
    let found = FileManager.default.enumerator(atPath: Self.sources.path)!.compactMap { $0 as? String }.filter { $0.hasSuffix("LICENSE") }
    #expect(found.count == Acknowledgments.all.count, "\(found)")
  }
}
