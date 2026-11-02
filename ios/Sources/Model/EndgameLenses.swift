import ChessCore

/// The Pawns, Pieces and Kings lenses once a game reaches an endgame: what
/// matters with little material left is passed pawns, active pieces and the
/// kings' squares, not holes, outposts or king safety.

private func promotionRank(_ color: Color) -> Int { color == .w ? 7 : 0 }

/// One of the endgame's passed pawns, with its kind: "C" for connected
/// passers, "P" for a protected passer, "O" for an outside passer.
public struct Passer: Equatable, Sendable {
  public var square: String
  public var color: Color
  public var kind: String?
}

public func passers(_ fen: String) -> [Passer] {
  let grid = Grid(fen)
  let passed = pawnFeatures(fen).filter(\.passed)
  return passed.map { p in
    let (file, rank) = coords(p.square)
    let own = grid.men.filter { $0.type == .p && $0.color == p.color }
    let enemy = grid.men.filter { $0.type == .p && $0.color != p.color }
    let connected = passed.contains { $0.color == p.color && abs(coords($0.square).file - file) == 1 }
    let protected = own.contains { abs($0.file - file) == 1 && $0.rank + forward(p.color) == rank }
    // Outside: every enemy pawn stands three or more files away, all on the same side of it.
    let outside = !enemy.isEmpty && (enemy.allSatisfy { $0.file - file >= 3 } || enemy.allSatisfy { file - $0.file >= 3 })
    let kind = connected ? "C" : protected ? "P" : outside ? "O" : nil
    return Passer(square: p.square, color: p.color, kind: kind)
  }
}

/// The pawn's square: the box the defending king must step into to catch it.
/// From the pawn (a pawn on its first move counts from one rank on) to the
/// queening rank, as far across as it is up, toward the defending king.
public func pawnSquare(_ fen: String, _ square: String, _ color: Color) -> Segment {
  let grid = Grid(fen)
  let (file, rank) = coords(square)
  let start = rel(color, rank) == 1 ? rank + forward(color) : rank
  let queening = promotionRank(color)
  let size = abs(queening - start)
  let king = grid.men.first { $0.type == .k && $0.color != color }
  // A king on the pawn's own file is inside either way: draw toward the side with room.
  let toward = king.flatMap { k -> Int? in k.file == file ? nil : k.file > file ? 1 : -1 } ?? (file < 4 ? 1 : -1)
  let far = min(7, max(0, file + toward * size))
  return Segment(from: sq(file, start), to: sq(far, queening))
}

public func endgamePawnsLens(_ fen: String, _ me: Color) -> LensMarks {
  let grid = Grid(fen)
  var marks = LensMarks()
  var tags: [Tag] = []
  for pawn in pawnFeatures(fen) {
    if pawn.passed {
      tags.append(Tag(square: pawn.square, tone: "good"))
    } else if pawn.isolated || pawn.doubled || pawn.backward {
      tags.append(Tag(square: pawn.square, tone: "bad"))
    }
  }
  let found = passers(fen)
  var boxes: [Segment] = []
  for p in found {
    // The square counts only while the defender has nothing but its king and pawns to stop the pawn.
    let helpers = grid.men.contains { $0.color != p.color && $0.type != .k && $0.type != .p }
    if !helpers { boxes.append(pawnSquare(fen, p.square, p.color)) }
  }
  marks.ghost = true
  marks.tags = tags
  marks.letters = found.compactMap { p in
    p.kind.map { Letter(square: p.square, text: $0, tone: p.color == me ? "mine" : "theirs") }
  }
  marks.boxes = boxes
  return marks
}

/// How central a king stands: "good" in the middle four by four, "passive"
/// one ring out, "bad" on the edge.
private func kingTone(_ man: Man) -> String {
  let off = max(abs(Double(man.file) - 3.5), abs(Double(man.rank) - 3.5))
  return off <= 1.5 ? "good" : off <= 2.5 ? "passive" : "bad"
}

public func endgamePiecesLens(_ fen: String, _ me: Color) -> LensMarks {
  let grid = Grid(fen)
  let passed = pawnFeatures(fen).filter(\.passed).map { p in (file: coords(p.square).file, rank: coords(p.square).rank, color: p.color) }
  var marks = LensMarks()
  marks.tints = controlTints(fen, me)
  var rings: [Ring] = []
  var dots: [String] = []
  var rated: [(square: String, color: Color, tone: String, ratio: Double)] = []
  for a in activity(fen) {
    var tone = a.ratio >= 0.9 ? "good" : a.ratio >= 0.45 ? "passive" : "bad"
    let (file, rank) = coords(a.square)
    if a.type == .r {
      // Behind a passed pawn, either side's, or on the seventh: good. In front of your own passer: bad.
      let behind = passed.contains { p in p.file == file && (rank - p.rank) * forward(p.color) < 0 }
      let blocking = passed.contains { p in p.color == a.color && p.file == file && (rank - p.rank) * forward(p.color) > 0 }
      if behind || rel(a.color, rank) == 6 {
        tone = "good"
      } else if blocking {
        tone = "bad"
      }
    }
    if a.type == .b {
      // A bad bishop: most of its own pawns stand on its color.
      let light = (file + rank) % 2 == 1
      let own = grid.men.filter { $0.type == .p && $0.color == a.color }
      let blockers = own.filter { (($0.file + $0.rank) % 2 == 1) == light }
      if blockers.count >= 2 && blockers.count * 2 > own.count {
        tone = "bad"
        dots += blockers.map(\.square)
      }
    }
    rings.append(Ring(square: a.square, tone: tone))
    rated.append((a.square, a.color, tone, a.ratio))
  }
  for king in grid.men where king.type == .k { rings.append(Ring(square: king.square, tone: kingTone(king))) }
  let order = ["bad": 0, "passive": 1, "good": 2]
  var badges: [String] = []
  for color in [Color.w, .b] {
    let worst = rated.filter { $0.color == color }.min { a, b in
      order[a.tone]! != order[b.tone]! ? order[a.tone]! < order[b.tone]! : a.ratio < b.ratio
    }
    if let worst { badges.append(worst.square) }
  }
  marks.rings = rings
  marks.badges = badges
  marks.dots = dots
  return marks
}

/// The squares a king on any of them wins the pawn's race to queen from,
/// whoever is to move.
public func keySquares(_ square: String, _ color: Color) -> [String] {
  let (file, rank) = coords(square)
  let up = rel(color, rank)
  var ranks: [Int]
  var files = [file - 1, file, file + 1]
  if file == 0 || file == 7 {
    // A rook pawn: only the squares beside its queening square and the one below.
    files = [file == 0 ? 1 : 6]
    ranks = [6, 7]
  } else if up <= 3 {
    ranks = [up + 2]
  } else {
    ranks = [up + 1, up + 2].filter { $0 <= 7 }
  }
  var out: [String] = []
  for r in ranks {
    for f in files where f >= 0 && f <= 7 {
      let r0 = color == .w ? r : 7 - r
      if f == file && r0 == rank { continue }
      out.append(sq(f, r0))
    }
  }
  return out
}

/// Whether the kings stand in opposition: on one line with an odd number of
/// squares between them. The side not to move holds it.
public func opposition(_ fen: String) -> Color? {
  let grid = Grid(fen)
  guard let white = grid.men.first(where: { $0.type == .k && $0.color == .w }),
    let black = grid.men.first(where: { $0.type == .k && $0.color == .b })
  else { return nil }
  let df = abs(white.file - black.file), dr = abs(white.rank - black.rank)
  let onLine = df == 0 || dr == 0 || df == dr
  let distance = max(df, dr)
  guard onLine, distance >= 2, distance % 2 == 0 else { return nil }
  return fenTurn(fen).other
}

public func endgameKingsLens(_ fen: String, _ me: Color) -> LensMarks {
  let grid = Grid(fen)
  let queens = grid.men.contains { $0.type == .q }
  // King safety still matters while a queen is on.
  var marks = queens ? kingsLens(fen, me) : LensMarks()
  var focus = Set(grid.men.filter { $0.type == .k }.map(\.square))
  var tints = marks.tints ?? []
  var onKey: [Color] = []
  let found = pawnFeatures(fen).filter(\.passed)
  for color in [Color.w, .b] {
    // The most advanced passer of each side.
    guard let pawn = found.filter({ $0.color == color }).max(by: { rel(color, coords($0.square).rank) < rel(color, coords($1.square).rank) }),
      let king = grid.men.first(where: { $0.type == .k && $0.color == color })
    else { continue }
    let keys = keySquares(pawn.square, color)
    tints += keys.map { Tint(square: $0, color: color == me ? .blue : .red, strength: 2) }
    focus.insert(pawn.square)
    if keys.contains(king.square) { onKey.append(color) }
  }
  var guides: [Guide] = []
  let pawnsOnly = grid.men.allSatisfy { $0.type == .k || $0.type == .p }
  let held = pawnsOnly ? opposition(fen) : nil
  if held != nil, let mine = grid.men.first(where: { $0.type == .k && $0.color == me }),
    let theirs = grid.men.first(where: { $0.type == .k && $0.color != me })
  {
    guides.append(Guide(from: mine.square, to: theirs.square, tone: "opposition"))
  }
  // A rook whose file stands between the enemy king and its own side's passer cuts the king off.
  for rook in grid.men where rook.type == .r {
    guard let them = grid.men.first(where: { $0.type == .k && $0.color != rook.color }) else { continue }
    let cuts = found.contains { p in
      let file = coords(p.square).file
      return p.color == rook.color && rook.file > min(file, them.file) && rook.file < max(file, them.file)
    }
    if cuts {
      guides.append(Guide(from: sq(rook.file, 0), to: sq(rook.file, 7), tone: "cutoff"))
      focus.insert(rook.square)
    }
  }
  marks.tints = tints
  marks.guides = guides
  if let held {
    marks.caption = held == me ? "You have the opposition" : "They have the opposition"
  } else if onKey.contains(me) {
    marks.caption = "You\u{2019}re on a key square"
  } else if onKey.contains(me.other) {
    marks.caption = "They\u{2019}re on a key square"
  }
  // With queens on, the king-safety marks keep their pieces bright too.
  let occupied = Set(grid.men.map(\.square))
  focus.formUnion(((marks.pips ?? []).map(\.square) + (marks.zone ?? [])).filter { occupied.contains($0) })
  marks.focus = focus.sorted()
  return marks
}
