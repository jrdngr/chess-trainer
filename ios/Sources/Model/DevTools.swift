import ChessCore
import Foundation

/// The developer tools' changes to a save: set straight, logging nothing, earning nothing.
/// Only Xcode and TestFlight builds show them.

/// The developer tools' settings for this device, outside every profile's save.
public struct DevSettings: Equatable, Sendable, Codable {
  /// Whole days the clock runs ahead.
  public var daysAhead = 0
  /// The unlock the App Store says is owned isn't credited, so it can be shown and bought again.
  public var ignoreStoreUnlock = false
  public init() {}

  enum CodingKeys: String, CodingKey { case daysAhead, ignoreStoreUnlock }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    daysAhead = try c.decodeIfPresent(Int.self, forKey: .daysAhead) ?? 0
    ignoreStoreUnlock = try c.decodeIfPresent(Bool.self, forKey: .ignoreStoreUnlock) ?? false
  }
}

/// An opening's form as the developer tools set it.
public enum DevForm: String, Sendable, CaseIterable {
  /// Every answer quick and right.
  case green
  /// Every answer slow.
  case middle
  /// Every answer missed.
  case red
  /// No answers.
  case none

  /// The answers it fills an opening's form with.
  public var answers: [Double]? {
    switch self {
    case .green: Array(repeating: 1, count: FORM_ANSWERS)
    case .middle: Array(repeating: 0.5, count: FORM_ANSWERS)
    case .red: Array(repeating: 0, count: FORM_ANSWERS)
    case .none: nil
    }
  }
}

extension AppState {
  /* ── tips ── */

  /// A tip marked seen, or unseen so it shows again at its trigger.
  public mutating func devSetTip(_ tip: GameTip, seen: Bool) {
    if seen { settings.seenTips.insert(tip) } else { settings.seenTips.remove(tip) }
  }

  /// Every tip seen, or none.
  public mutating func devSetAllTips(seen: Bool) {
    settings.seenTips = seen ? Set(GameTip.allCases) : []
  }

  /* ── the Pawn Shop ── */

  /// An item made yours with every item it needs, or taken away with every item that needs it.
  public mutating func devSetOwned(_ id: String, _ owned: Bool) {
    guard let item = shopItem(id), item.feature != nil else { return }
    if owned {
      for need in item.needs { devSetOwned(need, true) }
      unlocked.insert(id)
    } else {
      unlocked.remove(id)
      for other in SHOP where other.needs.contains(id) { devSetOwned(other.id, false) }
    }
    syncEndgameFamilies()
  }

  /// Every feature and endgame family yours, or none.
  public mutating func devSetAllOwned(_ owned: Bool) {
    if owned { unlockAll() } else { unlocked = [] }
  }

  /// Pawns added, or taken off with a negative count; the balance stops at 0.
  public mutating func devAddPawns(_ count: Int) {
    pawns = max(0, pawns + count)
  }

  /* ── openings ── */

  /// An opening on the list put into the Playbook free, or taken out with its moves, cards and form.
  /// Neither touches the price ladder. Returns whether it changed.
  @discardableResult
  public mutating func devSetOpening(_ id: String, owned: Bool, _ tree: OpeningTree) -> Bool {
    guard let opening = curatedOpening(id), ownsFamily(id) != owned else { return false }
    if owned { return seedFamily(opening, tree) }
    guard let rep = playbookList.first(where: { $0.color == opening.color }) else { return false }
    dropFamily(opening, from: rep.id)
    return true
  }

  /// Swap tokens held, from 0 to the most you can hold.
  public mutating func devSetTokens(_ count: Int) {
    families.tokens = min(MAX_SWAP_TOKENS, max(0, count))
  }

  /* ── onboarding ── */

  /// Welcome again, then onboarding; the save stays, and the openings picked go in beside it.
  public mutating func devReplayWelcome() {
    settings.seenIntro = false
    settings.onboarded = false
  }

  /* ── the streak ── */

  /// The streak set by hand: its length, the freezes held, and its last day, `lastPlayed` days
  /// before `now` (0 today, 1 yesterday); no days clears it.
  public mutating func devSetStreak(days: Int, freezes: Int, lastPlayed: Int, now: Double = Env.now()) {
    var streak = PawnStreak()
    streak.days = max(0, days)
    streak.freezes = min(MAX_FREEZES, max(0, freezes))
    if streak.days > 0 {
      let back = max(0, lastPlayed)
      streak.day = back == 0 ? dayKey(now) : daysBefore(now, back)[back - 1]
      streak.frozen = pawnStreak.frozen.filter { $0 <= streak.days }
    }
    pawnStreak = streak
  }

  /* ── growth levels ── */

  /// `count` Play games added to the history, each an ending on your first move, so the curve's
  /// level gates count them.
  public mutating func devAddPlayGames(_ count: Int, now: Double = Env.now()) {
    let rep = playbookList.first { $0.color == .w } ?? playbookList.first
    let color = rep?.color ?? .w
    let line = rep.flatMap { leafLines($0).first?.sans } ?? ["e4"]
    let moves = Array(line.prefix(color == .w ? 1 : 2))
    for n in 0..<max(0, count) {
      let game = GameRecord(
        id: "dev-\(Int(now))-\(games.count)-\(n)", mode: .play, at: now, color: color, picked: settings.selection,
        opening: "", moves: moves.isEmpty ? ["e4"] : moves, result: "*", termination: "ended")
      games = addGame(games, game)
    }
  }

  /// An opening's form set by hand.
  public mutating func devSetForm(_ id: String, _ color: Color, _ level: DevForm) {
    form[color][id] = level.answers
  }
}
