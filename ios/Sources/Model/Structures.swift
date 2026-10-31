import ChessCore

/// Named pawn structures and the plans that go with them. `src/model/structures.ts`.
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

  /// `sided` is written only when true, as the prototype's templates are.
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
