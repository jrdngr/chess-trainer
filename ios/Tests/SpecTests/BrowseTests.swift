import ChessCore
import Foundation
import Model
import Shared
import Testing

/// The browse functions in spec/cases/functions/picker.json, set up as
/// `src/spec/cases/picker.cases.ts` sets them up.
@Test func browse() throws {
  let tree = openingTree(bookIndex)
  let catalog = pickerCatalog(tree)
  let books = playbooks()
  try check("picker", [
    "browse.shortName": { shortName($0[0].string).json },
    "browse.lineName": { lineName(tree, catalog, line($0[0].string)).json },
    "browse.bookItems": { _ in written(bookItems(catalog)).json },
    "browse.shelfRows": { a in written(shelfRows(catalog, SHELVES.first { $0.id == a[0].string }!).map { .row($0) }, 0).json },
    "browse.myLines": { a in written(myLines(books[a[0].string]!, bookIndex, tree, a[1].strings), 2).json },
    "browse.recentItems": { a in
      let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 18))!.timeIntervalSince1970 * 1000
      var score = EMPTY_SCORE
      for played in a[0].array {
        var stats = emptyNodeStats()
        stats.lastAt = now - played[1].number * 3_600_000
        score.nodes[played[0].string] = stats
      }
      return written(recentItems(tree, catalog, score, now), 0).json
    },
    "browse.searchItems": { a in
      written(searchItems(a[0].string, books[a[1].string]!, bookIndex, tree, catalog, 12), 0).json
    },
    "browse.nextMoves": { a in
      nextMoves(bookIndex, tree, catalog, line(a[0].string), repMoves(books[a[1].string]!))
        .map { "\($0.label) \(JS.string($0.share)) \($0.name)\($0.mine ? " *" : "")" }.json
    },
    "browse.suggestions": { a in written(suggestions(books[a[0].string]!, bookIndex, tree, catalog, 15).map { .row($0) }, 0).json },
    "browse.mixLabels": { a in
      let rows = a[0].strings.enumerated().map { i, kind in
        BrowseRow(key: "\(i)", label: "\(i)", sans: [], side: .w, why: ("", ReasonKind(rawValue: kind)!))
      }
      return mixLabels(rows).map { "\($0.key):\($0.why!.kind.rawValue)" }.json
    },
  ], only: [
    "browse.shortName", "browse.lineName", "browse.bookItems", "browse.shelfRows", "browse.myLines",
    "browse.recentItems", "browse.searchItems", "browse.nextMoves", "browse.suggestions", "browse.mixLabels",
  ])
}

private func playbooks() -> [String: [Repertoire]] {
  [
    "empty": [],
    "e4 player": [
      rep(.w, ["e4 e5 Nf3 Nc6 Bb5 a6 Ba4", "e4 c5 Nf3 d6 d4 cxd4 Nxd4", "e4 e6 d4 d5 Nc3"]),
      rep(.b, [
        "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6",
        "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Be3 e5",
        "d4 Nf6 c4 g6 Nc3 Bg7 e4 d6",
      ]),
    ],
    "d4 player": [
      rep(.w, ["d4 d5 c4 e6 Nc3 Nf6 Bg5", "d4 d5 c4 c6 Nf3 Nf6 Nc3", "d4 Nf6 c4 e6 Nc3 Bb4 Qc2"]),
      rep(.b, ["e4 c6 d4 d5 e5 Bf5", "e4 c6 d4 d5 Nc3 dxe4 Nxe4 Bf5"]),
    ],
  ]
}

/// A list as rows, opened to a depth: heads as "# Head", rows as "label [side] moves", children indented.
private func written(_ items: [BrowseItem], _ depth: Int = 1, _ indent: String = "") -> [String] {
  var out: [String] = []
  for item in items {
    switch item {
    case .head(let head):
      out.append("\(indent)# \(head)")
    case .row(let row):
      out.append(indent + written(row))
      if depth > 0, let open = row.open { out += written(open(), depth - 1, indent + "  ") }
    }
  }
  return out
}

private func written(_ r: BrowseRow) -> String {
  let why = r.why.map { " (\($0.kind.rawValue): \($0.text))" } ?? ""
  return "\(r.label) [\(r.side.rawValue)] \(r.sans.joined(separator: " "))\(why)\(r.open != nil ? " ›" : "")"
}
