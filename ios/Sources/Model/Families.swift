import Book
import ChessCore

/// Opening families: what pawns buy on the Playbook tree. A family is the first move that is
/// yours: as White, your first move; as Black, your answer to White's first move. Pawns buy
/// families; everything under one is a variation, free, and grows only through the curve.

/// What the first family past the starting ones costs, and how much more each one after.
public let FAMILY_FIRST_PRICE = 2_000, FAMILY_PRICE_STEP = 500
/// Families bought to earn a swap token, and the most tokens held.
public let FAMILIES_PER_TOKEN = 3, MAX_SWAP_TOKENS = 1
/// The least share of games, in percent, a move needs to show as a family on the tree.
public let FAMILY_MIN_SHARE = 2.0

/// The family a line is in, for the side that plays it: its first move as White, its first two
/// as Black. Nil for a line too short to have one.
public func familyLine(_ line: [String], _ color: Color) -> [String]? {
  let plies = color == .w ? 1 : 2
  return line.count >= plies ? Array(line.prefix(plies)) : nil
}

/// What families cost and how swaps are earned.
public struct FamilyRecord: Equatable, Sendable, Codable {
  /// Families bought on each side, by color ("w", "b"): each one raises its side's price.
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

  /// The next family's price on a side.
  public func price(_ color: Color) -> Int { FAMILY_FIRST_PRICE + FAMILY_PRICE_STEP * (bought[color.rawValue] ?? 0) }
}

/// The moves a family starts with: the family, then the most played reply and your most played
/// answer in turn, for `size` of your moves, ending where the named opening ends or no reply is
/// common enough. As Black the calmest of the top answers leads.
public func familySeed(_ tree: OpeningTree, _ family: [String], _ color: Color, size: Int) -> [String] {
  let index = tree.index
  var line = family
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

/// The families a side could have: as White the common first moves; as Black, under each common
/// first move, the common answers. Most played first.
public func familyChoices(_ index: ReferenceIndex, _ color: Color) -> [[String]] {
  let firsts = popularReplies(index, START_FEN, FAMILY_MIN_SHARE).map(\.san)
  if color == .w { return firsts.map { [$0] } }
  return firsts.flatMap { first -> [[String]] in
    guard let after = applySan(START_FEN, first)?.after else { return [] }
    return popularReplies(index, after, FAMILY_MIN_SHARE).map { [first, $0.san] }
  }
}

extension AppState {
  /// The families you have on a side: those your Playbook's lines are in, in Playbook order.
  public func ownedFamilies(_ color: Color) -> [[String]] {
    guard let rep = playbookList.first(where: { $0.color == color }) else { return [] }
    var out: [[String]] = []
    for leaf in leafLines(rep) {
      guard let family = familyLine(leaf.sans, color), !out.contains(family) else { continue }
      out.append(family)
    }
    return out
  }

  public func ownsFamily(_ family: [String], _ color: Color) -> Bool { ownedFamilies(color).contains(family) }

  /// Buy a family at its side's price: its seed line goes into the Playbook, the price rises, and
  /// every third family bought earns a swap token. Returns whether it was bought.
  @discardableResult
  public mutating func buyFamily(_ family: [String], _ color: Color, _ tree: OpeningTree) -> Bool {
    let price = families.price(color)
    guard familyLine(family, color) == family, !ownsFamily(family, color), pawns >= price else { return false }
    guard seedFamily(family, color, tree) else { return false }
    pawns -= price
    families.bought[color.rawValue, default: 0] += 1
    let total = families.bought.values.reduce(0, +)
    if total % FAMILIES_PER_TOKEN == 0 { families.tokens = min(MAX_SWAP_TOKENS, families.tokens + 1) }
    logEvent(AppEvent(kind: "buy", color: color, count: price, picked: family.joined(separator: " "), text: "balance \(pawns)"))
    return true
  }

  /// Swap a family you have for one you don't, with a token: the old one goes with every move,
  /// card and form under it. Returns whether it was swapped.
  @discardableResult
  public mutating func swapFamily(_ out: [String], for family: [String], _ color: Color, _ tree: OpeningTree) -> Bool {
    guard families.tokens > 0, ownsFamily(out, color), familyLine(family, color) == family, !ownsFamily(family, color),
      let rep = playbookList.first(where: { $0.color == color }), let node = nodeAtLine(rep, out)
    else { return false }
    removeNode(rep.id, node.id)
    for id in form.openings.keys where id.split(separator: " ").map(String.init).starts(with: out) { form.openings[id] = nil }
    guard seedFamily(family, color, tree) else { return false }
    families.tokens -= 1
    logEvent(AppEvent(kind: "swap", color: color, picked: family.joined(separator: " "), text: "out \(out.joined(separator: " "))"))
    return true
  }

  /// A family's seed line into its side's Playbook.
  @discardableResult
  mutating func seedFamily(_ family: [String], _ color: Color, _ tree: OpeningTree) -> Bool {
    let line = familySeed(tree, family, color, size: settings.movesPerFill)
    let id = ensurePlaybook(color)
    return addLine(id, line, .fixed(.growth), via: .growth) > 0
  }
}
