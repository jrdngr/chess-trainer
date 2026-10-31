import ChessCore
import Shared

/// Reading a middlegame position for the lenses, from the board alone.
/// `src/model/boardHints.ts`. Colors are "mine" and "theirs" from your side.

public enum LensKind: String, Sendable, Codable, CaseIterable {
  case pawns, pieces, space, kings, threats
}

public let LENSES: [(kind: LensKind, label: String)] = [
  (.pawns, "Pawns"), (.pieces, "Pieces"), (.space, "Space"), (.kings, "Kings"), (.threats, "Threats"),
]

public enum TintColor: String, Sendable, Codable {
  case blue, red, purple, purpleBlue = "purple-blue", purpleRed = "purple-red", green, amber
}
public enum KingGrade: String, Sendable, Codable { case safe, exposed, attacked }
public enum Side: String, Sendable, Codable { case mine, theirs }

public struct Tint: Equatable, Sendable, Codable { public var square: String; public var color: TintColor; public var strength: Int }
public struct Tag: Equatable, Sendable, Codable { public var square: String; public var tone: String }
public struct Ring: Equatable, Sendable, Codable { public var square: String; public var tone: String }
public struct Star: Equatable, Sendable, Codable { public var square: String; public var side: Side }
public struct Pip: Equatable, Sendable, Codable { public var square: String; public var attackers: Int; public var defenders: Int }
public struct Shield: Equatable, Sendable, Codable { public var square: String; public var grade: KingGrade }
public struct Segment: Equatable, Sendable, Codable { public var from: String; public var to: String }
public struct LensArrow: Equatable, Sendable, Codable { public var from: String; public var to: String; public var tone: String }

/// What a lens draws. A lens fills in what it shows.
public struct LensMarks: Equatable, Sendable, Codable {
  public var ghost: Bool?
  public var tints: [Tint]?
  public var tags: [Tag]?
  public var dots: [String]?
  public var rings: [Ring]?
  public var stars: [Star]?
  public var zone: [String]?
  public var pips: [Pip]?
  public var shields: [Shield]?
  public var emptyPawns: [String]?
  public var lines: [Segment]?
  public var arrows: [LensArrow]?
  public var caption: String?
  public init() {}
}

/* ── the board as a grid ── */

struct Man: Equatable {
  var square: String
  var type: PieceType
  var color: Color
  var file: Int
  var rank: Int
}

struct Grid {
  var men: [Man]
  private var cells: [Man?]

  init(_ fen: String) {
    var cells = [Man?](repeating: nil, count: 64)
    var men: [Man] = []
    for piece in piecesFromFen(fen) {
      let (file, rank) = coords(piece.square)
      let man = Man(square: piece.square, type: piece.type, color: piece.color, file: file, rank: rank)
      cells[rank * 8 + file] = man
      men.append(man)
    }
    self.men = men
    self.cells = cells
  }

  /// Off the board is `.some(nil)`'s outer nil: `nil` off the board, `.some(nil)` empty.
  func at(_ file: Int, _ rank: Int) -> Man?? {
    file < 0 || file > 7 || rank < 0 || rank > 7 ? nil : .some(cells[rank * 8 + file])
  }

  func man(_ file: Int, _ rank: Int) -> Man? { at(file, rank) ?? nil }
}

func coords(_ square: String) -> (file: Int, rank: Int) {
  let u = Array(square.utf8)
  return (Int(u[0]) - 97, Int(u[1]) - 49)
}

func sq(_ file: Int, _ rank: Int) -> String {
  String(UnicodeScalar(UInt8(97 + file))) + String(rank + 1)
}

/// A rank counted from a side's own back rank, 0...7.
private func rel(_ color: Color, _ rank: Int) -> Int { color == .w ? rank : 7 - rank }
private func forward(_ color: Color) -> Int { color == .w ? 1 : -1 }

private let KNIGHT = [(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)]
private let KING = [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)]
private let DIAG = [(1, 1), (1, -1), (-1, 1), (-1, -1)]
private let ORTHO = [(1, 0), (-1, 0), (0, 1), (0, -1)]

/// Every square a man attacks. With `xray`, a line runs on through a friendly piece moving along it.
private func attacksOf(_ grid: Grid, _ man: Man, _ xray: Bool = false) -> [(file: Int, rank: Int)] {
  var out: [(file: Int, rank: Int)] = []
  func step(_ df: Int, _ dr: Int) {
    let f = man.file + df, r = man.rank + dr
    if f >= 0 && f < 8 && r >= 0 && r < 8 { out.append((f, r)) }
  }
  func ride(_ dirs: [(Int, Int)]) {
    for (df, dr) in dirs {
      let diagonal = df != 0 && dr != 0
      var f = man.file + df, r = man.rank + dr
      while f >= 0 && f < 8 && r >= 0 && r < 8 {
        out.append((f, r))
        let there = grid.man(f, r)
        let along = xray && there != nil && there!.color == man.color && (there!.type == .q || there!.type == (diagonal ? .b : .r))
        if there != nil && !along { break }
        f += df
        r += dr
      }
    }
  }
  switch man.type {
  case .p:
    step(-1, forward(man.color))
    step(1, forward(man.color))
  case .n: for (df, dr) in KNIGHT { step(df, dr) }
  case .k: for (df, dr) in KING { step(df, dr) }
  case .b: ride(DIAG)
  case .r: ride(ORTHO)
  case .q:
    ride(DIAG)
    ride(ORTHO)
  }
  return out
}

/// Who attacks each square: index rank * 8 + file.
private func attackMap(_ grid: Grid) -> [[Man]] {
  var map = [[Man]](repeating: [], count: 64)
  for man in grid.men {
    for (file, rank) in attacksOf(grid, man, true) { map[rank * 8 + file].append(man) }
  }
  return map
}

private func by(_ list: [Man], _ color: Color) -> [Man] { list.filter { $0.color == color } }
private func cheapest(_ list: [Man]) -> Int {
  list.map { $0.type == .k ? 100 : PIECE_VALUES[$0.type]! }.min() ?? Int.max
}

/* ── pawns ── */

public struct PawnInfo: Equatable, Sendable {
  public var square: String
  public var color: Color
  public var isolated: Bool
  public var doubled: Bool
  public var backward: Bool
  public var passed: Bool
}

private func pawnsOf(_ grid: Grid, _ color: Color) -> [Man] {
  grid.men.filter { $0.type == .p && $0.color == color }
}

public func pawnFeatures(_ fen: String) -> [PawnInfo] {
  let grid = Grid(fen)
  var out: [PawnInfo] = []
  for color in [Color.w, .b] {
    let mine = pawnsOf(grid, color)
    let theirs = pawnsOf(grid, color.other)
    for pawn in mine {
      let here = rel(color, pawn.rank)
      let neighbours = mine.filter { abs($0.file - pawn.file) == 1 }
      let isolated = neighbours.isEmpty
      let doubled = mine.contains { $0 != pawn && $0.file == pawn.file }
      let passed = !theirs.contains { abs($0.file - pawn.file) <= 1 && rel(color, $0.rank) > here }
      let stop = (file: pawn.file, rank: pawn.rank + forward(color))
      let stopGuarded = theirs.contains { abs($0.file - stop.file) == 1 && $0.rank + forward(color.other) == stop.rank }
      let backward = !isolated && !passed && neighbours.allSatisfy { rel(color, $0.rank) > here } && stopGuarded
      out.append(PawnInfo(square: pawn.square, color: color, isolated: isolated, doubled: doubled, backward: backward, passed: passed))
    }
  }
  return out
}

/// Holes in one side's camp: third and fourth ranks, b to g files, no pawn of its can guard again.
public func holes(_ fen: String, _ color: Color) -> [String] {
  let grid = Grid(fen)
  let mine = pawnsOf(grid, color)
  var out: [String] = []
  for file in 1...6 {
    for r in [2, 3] {
      let rank = color == .w ? r : 7 - r
      if let man = grid.man(file, rank), man.type == .p, man.color == color { continue }
      if !mine.contains(where: { abs($0.file - file) == 1 && rel(color, $0.rank) < r }) { out.append(sq(file, rank)) }
    }
  }
  return out
}

/// The same position with this side to move; nil when the other side would be in check.
public func asMover(_ fen: String, _ color: Color) -> String? {
  let parts = fen.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
  if parts[1] == color.rawValue { return fen }
  let flipped = [parts[0], color.rawValue, parts[2], "-", "0", parts.count > 5 ? parts[5] : "1"].joined(separator: " ")
  let grid = Grid(flipped)
  let map = attackMap(grid)
  guard let king = grid.men.first(where: { $0.type == .k && $0.color == color.other }) else { return nil }
  if !by(map[king.rank * 8 + king.file], color).isEmpty { return nil }
  return flipped
}

/// The pawn moves that are breaks: a capture of a pawn, or a push that attacks one. UCI.
public func breakCandidates(_ fen: String, _ color: Color) -> [String] {
  let grid = Grid(fen)
  return legalMoves(fen)
    .filter { move in
      let from = coords(move.from)
      guard let man = grid.man(from.file, from.rank), man.type == .p, man.color == color else { return false }
      let (file, rank) = coords(move.to)
      if let victim = grid.man(file, rank), victim.type == .p { return true }
      let ahead = rank + forward(color)
      return [file - 1, file + 1].contains { f in
        guard let target = grid.man(f, ahead) else { return false }
        return target.type == .p && target.color != color
      }
    }
    .map { "\($0.from)\($0.to)\($0.promotion?.rawValue ?? "")" }
}

public func pawnsLens(_ fen: String) -> LensMarks {
  var marks = LensMarks()
  var tags: [Tag] = []
  for pawn in pawnFeatures(fen) {
    if pawn.passed {
      tags.append(Tag(square: pawn.square, tone: "good"))
    } else if pawn.isolated || pawn.doubled || pawn.backward {
      tags.append(Tag(square: pawn.square, tone: "bad"))
    }
  }
  marks.ghost = true
  marks.tags = tags
  marks.dots = holes(fen, .w) + holes(fen, .b)
  marks.caption = structureOf(fen).map(structureLabel)
  return marks
}

/* ── pieces ── */

private let TYPICAL_MOBILITY: [PieceType: Double] = [.n: 5, .b: 6, .r: 7, .q: 13]

public struct Activity: Equatable, Sendable {
  public var square: String
  public var color: Color
  public var type: PieceType
  /// Safe squares reached over what is typical: 1 is normal.
  public var ratio: Double
}

/// How active each knight, bishop, rook and queen is.
public func activity(_ fen: String) -> [Activity] {
  let grid = Grid(fen)
  func pawnAttacks(_ color: Color) -> Set<Int> {
    var set = Set<Int>()
    for pawn in pawnsOf(grid, color) { for (file, rank) in attacksOf(grid, pawn) { set.insert(rank * 8 + file) } }
    return set
  }
  let guardedBy: [Color: Set<Int>] = [.w: pawnAttacks(.w), .b: pawnAttacks(.b)]
  var out: [Activity] = []
  for man in grid.men {
    guard let typical = TYPICAL_MOBILITY[man.type] else { continue }
    let reach = attacksOf(grid, man).filter { file, rank in
      if let there = grid.man(file, rank), there.color == man.color { return false }
      return !guardedBy[man.color.other]!.contains(rank * 8 + file)
    }.count
    out.append(Activity(square: man.square, color: man.color, type: man.type, ratio: Double(reach) / typical))
  }
  return out
}

/// Outposts: fourth to sixth ranks, b to g, no enemy pawn can attack, one of yours guards.
public func outposts(_ fen: String, _ color: Color) -> [String] {
  let grid = Grid(fen)
  let theirs = pawnsOf(grid, color.other)
  var out: [String] = []
  for file in 1...6 {
    for r in [3, 4, 5] {
      let rank = color == .w ? r : 7 - r
      if let man = grid.man(file, rank), man.type == .p { continue }
      if theirs.contains(where: { abs($0.file - file) == 1 && rel(color, $0.rank) > r }) { continue }
      if pawnsOf(grid, color).contains(where: { abs($0.file - file) == 1 && $0.rank + forward(color) == rank }) {
        out.append(sq(file, rank))
      }
    }
  }
  return out
}

/// The shortest knight route from one of your knights to a square, at most three hops.
private func knightRoute(_ grid: Grid, _ color: Color, _ target: String) -> [String]? {
  let goal = coords(target)
  var best: [String]?
  for knight in grid.men where knight.type == .n && knight.color == color {
    if knight.file == goal.file && knight.rank == goal.rank { return nil }
    var seen: [Int: Int] = [:]
    let start = knight.rank * 8 + knight.file
    seen[start] = -1
    var frontier = [start]
    var hop = 0
    while hop < 3 && !frontier.isEmpty {
      var next: [Int] = []
      for at in frontier {
        let f0 = at % 8, r0 = at / 8
        for (df, dr) in KNIGHT {
          let f = f0 + df, r = r0 + dr
          guard let there = grid.at(f, r) else { continue }
          if let man = there, man.color == color { continue }
          let key = r * 8 + f
          if seen[key] != nil { continue }
          seen[key] = at
          next.append(key)
        }
      }
      let goalKey = goal.rank * 8 + goal.file
      if seen[goalKey] != nil {
        var path: [String] = []
        var k = goalKey
        while k != -1 {
          path.insert(sq(k % 8, k / 8), at: 0)
          k = seen[k]!
        }
        if best == nil || path.count < best!.count { best = path }
        break
      }
      frontier = next
      hop += 1
    }
  }
  return best
}

public func piecesLens(_ fen: String, _ me: Color) -> LensMarks {
  let grid = Grid(fen)
  let acts = activity(fen)
  var marks = LensMarks()
  marks.tints = acts.map { Tint(square: $0.square, color: $0.ratio >= 0.9 ? .green : $0.ratio >= 0.45 ? .amber : .red, strength: 2) }
  var rings: [Ring] = []
  for color in [Color.w, .b] {
    let own = acts.filter { $0.color == color }
    guard let firstOwn = own.first else { continue }
    let worst = own.dropFirst().reduce(firstOwn) { $1.ratio < $0.ratio ? $1 : $0 }
    rings.append(Ring(square: worst.square, tone: "bad"))
  }
  var stars: [Star] = []
  for color in [Color.w, .b] {
    for square in outposts(fen, color) { stars.append(Star(square: square, side: color == me ? .mine : .theirs)) }
  }
  // Routes for your own knights only, to the two nearest outposts.
  let routes = outposts(fen, me)
    .compactMap { knightRoute(grid, me, $0) }
    .filter { $0.count > 1 }
    .jsSorted { cmp($0.count, $1.count) }
    .prefix(2)
  var arrows: [LensArrow] = []
  for path in routes { for i in 1..<path.count { arrows.append(LensArrow(from: path[i - 1], to: path[i], tone: "route")) } }
  marks.rings = rings
  marks.stars = stars
  marks.arrows = arrows
  return marks
}

/// How one of your pieces gets to a plan's square, as route arrows. `done` when one stands there.
public func goalRoute(_ fen: String, _ me: Color, _ goal: Goal) -> (done: Bool, arrows: [Segment]) {
  let grid = Grid(fen)
  let target = coords(goal.to)
  let there = grid.man(target.file, target.rank)
  if let there, there.color == me, there.type == goal.piece { return (true, []) }
  if let there, there.color == me { return (false, []) }
  func pairs(_ path: [String]) -> [Segment] { path.indices.dropFirst().map { Segment(from: path[$0 - 1], to: path[$0]) } }
  if goal.piece == .n {
    return (false, knightRoute(grid, me, goal.to).map(pairs) ?? [])
  }
  if goal.piece == .p {
    // The nearest pawn behind the square on its file, with nothing in the way.
    let behind = pawnsOf(grid, me)
      .filter { $0.file == target.file && rel(me, $0.rank) < rel(me, target.rank) }
      .jsSorted { cmp(rel(me, $1.rank), rel(me, $0.rank)) }
      .first
    guard let behind, there == nil else { return (false, []) }
    var r = behind.rank + forward(me)
    while r != target.rank {
      if grid.man(target.file, r) != nil { return (false, []) }
      r += forward(me)
    }
    return (false, [Segment(from: behind.square, to: goal.to)])
  }
  let reach = grid.men.first { man in
    man.color == me && man.type == goal.piece && attacksOf(grid, man).contains { $0.file == target.file && $0.rank == target.rank }
  }
  return (false, reach.map { [Segment(from: $0.square, to: goal.to)] } ?? [])
}

/* ── space ── */

public struct Control: Equatable, Sendable {
  public var square: String
  /// "mine", "theirs", "both", or nil.
  public var holder: String?
  public var margin: Int
  public var lean: Side?
}

public func control(_ fen: String, _ me: Color) -> [Control] {
  let grid = Grid(fen)
  let map = attackMap(grid)
  var out: [Control] = []
  for rank in 0..<8 {
    for file in 0..<8 {
      let all = map[rank * 8 + file]
      let mine = by(all, me), theirs = by(all, me.other)
      let square = sq(file, rank)
      if mine.isEmpty && theirs.isEmpty {
        out.append(Control(square: square, holder: nil, margin: 0, lean: nil))
      } else if mine.count != theirs.count {
        out.append(Control(square: square, holder: mine.count > theirs.count ? "mine" : "theirs", margin: abs(mine.count - theirs.count), lean: nil))
      } else {
        let a = cheapest(mine), b = cheapest(theirs)
        out.append(Control(square: square, holder: "both", margin: 0, lean: a < b ? .mine : b < a ? .theirs : nil))
      }
    }
  }
  return out
}

/// Squares each side holds outright in the other's half.
public func spaceCount(_ fen: String, _ me: Color) -> (mine: Int, theirs: Int) {
  var mine = 0, theirs = 0
  for c in control(fen, me) {
    let rank = coords(c.square).rank
    if c.holder == "mine" && rel(me, rank) >= 4 { mine += 1 }
    if c.holder == "theirs" && rel(me.other, rank) >= 4 { theirs += 1 }
  }
  return (mine, theirs)
}

public func spaceLens(_ fen: String, _ me: Color) -> LensMarks {
  var tints: [Tint] = []
  for c in control(fen, me) {
    guard let holder = c.holder else { continue }
    if holder == "both" {
      tints.append(Tint(square: c.square, color: c.lean == .mine ? .purpleBlue : c.lean == .theirs ? .purpleRed : .purple, strength: 1))
    } else {
      tints.append(Tint(square: c.square, color: holder == "mine" ? .blue : .red, strength: min(3, c.margin)))
    }
  }
  let count = spaceCount(fen, me)
  var marks = LensMarks()
  marks.tints = tints
  marks.caption = "Space \u{00b7} you \(count.mine) \u{2013} \(count.theirs) them"
  return marks
}

/* ── kings ── */

public struct KingReport: Equatable, Sendable {
  public var color: Color
  public var square: String
  public var zone: [String]
  public var pips: [Pip]
  public var missingShield: [String]
  public var lines: [Segment]
  public var score: Double
  public var grade: KingGrade
}

public let KING_GRADE_TEXT: [KingGrade: String] = [.safe: "Safe", .exposed: "Exposed", .attacked: "Under attack"]

public func kingReport(_ fen: String, _ color: Color) -> KingReport? {
  let grid = Grid(fen)
  let map = attackMap(grid)
  guard let king = grid.men.first(where: { $0.type == .k && $0.color == color }) else { return nil }
  let enemy = color.other
  let dir = forward(color)

  var zoneCells: [(file: Int, rank: Int)] = []
  for df in -1...1 {
    for dr in -1...2 {
      // Two ranks out only in front of the king.
      let r = king.rank + dr * dir, f = king.file + df
      if f < 0 || f > 7 || r < 0 || r > 7 { continue }
      zoneCells.append((f, r))
    }
  }
  var pips: [Pip] = []
  var attacks = 0, defence = 0
  for (file, rank) in zoneCells {
    let here = map[rank * 8 + file]
    let attackers = by(here, enemy).count
    let defenders = by(here, color).filter { $0.type != .k }.count
    attacks += attackers
    defence += defenders
    if attackers > 0 { pips.append(Pip(square: sq(file, rank), attackers: attackers, defenders: defenders)) }
  }

  var missingShield: [String] = []
  let pawns = pawnsOf(grid, color)
  if rel(color, king.rank) <= 1 {
    for f in (king.file - 1)...(king.file + 1) where f >= 0 && f <= 7 {
      let near = pawns.contains { $0.file == f && rel(color, $0.rank) > rel(color, king.rank) && rel(color, $0.rank) <= rel(color, king.rank) + 2 }
      if !near { missingShield.append(sq(f, king.rank + dir)) }
    }
  }

  var lines: [Segment] = []
  let heavy = grid.men.contains { $0.color == enemy && ($0.type == .r || $0.type == .q) }
  if heavy {
    for f in (king.file - 1)...(king.file + 1) where f >= 0 && f <= 7 {
      let shut = pawns.contains { $0.file == f && rel(color, $0.rank) > rel(color, king.rank) }
      if !shut { lines.append(Segment(from: sq(f, color == .w ? 7 : 0), to: sq(f, king.rank))) }
    }
  }
  for (df, dr) in [(1, dir), (-1, dir)] {
    var f = king.file + df, r = king.rank + dr
    while f >= 0 && f < 8 && r >= 0 && r < 8 {
      if let man = grid.man(f, r) {
        if man.color == enemy && (man.type == .b || man.type == .q) { lines.append(Segment(from: man.square, to: king.square)) }
        break
      }
      f += df
      r += dr
    }
  }

  let inCheck = !by(map[king.rank * 8 + king.file], enemy).isEmpty
  let score = Double(attacks + 2 * missingShield.count + 2 * lines.count) - Double(defence) / 2
  let grade: KingGrade = inCheck || score >= 7 ? .attacked : score >= 3 ? .exposed : .safe
  return KingReport(
    color: color, square: king.square, zone: zoneCells.map { sq($0.file, $0.rank) }, pips: pips,
    missingShield: missingShield, lines: lines, score: score, grade: grade)
}

public func kingsLens(_ fen: String, _ me: Color) -> LensMarks {
  var marks = LensMarks()
  var zone: [String] = [], pips: [Pip] = [], shields: [Shield] = [], empty: [String] = [], lines: [Segment] = []
  var grades: [Side: KingGrade] = [:]
  for color in [Color.w, .b] {
    guard let report = kingReport(fen, color) else { continue }
    zone += report.zone
    pips += report.pips
    shields.append(Shield(square: report.square, grade: report.grade))
    empty += report.missingShield
    lines += report.lines
    grades[color == me ? .mine : .theirs] = report.grade
  }
  marks.zone = zone
  marks.pips = pips
  marks.shields = shields
  marks.emptyPawns = empty
  marks.lines = lines
  if let mine = grades[.mine], let theirs = grades[.theirs] {
    marks.caption = "You: \(KING_GRADE_TEXT[mine]!) \u{00b7} Them: \(KING_GRADE_TEXT[theirs]!)"
  }
  return marks
}

/* ── threats ── */

public struct Loose: Equatable, Sendable {
  public var square: String
  public var color: Color
  /// "hanging" or "cheaper".
  public var kind: String
}

/// Every piece that is hanging, or attacked by something worth less.
public func loosePieces(_ fen: String) -> [Loose] {
  let grid = Grid(fen)
  let map = attackMap(grid)
  var out: [Loose] = []
  for man in grid.men {
    let here = map[man.rank * 8 + man.file]
    let attackers = by(here, man.color.other)
    if attackers.isEmpty { continue }
    if man.type == .k {
      out.append(Loose(square: man.square, color: man.color, kind: "hanging"))
      continue
    }
    if by(here, man.color).isEmpty {
      out.append(Loose(square: man.square, color: man.color, kind: "hanging"))
    } else if cheapest(attackers) < PIECE_VALUES[man.type]! {
      out.append(Loose(square: man.square, color: man.color, kind: "cheaper"))
    }
  }
  return out
}

private func attackPairs(_ fen: String, _ attacker: Color) -> [Segment] {
  let grid = Grid(fen)
  var out: [Segment] = []
  for man in grid.men where man.color == attacker {
    for (file, rank) in attacksOf(grid, man) {
      if let target = grid.man(file, rank), target.color != attacker { out.append(Segment(from: man.square, to: target.square)) }
    }
  }
  return out
}

/// What the opponent's last move newly threatens.
public func newThreats(_ prevFen: String, _ fen: String, _ me: Color) -> [Segment] {
  let loose = Set(loosePieces(fen).filter { $0.color == me }.map(\.square))
  let before = Set(attackPairs(prevFen, me.other).map { $0.from + $0.to })
  return attackPairs(fen, me.other).filter { loose.contains($0.to) && !before.contains($0.from + $0.to) }
}

public func threatsLens(_ fen: String, _ me: Color, _ prevFen: String? = nil) -> LensMarks {
  let loose = loosePieces(fen)
  var marks = LensMarks()
  marks.rings = loose.map { Ring(square: $0.square, tone: $0.kind == "hanging" ? "bad" : "warn") }
  let turn = String(fen.split(separator: " ")[1])
  marks.arrows = prevFen != nil && turn == me.rawValue ? newThreats(prevFen!, fen, me).map { LensArrow(from: $0.from, to: $0.to, tone: "threat") } : []
  let mine = loose.filter { $0.color == me }.count
  marks.caption = loose.isEmpty ? "Nothing hanging" : "Yours at risk \(mine) \u{00b7} theirs \(loose.count - mine)"
  return marks
}

/// Your men a move leaves loose that were not before it: the Undefended flash.
public func newlyLoose(_ before: String, _ after: String, _ me: Color, from: String, to: String) -> [String] {
  let was = Set(loosePieces(before).filter { $0.color == me }.map(\.square))
  return loosePieces(after).filter { $0.color == me }.map(\.square).filter { square in
    square == to ? !was.contains(from) : !was.contains(square)
  }
}

public func lensMarks(_ kind: LensKind, _ fen: String, _ me: Color, _ prevFen: String? = nil) -> LensMarks {
  switch kind {
  case .pawns: return pawnsLens(fen)
  case .pieces: return piecesLens(fen, me)
  case .space: return spaceLens(fen, me)
  case .kings: return kingsLens(fen, me)
  case .threats: return threatsLens(fen, me, prevFen)
  }
}
