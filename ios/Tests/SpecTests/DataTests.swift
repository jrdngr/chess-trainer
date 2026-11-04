import ChessCore
import Foundation
import Model
import Testing

/// Golden/cases/functions/data.json: the event log, sync's status line and Reset progress.
@Test func dataCases() throws {
  let at = Date(timeIntervalSince1970: 1_793_448_000).timeIntervalSince1970 * 1000

  /// Steps on an empty Playbook, and the event log they leave, without times or ids.
  func play(_ steps: [JSON]) -> JSON {
    setEventPlace(.repertoire)
    var state = AppState()
    var undo: PlaybookUndo?
    Env.at(at) {
      func rep(_ color: JSON) -> String { state.ensureRepertoire(Color(rawValue: color.string)!) }
      func node(_ color: JSON, _ text: JSON) -> String { nodeAtLine(state.repertoires[rep(color)]!, line(text.string))!.id }
      for step in steps {
        let a = step.array
        switch a[0].string {
        case "add":
          state.addLine(rep(a[1]), line(a[2].string), .fixed(.book), via: a.count > 3 ? EventPlace(rawValue: a[3].string) : nil)
        case "remove": undo = state.removeNode(rep(a[1]), node(a[1], a[2]))
        case "removeLine": undo = state.removeLine(rep(a[1]), node(a[1], a[2]))
        case "removeOpening": state.removeOpening(rep(a[1]), node(a[1], a[2]))
        case "removeRepertoire": state.removeRepertoire(rep(a[1]))
        case "prefer": state.preferMove(rep(a[1]), node(a[1], a[2]))
        case "note": state.annotate(rep(a[1]), node(a[1], a[2]), "a note")
        case "reorder": state.reorder(rep(a[1]), node(a[1], a[2]), a[3].int)
        case "tidySwitch": undo = state.tidySwitch(rep(a[1]), node(a[1], a[2]), a[3].string)
        case "tidyKeep": state.tidyKeep(rep(a[1]), node(a[1], a[2]))
        case "tidyRemove": undo = state.tidyRemove(rep(a[1]), node(a[1], a[2]))
        case "undo":
          if let u = undo { state.undo(u) }
          undo = nil
        case "log":
          let e = a[1]
          state.logEvent(AppEvent(
            kind: e["kind"].string, color: e["color"].stringOrNil.flatMap(Color.init(rawValue:)), line: e["line"].stringOrNil,
            picked: e["picked"].stringOrNil, offered: e["offered"] == .null ? nil : e["offered"].array.map(\.string),
            from: e["from"].stringOrNil))
        default: Issue.record("unknown step \(a[0])")
        }
      }
    }
    return obj([
      "events": state.events.map(eventJSON).json,
      "playbook": state.repertoireList.map { "\($0.color.rawValue): \($0.nodes.count) moves" },
    ])
  }

  func rep(_ lines: [JSON]) -> Repertoire {
    var out = createRepertoire("White", .w, "rep_w")
    for l in lines { out = addLine(out, line(l.string), .fixed(.seed)).rep }
    return out
  }

  try check("data", [
    "events.log": { play($0[0].array) },
    "events.appendEvent": { a in
      var events: [AppEvent] = []
      for i in 1...a[0].int {
        events = appendEvent(events, AppEvent(kind: "growth-undo", via: .growth, color: .w, line: "\(i)", all: false), Double(i))
      }
      return obj(["kept": events.count, "first": events.first?.at, "last": events.last?.at, "cap": EVENT_CAP])
    },
    "events.normalizeEvents": { a in
      guard case .array(let list) = a[0] else { return 0.json }
      return normalizeEvents(list.map { _ in AppEvent(kind: "add") }).count.json
    },
    "events.removedBetween": { a in
      let before = rep(a[0].array)
      let after = pruneLine(before, nodeAtLine(before, line(a[1].string))!.id)
      let r = removedBetween(before, after)
      return obj(["removed": r.removed, "count": r.count])
    },
  ])
}
