import Foundation
import Model

/// Pawns on their way to the counter: each drop is one award, its pawns popping out where they
/// were earned. The balance takes them at once; the counter shows them as they land.
public struct PawnDrop: Equatable, Identifiable, Sendable {
  public var id: Int
  public var award: PawnAward
  /// Its pawns not yet in the counter.
  public var flying: Int
  /// Flying into the prep's pot, not the counter: not on the balance yet.
  public var toPot = false
}

extension AppStore {
  /// How long a drop may take before its pawns count anyway.
  public static let dropSeconds = 3.0

  /// The balance as the counter shows it: pawns still flying aren't in it yet.
  public var shownPawns: Int { state.pawns - streakWaiting - pawnDrops.reduce(0) { $0 + ($1.toPot ? 0 : $1.flying) } }

  /// Pawns on their way into the prep's pot.
  public var flyingToPot: Int { pawnDrops.reduce(0) { $0 + ($1.toPot ? $1.flying : 0) } }

  /// Pawns on their way out of the prep's pot to the counter.
  public var flyingFromPot: Int { pawnDrops.reduce(0) { $0 + (!$1.toPot && $1.award.source == .pot ? $1.flying : 0) } }

  /// A prepared move found: a pawn pops out of its square into the prep's pot. It isn't
  /// earned until the prep completes.
  public func dropInPot(_ square: String) {
    dropCount += 1
    let id = dropCount
    pawnDrops.append(PawnDrop(id: id, award: PawnAward(.prepComplete, .square(square), count: 1), flying: 1, toPot: true))
    let clock = services.clock
    Task { @MainActor [weak self] in
      await clock.sleep(Self.dropSeconds)
      self?.pawnDrops.removeAll { $0.id == id }
    }
  }

  /// Pawns earned: onto the balance (unless `paid` already), and off to the counter.
  public func pay(_ award: PawnAward, paid: Bool = false) {
    guard award.count > 0 else { return }
    log(AppEvent(kind: "pawns", source: award.event.rawValue, count: award.count, text: "\(award.source)"))
    if !paid { update { $0.earn(award.count) } }
    drop(award)
  }

  /// An award's pawns off to the counter.
  private func drop(_ award: PawnAward) {
    dropCount += 1
    let id = dropCount
    pawnDrops.append(PawnDrop(id: id, award: award, flying: award.count))
    services.emit(.pawns(award))
    // Not counted as the game's work: a headless game doesn't wait on the counter.
    let clock = services.clock
    Task { @MainActor [weak self] in
      await clock.sleep(Self.dropSeconds)
      self?.pawnDrops.removeAll { $0.id == id }
    }
  }

  /// One of a drop's pawns reached the counter.
  public func landed(_ id: Int) {
    guard let i = pawnDrops.firstIndex(where: { $0.id == id }) else { return }
    pawnDrops[i].flying -= 1
    if pawnDrops[i].flying <= 0 { pawnDrops.remove(at: i) }
  }

  /// A game finished: the day's first in a streak pays. The pawns go onto the balance
  /// now and wait to pop out of the streak ring on Home.
  public func finishedGame() {
    var streak = 0
    update { streak = $0.finishedGame() }
    guard streak > 0 else { return }
    log(AppEvent(kind: "pawns", source: PawnEvent.streak.rawValue, count: streak, text: "waiting"))
    streakWaiting += streak
  }

  /// Home is up: the streak pawns waiting pop out of its streak ring.
  public func showStreakPawns() {
    if state.pawnStreak != Model.settleStreak(state.pawnStreak, past: daysBefore(Env.now())) { update { $0.settleStreak() } }
    guard streakWaiting > 0 else { return }
    let count = streakWaiting
    streakWaiting = 0
    drop(PawnAward(.streak, .streak, count: count))
  }
}

extension AppStore {
  /// Buy an item in the Pawn Shop. Returns whether it was bought.
  @discardableResult
  public func buy(_ id: String) -> Bool {
    var bought = false
    update { bought = $0.buy(id) }
    if bought, let feature = shopItem(id)?.feature { justUnlocked = feature }
    return bought
  }

  /// A feature's place showed it off: it is no longer new.
  public func shownUnlock(_ feature: ShopFeature) {
    if justUnlocked == feature { justUnlocked = nil }
  }
}
