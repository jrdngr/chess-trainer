import Book
import Foundation

/// The save's version. A save from before it is brought up by `decodeSave`
/// and `migrate`; a new save starts at it.
public let SAVE_VERSION = 3

/// Runs a day of a card's interval stood for, when intervals were days.
let RUNS_PER_DAY: Double = 3

extension AppState {
  /// Brings a save from an older version up to this one, step by step.
  /// Returns whether anything changed.
  /// 1: the Playbook holds only book moves.
  /// 2: schedules count runs, not days.
  /// 3: names are Play, Playbook and Run (done on the JSON by `decodeSave`).
  @discardableResult
  public mutating func migrate(_ index: ReferenceIndex) -> Bool {
    if version >= SAVE_VERSION { return false }
    if version < 1 { removeNonBookMoves(index) }
    if version < 2 { scheduleByRuns() }
    version = SAVE_VERSION
    return true
  }

  /// Card intervals in days become runs. Endgame positions count from the first
  /// Endgame round on: one failed last is due, others wait their interval.
  mutating func scheduleByRuns() {
    for id in cards.keys { cards[id]!.interval *= RUNS_PER_DAY }
    for id in endgames.cards.keys {
      var card = endgames.cards[id]!
      card.interval *= RUNS_PER_DAY
      card.dueRound = endgames.rounds + Int(card.interval.rounded())
      endgames.cards[id] = card
    }
  }
}

/// Reads a saved state, renaming what a save from before version 3 calls
/// Autopilot, Repertoire and Survival first.
public func decodeSave(_ data: Data) throws -> AppState {
  try JSONDecoder().decode(AppState.self, from: renamedSave(data))
}

/// A save from before version 3 with its keys and values under their new names; any other data as it is.
public func renamedSave(_ data: Data) -> Data {
  guard var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return data }
  if (root["version"] as? Int ?? 0) >= 3 { return data }
  root = renameKeys(root, ["repertoireId": "playbookId", "repertoires": "playbooks", "repertoireOrder": "playbookOrder"]) as! [String: Any]
  rename(&root, "survival", "runRecord")
  if var settings = root["settings"] as? [String: Any] {
    settings["play"] = nil
    rename(&settings, "autopilot", "play")
    root["settings"] = settings
  }
  let modes = ["run": "oldPlay", "survival": "run"]
  if var score = root["score"] as? [String: Any] {
    if let global = score["global"] as? [String: Any] { score["global"] = renamedModes(global, modes) }
    if let nodes = score["nodes"] as? [String: Any] { score["nodes"] = nodes.mapValues { ($0 as? [String: Any]).map { renamedModes($0, modes) } ?? $0 } }
    if let rounds = score["rounds"] as? [[String: Any]] { score["rounds"] = rounds.map { renamedValue($0, "mode", modes) } }
    root["score"] = score
  }
  if let games = root["games"] as? [[String: Any]] {
    root["games"] = games.map { renamedValue($0, "mode", ["play": "freePlay", "autopilot": "play", "survival": "run"]) }
  }
  if let events = root["events"] as? [[String: Any]] {
    let places = ["repertoire": "playbook", "play": "freePlay", "autopilot": "play", "survival": "run"]
    root["events"] = events.map { renamedValue($0, "via", places) }
  }
  return (try? JSONSerialization.data(withJSONObject: root)) ?? data
}

private func rename(_ object: inout [String: Any], _ from: String, _ to: String) {
  guard let value = object.removeValue(forKey: from) else { return }
  object[to] = value
}

private func renameKeys(_ value: Any, _ names: [String: String]) -> Any {
  if let object = value as? [String: Any] {
    var out: [String: Any] = [:]
    for (key, inner) in object { out[names[key] ?? key] = renameKeys(inner, names) }
    return out
  }
  if let array = value as? [Any] { return array.map { renameKeys($0, names) } }
  return value
}

private func renamedValue(_ object: [String: Any], _ key: String, _ names: [String: String]) -> [String: Any] {
  guard let value = object[key] as? String, let to = names[value] else { return object }
  var out = object
  out[key] = to
  return out
}

/// Node stats with their per-mode tallies under the modes' new names.
private func renamedModes(_ stats: [String: Any], _ names: [String: String]) -> [String: Any] {
  guard let byMode = stats["byMode"] as? [String: Any] else { return stats }
  var out = stats
  out["byMode"] = Dictionary(uniqueKeysWithValues: byMode.map { (names[$0.key] ?? $0.key, $0.value) })
  return out
}
