import ChessCore

/// The global selection: which side, and which region of the opening tree,
/// every mode works in.

public enum ColorChoice: String, Sendable, Codable {
  case w, b, either

  /// Saves before version 1 call Either "random".
  public init(from decoder: Decoder) throws {
    let raw = try decoder.singleValueContainer().decode(String.self)
    guard let choice = ColorChoice(rawValue: raw == "random" ? "either" : raw) else {
      throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown side \(raw)"))
    }
    self = choice
  }
}

public struct Selection: Equatable, Sendable, Codable {
  public var color: ColorChoice
  /// An opening tree node id; "" is the root.
  public var opening: String
  public init(color: ColorChoice, opening: String) {
    self.color = color
    self.opening = opening
  }
}

public let DEFAULT_SELECTION = Selection(color: .either, opening: "")

/// The sides a selection covers: both, for Either.
public func colorsOf(_ choice: ColorChoice) -> [Color] {
  switch choice {
  case .either: return [.w, .b]
  case .w: return [.w]
  case .b: return [.b]
  }
}

public func colorLabel(_ choice: ColorChoice) -> String {
  choice == .w ? "White" : choice == .b ? "Black" : "Either"
}

/// The repertoires the selection covers.
public func repertoiresIn(_ reps: [Repertoire], _ choice: ColorChoice) -> [Repertoire] {
  let wanted = colorsOf(choice)
  return reps.filter { wanted.contains($0.color) }
}

/// The region a selection names.
public func regionOf(_ tree: OpeningTree, _ selection: Selection) -> OpeningNode {
  nodeById(tree, selection.opening)
}

/// The training items inside a region: those whose answer keeps the line in it, or on the way in.
public func itemsInRegion(_ tree: OpeningTree, _ node: OpeningNode, _ items: [TrainingItem]) -> [TrainingItem] {
  if node.depth == 0 { return items }
  return items.filter { item in item.expected.contains { lineStatus(tree, node, item.pathSans + [$0.san]) != .outside } }
}

/// Is a line inside a region, or still able to get there?
public func lineInRegion(_ tree: OpeningTree, _ node: OpeningNode, _ sans: [String]) -> Bool {
  node.depth == 0 || lineStatus(tree, node, sans) != .outside
}
