import ChessCore
import Engine
import Foundation
import Model
import Observation

/// One game against the engine.
@MainActor @Observable
final class PlayGame {
  struct Over: Equatable {
    var result: GameResult
    var reason: String
  }

  enum Intro { case announce, done }

  let prefs: PlayPrefs
  /// The game's selection, "Any favorite" resolved to one favorite for it.
  let selection: Selection
  let level: Level
  let color: ChessCore.Color
  let region: OpeningNode
  /// The repertoire this game is measured against and saved into.
  let target: Repertoire?
  /// One id for the life of the game, so ending it twice records it once.
  let gameId: String

  private(set) var moves: [String] = []
  private(set) var fen = START_FEN
  private(set) var thinking = false
  private(set) var evalLine: EngineLine?
  private(set) var over: Over?
  private(set) var offBook: String?
  private(set) var intro = Intro.announce
  var saved = false

  @ObservationIgnored private let store: AppStore
  @ObservationIgnored private let tree: OpeningTree
  @ObservationIgnored private let prep: [String: [String]]
  @ObservationIgnored private let engine = BasicEngine()
  @ObservationIgnored private let evalEngine = BasicEngine()
  @ObservationIgnored private var turnTask: Task<Void, Never>?
  @ObservationIgnored private var evalTask: Task<Void, Never>?
  @ObservationIgnored private var introTask: Task<Void, Never>?

  /// How long the announcement holds before the board, unless tapped away: `ANNOUNCE_MS`.
  static let announceMs = 2500
  /// The beat before a scripted move of the opening.
  static let scriptedMs = 420

  init(prefs: PlayPrefs, selection: Selection, store: AppStore, tree: OpeningTree) {
    self.prefs = prefs
    self.selection = selection
    self.store = store
    self.tree = tree
    level = levelById(prefs.level)
    region = nodeById(tree, selection.opening)
    switch selection.color {
    case .w: color = .w
    case .b: color = .b
    case .random: color = Env.random() < 0.5 ? .w : .b
    }
    let side = color
    target = store.state.repertoireList.first { $0.color == side }
    prep = prepIndex(target)
    gameId = "play_\(String(Int(Env.now()), radix: 36))_\(String(String(Env.random()).dropFirst(2).prefix(6)))"
  }

  var status: PositionStatus { positionStatus(fen) }
  var myTurn: Bool { fenTurn(fen) == color && over == nil }
  var held: Bool { intro != .done }
  /// The opening stays on a pill over the board until your first move.
  var showsPill: Bool { intro == .done && moves.count < (color == .w ? 1 : 2) }

  /// The announcement goes after its beat, or at a tap.
  func begin() {
    introTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(Self.announceMs))
      guard !Task.isCancelled else { return }
      self?.toBoard()
    }
  }

  func toBoard() {
    guard intro == .announce else { return }
    intro = .done
    advance()
  }

  func stop() {
    introTask?.cancel()
    turnTask?.cancel()
    evalTask?.cancel()
  }

  /// Your move, warned about when it leaves your own prep.
  func play(_ move: LegalMove) {
    guard myTurn, !held else { return }
    let key = positionKey(fen)
    if prefs.warnOffBook, let known = prep[key], !known.isEmpty, !known.contains(move.san), let target {
      offBook = "\(move.san) \u{2014} your prep says \(known.joined(separator: " or "))"
      let mistake = Mistake(source: .play, repertoireId: target.id, key: key, fen: fen, path: moves, played: move.san, expected: known[0])
      store.update { $0.logMistake(mistake) }
    } else {
      offBook = nil
    }
    Haptics.buzz(10, on: store.state.settings.hapticFeedback)
    push(move)
  }

  func takeBack() {
    guard moves.count >= 2 else { return }
    turnTask?.cancel()
    thinking = false
    moves = Array(moves.dropLast(fenTurn(fen) == color ? 2 : 1))
    fen = walkSan(moves).fens.last ?? START_FEN
    over = nil
    offBook = nil
    advance()
  }

  func resign() { end(.loss, "resignation") }

  private func push(_ move: LegalMove) {
    moves.append(move.san)
    fen = move.after
    advance()
  }

  /// After every change: settle a finished game, or start the engine's turn or the eval.
  private func advance() {
    turnTask?.cancel()
    evalTask?.cancel()
    guard over == nil else { return }
    let status = status
    if status.gameOver {
      if status.checkmate {
        end(fenTurn(fen) == color ? .loss : .win, "checkmate")
      } else {
        end(.draw, status.stalemate ? "stalemate" : "the rules")
      }
      return
    }
    if fenTurn(fen) == color { weigh() } else if !held { engineTurn() }
  }

  /// A finished game is kept with the imports; the repertoire is only written by Save.
  private func end(_ result: GameResult, _ reason: String) {
    turnTask?.cancel()
    evalTask?.cancel()
    thinking = false
    over = Over(result: result, reason: reason)
    if let game = playedGame(id: gameId, color: color, moves: moves, result: result, level: level, at: Env.now()) {
      store.update { $0.recordPlayGame(game) }
    }
    let score = result == .draw ? "1/2-1/2" : pgnResult(won: result == .win, color: color)
    let record = GameRecord(
      id: gameId, mode: .play, at: Env.now(), color: color, picked: pickedFor(selection, saved: store.state.settings.selection),
      opening: region.id, moves: moves, result: score, termination: reason == "the rules" ? "draw" : reason)
    store.update { $0.recordGame(record) }
  }

  /// The engine's move: the selected opening's move order while the game is
  /// still on it, then a search picked for this level.
  private func engineTurn() {
    let fen = fen
    let onLine = region.depth > 0 && moves.count < region.sans.count
      && moves.enumerated().allSatisfy { region.sans[$0.offset] == $0.element }
      && lineStatus(tree, region, moves) == .onWay
    let scripted = onLine ? applySan(fen, region.sans[moves.count]) : nil
    thinking = true
    turnTask = Task { [weak self, engine, level] in
      var move = scripted
      if move == nil {
        let snap = await engine.analyse(fen, EngineLimits(depth: level.depth, multiPv: level.multiPv))
        move = chooseMove(snap.lines, level, Env.random).flatMap { applyUci(fen, $0) }
      } else {
        try? await Task.sleep(for: .milliseconds(Self.scriptedMs))
      }
      guard let self, !Task.isCancelled, self.fen == fen else { return }
      self.thinking = false
      if let move { self.push(move) }
    }
  }

  /// A quiet evaluation for the bar, only when asked for.
  private func weigh() {
    guard prefs.showEval, store.state.settings.engineEnabled else { return }
    let fen = fen
    evalTask = Task { [weak self, evalEngine] in
      let snap = await evalEngine.analyse(fen, EngineLimits(depth: 10, multiPv: 1))
      guard let self, !Task.isCancelled, self.fen == fen, let line = snap.lines.first else { return }
      self.evalLine = line
    }
  }
}

/// What the repertoire prepares at a position, by key, for the off-book warning.
func prepIndex(_ rep: Repertoire?) -> [String: [String]] {
  guard let rep else { return [:] }
  var out: [String: [String]] = [:]
  func walk(_ nodeId: String?) {
    let fen = fenAt(rep, nodeId)
    let kids = childrenOf(rep, nodeId)
    if !kids.isEmpty && fenTurn(fen) == rep.color {
      var existing = out[positionKey(fen)] ?? []
      for kid in kids where !existing.contains(kid.san) { existing.append(kid.san) }
      out[positionKey(fen)] = existing
    }
    for kid in kids { walk(kid.id) }
  }
  walk(nil)
  return out
}

/// A Playbook's name without its side.
func displayName(_ name: String) -> String {
  let trimmed = name.replacingOccurrences(of: #"^\s*(white|black)\s*[—–\-:]\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
    .trimmingCharacters(in: .whitespaces)
  return trimmed.isEmpty ? name : trimmed
}
