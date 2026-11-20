import Book
import ChessCore

/// Openings for sale: a curated list, each named the way a player talks about the choice they
/// made (the Italian, the Najdorf, the Slav). An opening is everything from its named position
/// on; the moves leading to it are fixed. You drill only the openings you have, and growth
/// stays inside them. Pawns buy openings; everything inside one grows through the curve.

/// What the first opening past the starting ones costs, and how much more each one after.
public let FAMILY_FIRST_PRICE = 500, FAMILY_PRICE_STEP = 500
/// Openings bought to earn a swap token, and the most tokens held.
public let FAMILIES_PER_TOKEN = 3, MAX_SWAP_TOKENS = 1

/// One opening on the list.
public struct CuratedOpening: Equatable, Sendable, Identifiable {
  public var id: String
  public var name: String
  /// The side that plays it.
  public var color: Color
  /// The moves to its named position, ending on your move. Most openings have one; a system
  /// played against several answers (the London) has one per answer.
  public var roots: [[String]]

  init(_ id: String, _ name: String, _ color: Color, _ roots: String...) {
    self.id = id
    self.name = name
    self.color = color
    self.roots = roots.map { $0.split(separator: " ").map(String.init) }
  }

  /// The first move of its line.
  public var firstMove: String { roots[0][0] }

  /// Whether a line is inside it: past one of its roots, or at one.
  public func holds(_ line: [String]) -> Bool { roots.contains { line.starts(with: $0) } }

  /// Whether a line leads into it: a start of one of its roots.
  public func leadsInto(_ line: [String]) -> Bool { roots.contains { $0.starts(with: line) } }
}

/// The list, most played first on each side.
public let OPENING_LIST: [CuratedOpening] = [
  // White
  CuratedOpening("italian", "Italian Game", .w, "e4 e5 Nf3 Nc6 Bc4"),
  CuratedOpening("ruy", "Ruy Lopez", .w, "e4 e5 Nf3 Nc6 Bb5"),
  CuratedOpening("scotch", "Scotch Game", .w, "e4 e5 Nf3 Nc6 d4"),
  CuratedOpening("vienna", "Vienna Game", .w, "e4 e5 Nc3"),
  CuratedOpening("kingsGambit", "King's Gambit", .w, "e4 e5 f4"),
  CuratedOpening("openSicilian", "Open Sicilian", .w, "e4 c5 Nf3 d6 d4", "e4 c5 Nf3 Nc6 d4", "e4 c5 Nf3 e6 d4"),
  CuratedOpening("alapin", "Alapin Sicilian", .w, "e4 c5 c3"),
  CuratedOpening("morra", "Smith-Morra Gambit", .w, "e4 c5 d4 cxd4 c3"),
  CuratedOpening("advanceFrench", "Advance French", .w, "e4 e6 d4 d5 e5"),
  CuratedOpening("advanceCaro", "Advance Caro-Kann", .w, "e4 c6 d4 d5 e5"),
  CuratedOpening("queensGambit", "Queen's Gambit", .w, "d4 d5 c4"),
  CuratedOpening("london", "London System", .w, "d4 d5 Bf4", "d4 Nf6 Bf4"),
  CuratedOpening("catalan", "Catalan", .w, "d4 Nf6 c4 e6 g3"),
  CuratedOpening("english", "English Opening", .w, "c4"),
  CuratedOpening("kia", "King's Indian Attack", .w, "Nf3 d5 g3", "Nf3 Nf6 g3"),
  // Black against 1.e4
  CuratedOpening("openGame", "1...e5", .b, "e4 e5"),
  CuratedOpening("najdorf", "Najdorf Sicilian", .b, "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6"),
  CuratedOpening("dragon", "Dragon Sicilian", .b, "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 g6"),
  CuratedOpening("accelerated", "Accelerated Dragon", .b, "e4 c5 Nf3 Nc6 d4 cxd4 Nxd4 g6"),
  CuratedOpening("french", "French Defense", .b, "e4 e6"),
  CuratedOpening("caro", "Caro-Kann Defense", .b, "e4 c6"),
  CuratedOpening("scandinavian", "Scandinavian Defense", .b, "e4 d5"),
  CuratedOpening("pirc", "Pirc Defense", .b, "e4 d6"),
  // Black against 1.d4
  CuratedOpening("qgd", "Queen's Gambit Declined", .b, "d4 d5 c4 e6"),
  CuratedOpening("slav", "Slav Defense", .b, "d4 d5 c4 c6"),
  CuratedOpening("qga", "Queen's Gambit Accepted", .b, "d4 d5 c4 dxc4"),
  CuratedOpening("kid", "King's Indian Defense", .b, "d4 Nf6 c4 g6 Nc3 Bg7"),
  CuratedOpening("grunfeld", "Grünfeld Defense", .b, "d4 Nf6 c4 g6 Nc3 d5"),
  CuratedOpening("nimzo", "Nimzo-Indian Defense", .b, "d4 Nf6 c4 e6 Nc3 Bb4"),
  CuratedOpening("qid", "Queen's Indian Defense", .b, "d4 Nf6 c4 e6 Nf3 b6"),
  CuratedOpening("dutch", "Dutch Defense", .b, "d4 f5"),
]

/// An opening on the list by id.
public func curatedOpening(_ id: String) -> CuratedOpening? { OPENING_LIST.first { $0.id == id } }

/// The openings on the list for one side.
public func openingList(_ color: Color) -> [CuratedOpening] { OPENING_LIST.filter { $0.color == color } }

/// What openings cost and how swaps are earned.
public struct FamilyRecord: Equatable, Sendable, Codable {
  /// Openings bought on each side, by color ("w", "b"): each one raises its side's price.
  public var bought: [String: Int] = [:]
  /// Swap tokens held.
  public var tokens = 1
  public init() {}

  enum CodingKeys: String, CodingKey { case bought, tokens }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    bought = try c.decodeIfPresent([String: Int].self, forKey: .bought) ?? [:]
    tokens = try c.decodeIfPresent(Int.self, forKey: .tokens) ?? 1
  }

  /// The next opening's price on a side.
  public func price(_ color: Color) -> Int { FAMILY_FIRST_PRICE + FAMILY_PRICE_STEP * (bought[color.rawValue] ?? 0) }
}

/// The moves an opening starts with, from one of its roots: the most played reply and your
/// most played answer in turn, for `size` of your moves, ending where the named opening ends
/// or no reply is common enough. As Black the calmest of the top answers leads.
public func familySeed(_ tree: OpeningTree, _ root: [String], _ color: Color, size: Int) -> [String] {
  let index = tree.index
  var line = root
  var added = 1
  while !fillEnds(index, line, added: added, size: size) {
    let walked = walkSan(line)
    guard walked.moves.count == line.count else { break }
    let fen = walked.fens[line.count]
    if fenTurn(fen) == color {
      let answers = calmFirst(tree, line, color: color, popularReplies(index, fen, 0).prefix(3).map(\.san), san: { $0 })
      guard let pick = answers.first else { break }
      line.append(pick)
      added += 1
    } else {
      guard let reply = popularReplies(index, fen, GAP_SHARE).first else { break }
      line.append(reply.san)
    }
  }
  return line
}

extension AppState {
  /// The openings on the list you have on a side: those your Playbook's lines are in, in list order.
  public func ownedFamilies(_ color: Color) -> [CuratedOpening] {
    guard let rep = playbookList.first(where: { $0.color == color }) else { return [] }
    let lines = leafLines(rep).map(\.sans)
    return openingList(color).filter { opening in lines.contains { opening.holds($0) } }
  }

  public func ownsFamily(_ id: String) -> Bool {
    guard let opening = curatedOpening(id) else { return false }
    return ownedFamilies(opening.color).contains { $0.id == id }
  }

  /// Buy an opening at its side's price: its seed lines go into the Playbook, the price rises, and
  /// every third one bought earns a swap token. Returns whether it was bought.
  @discardableResult
  public mutating func buyFamily(_ id: String, _ tree: OpeningTree) -> Bool {
    guard let opening = curatedOpening(id), !ownsFamily(id) else { return false }
    let price = families.price(opening.color)
    guard pawns >= price, seedFamily(opening, tree) else { return false }
    pawns -= price
    families.bought[opening.color.rawValue, default: 0] += 1
    let total = families.bought.values.reduce(0, +)
    if total % FAMILIES_PER_TOKEN == 0 { families.tokens = min(MAX_SWAP_TOKENS, families.tokens + 1) }
    logEvent(AppEvent(kind: "buy", color: opening.color, count: price, picked: id, text: "balance \(pawns)"))
    return true
  }

  /// Swap an opening you have for one you don't, on the same side, with a token: the old one goes
  /// with every move, card and form inside it. Moves it shares with another opening you have stay.
  /// Returns whether it was swapped.
  @discardableResult
  public mutating func swapFamily(_ out: String, for id: String, _ tree: OpeningTree) -> Bool {
    guard families.tokens > 0, let old = curatedOpening(out), let new = curatedOpening(id), old.color == new.color,
      ownsFamily(out), !ownsFamily(id), let rep = playbookList.first(where: { $0.color == old.color })
    else { return false }
    dropFamily(old, from: rep.id)
    guard seedFamily(new, tree) else { return false }
    families.tokens -= 1
    logEvent(AppEvent(kind: "swap", color: old.color, picked: id, text: "out \(out)"))
    return true
  }

  /// An opening out of the Playbook, with every move, card and form inside it. Moves it shares
  /// with another opening you have stay.
  mutating func dropFamily(_ old: CuratedOpening, from repId: String) {
    let kept = ownedFamilies(old.color).filter { $0.id != old.id }
    for root in old.roots {
      // Cut where the root leaves every other opening you have.
      let cut = (1...root.count).first { n in !kept.contains { $0.leadsInto(Array(root.prefix(n))) || $0.holds(Array(root.prefix(n))) } }
      guard let cut, let fresh = playbooks[repId], let node = nodeAtLine(fresh, Array(root.prefix(cut))) else { continue }
      removeNode(repId, node.id)
    }
    for key in form[old.color].keys where old.holds(key.split(separator: " ").map(String.init)) { form[old.color][key] = nil }
  }

  /// An opening's seed lines into its side's Playbook, one per root.
  @discardableResult
  mutating func seedFamily(_ opening: CuratedOpening, _ tree: OpeningTree) -> Bool {
    let id = ensurePlaybook(opening.color)
    var added = 0
    for root in opening.roots {
      added += addLine(id, familySeed(tree, root, opening.color, size: MOVES_PER_FILL), .fixed(.growth), via: .growth)
    }
    return added > 0
  }
}
