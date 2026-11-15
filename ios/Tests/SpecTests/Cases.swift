import Foundation
import Testing

/// The golden cases in `Golden/`: recorded answers the model must keep
/// giving. Each function case is `{ args, out }`.
enum Cases {
  /// `ios/Tests/SpecTests/Golden`.
  static let golden = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().appendingPathComponent("Golden")

  /// The book the app ships, `ios/Resources/book.json`.
  static let book = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Resources/book.json")

  static func file(_ area: String) throws -> [String: [(args: [JSON], out: JSON)]] {
    let url = golden.appendingPathComponent("cases/functions/\(area).json")
    let json = try JSON.parse(Data(contentsOf: url))
    var out: [String: [(args: [JSON], out: JSON)]] = [:]
    for fn in json["functions"].array {
      out[fn["fn"].string] = fn["cases"].array.map { ($0["args"].array, $0["out"]) }
    }
    return out
  }

  /// With `GOLDEN_WRITE=1`, what the ports answered is written to `ios/.golden-out/`, for
  /// `Golden/rewrite.py` to put in the cases when a change in behavior is intended.
  static let writing = ProcessInfo.processInfo.environment["GOLDEN_WRITE"] == "1"

  static func write(_ name: String, _ value: JSON) {
    let dir = golden.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent(".golden-out")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let data = try? JSONSerialization.data(withJSONObject: value.anyValue, options: [.fragmentsAllowed])
    try? data?.write(to: dir.appendingPathComponent("\(name).json"))
  }
}

/// Runs every case of the named functions in one area through their Swift
/// ports, and fails on any the port answers differently, or doesn't port.
func check(_ area: String, _ ports: [String: ([JSON]) -> JSON], only: Set<String>? = nil) throws {
  let file = try Cases.file(area)
  let wanted = only ?? Set(file.keys)
  var written: [String: JSON] = [:]
  defer { if Cases.writing { Cases.write("functions-\(area)", .object(written)) } }
  for fn in wanted.sorted() {
    guard let cases = file[fn] else {
      Issue.record("\(area): no cases for \(fn)")
      continue
    }
    guard let port = ports[fn] else {
      Issue.record("\(area): \(fn) is not ported")
      continue
    }
    var failures = 0
    var outs: [JSON] = []
    defer { written[fn] = .array(outs) }
    for (i, c) in cases.enumerated() {
      let got = port(c.args)
      outs.append(got)
      if !matches(got, c.out) {
        failures += 1
        if failures <= 3 {
          Issue.record("\(fn) case \(i) args \(JSON.array(c.args))\n  expected \(c.out)\n  got      \(got)")
        }
      }
    }
    if failures > 3 { Issue.record("\(fn): \(failures) of \(cases.count) cases differ") }
  }
}
