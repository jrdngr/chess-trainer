import ChessCore
import Engine
import Foundation
import Model

/// Measuring what play earns: a bot plays your side headless, run after run, and each run's
/// pawn events and moves are counted. Counts, not rates: time and pawn values are
/// assumptions applied afterwards, so a price change needs no new games.

/// How the bot spends a session.
public enum MeasureStrategy: String, Sendable, CaseIterable, Codable {
  /// Play runs: the prep, then on to the run's end.
  case full
  /// Play runs: the prep, growth when it opens, then the X.
  case prepOnly
  /// Middlegame runs, played to their end.
  case middlegame
  /// Endgames rounds, by Practice (the library in turn once nothing is due), played with the engine's best moves.
  case endgames
}

public struct MeasureOptions: Sendable {
  public var strategy: MeasureStrategy
  /// The bot's level, and the player strength the app starts from.
  public var rating: Int
  public var runs: Int
  public var side: ColorChoice
  public var start: RunStart
  /// How often the bot plays its own move instead of the prepared one.
  public var missRate: Double
  /// A run still going after this many of your moves is ended with the X.
  public var maxMoves: Int
  /// The app's estimate of your strength follows your play, as it does in the app; otherwise it is
  /// set back to `rating` before each run, so the opponent plays at it.
  public var adaptive: Bool
  public init(
    strategy: MeasureStrategy, rating: Int, runs: Int, side: ColorChoice = .w, start: RunStart = .drill,
    missRate: Double = 0, maxMoves: Int = 120, adaptive: Bool = false
  ) {
    self.adaptive = adaptive
    self.strategy = strategy
    self.rating = rating
    self.runs = runs
    self.side = side
    self.start = start
    self.missRate = missRate
    self.maxMoves = maxMoves
  }
}

/// One run, counted.
public struct MeasuredRun: Codable, Sendable, Equatable {
  public var strategy: String
  /// The bot's level.
  public var rating: Int
  /// The opponent's level when the run started.
  public var opponent: Int
  public var seed: UInt32
  /// Which run of the session: the Playbook grows as they go.
  public var index: Int
  public var side: String
  /// Drill or Freeform; for Endgames, the ending's family.
  public var start: String
  public var opening: String
  /// Moves in your Playbook when the run started.
  public var playbookMoves: Int
  /// Your moves asked by your prep.
  public var prepMoves = 0
  /// Your moves added while growth was open.
  public var growthMoves = 0
  /// Your other moves.
  public var otherMoves = 0
  public var misses = 0
  /// blunder, won, lost, draw, ended (the X), capped; for Endgames, success or failure.
  public var ending = ""
  /// How many times each pawn event paid, by `PawnEvent` name.
  public var events: [String: Int] = [:]
  /// Pawns earned at the values the run was played with.
  public var pawns = 0
}

/// The bot: the engine at a level, picking as the app's opponents do.
@MainActor
final class MeasureBot {
  let engine: ChessEngine
  let level: Level
  var seed: UInt32

  init(engine: ChessEngine, rating: Int, seed: UInt32) {
    self.engine = engine
    self.level = levelFor(rating: rating)
    self.seed = seed ^ 0x9e37_79b9
  }

  func chance() -> Double {
    seed = seed &+ 0x6d2b_79f5
    var t = seed
    t = (t ^ (t >> 15)) &* (t | 1)
    t ^= t &+ ((t ^ (t >> 7)) &* (t | 61))
    return Double(t ^ (t >> 14)) / 4_294_967_296
  }

  /// The engine's best move, searched deep: a player who knows the technique.
  func best(_ fen: String) async -> String? {
    let snap = await engine.analyse(fen, EngineLimits(depth: 14, multiPv: 1))
    return snap.lines.first?.pv.first.flatMap { applyUci(fen, $0)?.san } ?? legalMoves(fen).first?.san
  }

  func move(_ fen: String) async -> String? {
    let snap = await engine.analyse(fen, EngineLimits(depth: level.depth, multiPv: level.multiPv))
    let uci = chooseMove(snap.lines, level, chance)
    return uci.flatMap { applyUci(fen, $0)?.san } ?? legalMoves(fen).first?.san
  }
}

extension HeadlessApp {
  /// Play `options.runs` runs with a bot on your side and count each. The profile owns every
  /// feature, so every strategy can run; `onRun` sees each run as it ends.
  public func measure(_ options: MeasureOptions, seed: UInt32, onRun: (MeasuredRun) -> Void = { _ in }) async throws -> [MeasuredRun] {
    if !state.settings.seenIntro { try knowMyOpenings(starter: "classical") }
    store.update { state in
      state.unlockAll()
      state.strength = PlayerStrength(rating: Double(options.rating), moves: 1000)
    }
    try select(side: options.side, start: options.start, opening: ANY_OPENING)
    let bot = MeasureBot(engine: services.makeEngine(), rating: options.rating, seed: seed)
    var runs: [MeasuredRun] = []
    for index in 0..<options.runs {
      if !options.adaptive { store.update { $0.strength = PlayerStrength(rating: Double(options.rating), moves: 1000) } }
      var counted = MeasuredRun(
        strategy: options.strategy.rawValue, rating: options.rating, opponent: levelMatching(state.strength).rating,
        seed: seed, index: index, side: "", start: options.start.rawValue, opening: "", playbookMoves: playbookSize)
      _ = takeSignals()
      switch options.strategy {
      case .full, .prepOnly: try await measurePlay(options, bot, &counted, first: index == 0)
      case .middlegame: try await measureMiddlegame(options, bot, &counted)
      case .endgames: try await measureEnding(options, bot, &counted)
      }
      for signal in takeSignals() {
        guard case .pawns(let award) = signal, award.event != .streak else { continue }
        counted.events[award.event.rawValue, default: 0] += 1
        counted.pawns += award.count
      }
      runs.append(counted)
      onRun(counted)
    }
    await home()
    return runs
  }

  private var playbookSize: Int { state.playbooks.values.reduce(0) { $0 + $1.nodes.count } }

  private func measurePlay(_ options: MeasureOptions, _ bot: MeasureBot, _ counted: inout MeasuredRun, first: Bool) async throws {
    if first || play == nil { await openPlay() } else { try await next() }
    guard let model = run else { throw Failure.notHere("No Play run started") }
    counted.side = model.run.color.rawValue
    counted.opening = openingName(tree, model.openingId)
    try await playOut(options, bot, &counted, prepOnly: options.strategy == .prepOnly)
  }

  private func measureMiddlegame(_ options: MeasureOptions, _ bot: MeasureBot, _ counted: inout MeasuredRun) async throws {
    try await openMiddlegame()
    guard let model = run else { throw Failure.notHere("No Middlegame run started") }
    counted.side = model.run.color.rawValue
    counted.start = "middlegame"
    counted.opening = openingName(tree, model.openingId)
    try await playOut(options, bot, &counted, prepOnly: false)
  }

  /// Your moves in a run until it ends: the prep as prepared (now and then missed), growth's
  /// top answer while it is open, the bot's move otherwise.
  private func playOut(_ options: MeasureOptions, _ bot: MeasureBot, _ counted: inout MeasuredRun, prepOnly: Bool) async throws {
    var mine = 0
    while let model = run, model.live, model.finish == nil {
      if model.intro == .plan {
        // The plan card's Play.
        model.playFromHandoff()
        await idle()
        continue
      }
      guard model.myTurn, !model.held, let fen else { break }
      if mine >= options.maxMoves {
        await endRound()
        counted.ending = "capped"
        return
      }
      let san: String
      if model.fill != nil {
        guard let top = choices.first else { await doneAdding(); continue }
        san = top
        counted.growthMoves += 1
      } else if model.label == .on, let prepared = model.prepNow.first {
        if options.missRate > 0, bot.chance() < options.missRate, let own = await bot.move(fen), !model.prepNow.contains(own) {
          san = own
          counted.misses += 1
        } else {
          san = prepared
        }
        counted.prepMoves += 1
      } else if prepOnly {
        await endRound()
        break
      } else {
        guard let own = await bot.move(fen) else { break }
        san = own
        counted.otherMoves += 1
      }
      mine += 1
      try await move(san)
    }
    if run?.phase == .blunder {
      continueToEnd()
      await idle()
    }
    if counted.ending.isEmpty { counted.ending = endingName(run?.session.ending) }
  }

  private func measureEnding(_ options: MeasureOptions, _ bot: MeasureBot, _ counted: inout MeasuredRun) async throws {
    if endgame == nil { try openEndgames() }
    // Practice, or with nothing to practice, the library in turn, as a player picking endings would.
    do { try await practice() } catch {
      let entries = state.endgames.entries.filter { $0.family != "games" }
      guard !entries.isEmpty else { throw error }
      try await playEnding(entries[counted.index % entries.count].id)
    }
    guard let game = endgame?.game else { throw Failure.notHere("No ending started") }
    counted.side = game.color.rawValue
    counted.start = game.entry.family
    counted.opening = game.entry.name
    while game.phase == .playing, game.outcome == nil {
      guard game.myTurn else { await idle(); if !game.myTurn { break } else { continue } }
      if counted.otherMoves >= options.maxMoves {
        await resign()
        break
      }
      // Endgames are played by technique, not by level: the bot plays the best move it finds.
      guard let san = await bot.best(game.fen) else { break }
      counted.otherMoves += 1
      try await move(san)
    }
    switch game.outcome {
    case .success: counted.ending = "success"
    case .failure: counted.ending = "failure"
    case nil: counted.ending = "capped"
    }
  }
}

/// A run's ending as a word for the counts.
func endingName(_ ending: Ending?) -> String {
  switch ending {
  case .blunder: "blunder"
  case .won: "won"
  case .lost: "lost"
  case .draw: "draw"
  case .ended: "ended"
  case nil: "none"
  }
}
