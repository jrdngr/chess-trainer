import Foundation
import Model

/// Debug hooks for screenshots. `OPEN_IMPORT=1` opens Import games over the
/// Playbook tab; `IMPORT_SAMPLE=1` loads the sample archive (the review);
/// `IMPORT_SHEET=pgn` opens Paste PGN; `IMPORT_ERROR=blocked|network` shows
/// the banner; `IMPORT_FINDING=n` opens the review's nth finding.
enum ImportDebug {
  static var env: [String: String] {
    #if DEBUG
      ProcessInfo.processInfo.environment
    #else
      [:]
    #endif
  }

  static var open: Bool { env["OPEN_IMPORT"] == "1" }
  static var finding: Int? { env["IMPORT_FINDING"].flatMap(Int.init) }
}

extension ImportView {
  func debugOpen() {
    let env = ImportDebug.env
    if env["IMPORT_SAMPLE"] == "1", games.isEmpty { loadSample() }
    if env["IMPORT_SHEET"] == "pgn" { pgnOpen = true }
    switch env["IMPORT_ERROR"] {
    case "blocked": error = ("", true)
    case "network": error = ("No Lichess account called \"\(trimmed)\".", false)
    default: break
    }
  }
}
