import ChessCore

/// Named pawn structures and the plans that go with them.
/// The templates and their tests are in `StructureTemplates.swift`.

/// A piece and the square a plan wants it on.
public struct Goal: Equatable, Sendable, Codable {
  public init(piece: PieceType, to: String) {
    self.piece = piece
    self.to = to
  }
  public var piece: PieceType
  public var to: String
}

public struct PlanStep: Equatable, Sendable, Codable {
  public var text: String
  /// The pushes or piece squares the step names; reaching any completes it.
  public var goals: [Goal]?
  init(text: String, goals: [Goal]? = nil) {
    self.text = text
    self.goals = goals
  }
}

public struct StructureTemplate: Equatable, Sendable, Codable {
  public var id: String
  public var name: String
  /// Named for one side, as in "Isolated queen pawn (White)".
  public var sided: Bool
  /// Plans for the side the structure is named after, then for its opponent.
  public var a: [PlanStep]
  public var b: [PlanStep]

  enum CodingKeys: String, CodingKey { case id, name, sided, a, b }

  /// `sided` is written only when true.
  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(id, forKey: .id)
    try c.encode(name, forKey: .name)
    if sided { try c.encode(true, forKey: .sided) }
    try c.encode(a, forKey: .a)
    try c.encode(b, forKey: .b)
  }

  public init(id: String, name: String, sided: Bool, a: [PlanStep], b: [PlanStep]) {
    self.id = id
    self.name = name
    self.sided = sided
    self.a = a
    self.b = b
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      id: try c.decode(String.self, forKey: .id), name: try c.decode(String.self, forKey: .name),
      sided: try c.decodeIfPresent(Bool.self, forKey: .sided) ?? false,
      a: try c.decode([PlanStep].self, forKey: .a), b: try c.decode([PlanStep].self, forKey: .b))
  }
}

public struct Structure: Equatable, Sendable {
  public var template: StructureTemplate
  /// Which color is side `a`.
  public var a: Color
  public init(template: StructureTemplate, a: Color) {
    self.template = template
    self.a = a
  }
}

private let FILES = Array("abcdefgh")

struct Pawns: Sendable {
  let pawns: [(color: Color, file: Int, rank: Int)]
  /// A pawn of this color on this file, on this rank counted from its own side.
  func has(_ color: Color, _ file: String, _ relRank: Int) -> Bool {
    let f = FILES.firstIndex(of: Character(file))!
    return pawns.contains { $0.color == color && $0.file == f && $0.rank == (color == .w ? relRank - 1 : 8 - relRank) }
  }
  func none(_ color: Color, _ file: String) -> Bool {
    let f = FILES.firstIndex(of: Character(file))!
    return !pawns.contains { $0.color == color && $0.file == f }
  }
}

private func pawnsOf(_ fen: String) -> Pawns {
  Pawns(pawns: piecesFromFen(fen).filter { $0.type == .p }.map { p in
    let (file, rank) = coords(p.square)
    return (p.color, file, rank)
  })
}

public let STRUCTURE_TEMPLATES = TEMPLATES.map(\.template)

/// The structure the pawns form, if they match a named one.
public func structureOf(_ fen: String) -> Structure? {
  let p = pawnsOf(fen)
  for (template, test) in TEMPLATES {
    for a in [Color.w, .b] where test(p, a, a.other) { return Structure(template: template, a: a) }
  }
  return nil
}

/// The structure's name as the Pawns lens shows it.
public func structureLabel(_ structure: Structure) -> String {
  structure.template.sided ? "\(structure.template.name) (\(structure.a == .w ? "White" : "Black"))" : structure.template.name
}

/// A template square as it stands on the board: mirrored when side `a` is Black.
public func placeSquare(_ square: String, _ a: Color) -> String {
  if a == .w { return square }
  return "\(square.first!)\(9 - Int(String(square.last!))!)"
}

/// Your side's plan in a structure.
public func planFor(_ structure: Structure, _ me: Color) -> [PlanStep] {
  let steps = structure.a == me ? structure.template.a : structure.template.b
  return steps.map { s in
    PlanStep(text: stepText(s.text, structure.a, me), goals: s.goals?.map { Goal(piece: $0.piece, to: placeSquare($0.to, structure.a)) })
  }
}

/// A step's words for the board: squares mirrored when `a` is Black, Black's moves given their "...".
public func stepText(_ text: String, _ a: Color, _ me: Color) -> String {
  var placed = text
  if a != .w {
    placed = text.replacing(#/([a-h])([1-8])/#) { m in "\(m.1)\(9 - Int(String(m.2))!)" }
  }
  return placed
    .replacing(#/\{([^}]+)\}/#) { m in me == .b ? "...\(m.1)" : String(m.1) }
    .replacing(#/<([^>]+)>/#) { m in me == .w ? "...\(m.1)" : String(m.1) }
}

/// Each structure's plan in a few words, for the side it is named after and then its opponent.
public let PLAN_HEADLINES: [String: (a: String, b: String)] = [
  "stonewall": ("Knight to e5", "The e4 outpost"),
  "carlsbad": ("Minority attack", "Kingside play"),
  "french-chain": ("Hold d4, attack the king", "Hit the chain's base"),
  "caro-advance": ("Kingside space", "Free the bishop, hit d4"),
  "czech-benoni": ("Open the queenside", "The f5 break"),
  "kid-chain": ("Queenside break", "Kingside storm"),
  "benoni": ("The e5 push", "Queenside majority"),
  "hedgehog": ("Keep the squeeze", "Wait, then break"),
  "botvinnik": ("Knight to d5", "The d4 hole"),
  "maroczy": ("Keep the bind", "Trade and break"),
  "dragon": ("Open the h-file", "The c-file"),
  "scheveningen": ("Kingside pawn storm", "Central break"),
  "sicilian-e5": ("The d5 hole", "Free your game with d5"),
  "hanging-pawns": ("Push at the right moment", "Attack the pawns"),
  "iqp": ("Play for the attack", "Blockade d5"),
  "big-center": ("Push for space", "Hit the center"),
  "central-tension": ("Keep the tension", "Hold e5"),
  "symmetrical": ("Fight for the outposts", "Fight for e4"),
  "open-center": ("Activity first", "Activity first"),
]

/// Your side's plan in a few words, its squares placed for the board.
public func planHeadline(_ structure: Structure, _ me: Color) -> String? {
  PLAN_HEADLINES[structure.template.id].map { stepText(structure.a == me ? $0.a : $0.b, structure.a, me) }
}

/// A piece of a step's words: plain, or a move it names.
public struct StepRun: Equatable, Sendable {
  public var text: String
  public var move: Bool
}

/// Your side's plan as runs of words, the moves marked so they can stand out.
/// Each step's runs join to the same words as `planFor`'s.
public func planRuns(_ structure: Structure, _ me: Color) -> [[StepRun]] {
  let steps = structure.a == me ? structure.template.a : structure.template.b
  return steps.map { stepRuns($0.text, structure.a, me) }
}

/// A step's words split at its marked moves, each placed as `stepText` places it.
public func stepRuns(_ text: String, _ a: Color, _ me: Color) -> [StepRun] {
  var runs: [StepRun] = []
  var rest = Substring(text)
  while let m = rest.firstMatch(of: #/\{[^}]+\}|<[^>]+>/#) {
    if m.range.lowerBound > rest.startIndex {
      runs.append(StepRun(text: stepText(String(rest[..<m.range.lowerBound]), a, me), move: false))
    }
    runs.append(StepRun(text: stepText(String(m.output), a, me), move: true))
    rest = rest[m.range.upperBound...]
  }
  if !rest.isEmpty { runs.append(StepRun(text: stepText(String(rest), a, me), move: false)) }
  return runs
}
