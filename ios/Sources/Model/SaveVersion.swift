import Foundation

/// The save's version. A new save starts at it; a save from an older version is wiped.
public let SAVE_VERSION = 7

/// Reads a saved state. A save from an older version reads as a fresh start: it is not brought up to date.
public func decodeSave(_ data: Data) throws -> AppState {
  struct Stamp: Decodable { var version: Int? }
  guard let version = try JSONDecoder().decode(Stamp.self, from: data).version, version >= SAVE_VERSION else { return AppState() }
  return try JSONDecoder().decode(AppState.self, from: data)
}

/// Whether a save is at the current version and reads whole: one a restore can bring back.
/// An older save would only open as a fresh start.
public func isCurrentSave(_ data: Data) -> Bool {
  struct Stamp: Decodable { var version: Int? }
  guard let version = (try? JSONDecoder().decode(Stamp.self, from: data))?.version, version >= SAVE_VERSION else { return false }
  return (try? JSONDecoder().decode(AppState.self, from: data)) != nil
}
