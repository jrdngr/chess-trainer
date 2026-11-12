import ChessCore

/// The Playbook's changes to the saved state: `useStore`'s playbook
/// actions. Each logs what it did; the deletes hand back an undo.

/// A delete taken back: the tree as it was, with what the delete took from
/// cards, log and mistakes, and the event that records the undo.
public struct PlaybookUndo: Sendable {
  let repId: String
  let rep: Playbook
  let cards: [String: Card]
  let log: [ReviewLogEntry]
  let mistakes: [Mistake]
  let event: AppEvent
}

extension AppState {
  /// One tree per colour, so everything that saves a line asks for the side and gets the same tree back.
  public mutating func ensurePlaybook(_ color: Color) -> String {
    if let existing = playbookList.first(where: { $0.color == color }) { return existing.id }
    let rep = createPlaybook(playbookName(color), color)
    playbooks[rep.id] = rep
    playbookOrder.append(rep.id)
    return rep.id
  }

  public mutating func logEvent(_ event: AppEvent) {
    events = appendEvent(events, event)
  }

  @discardableResult
  public mutating func addLine(
    _ repId: String, _ sans: [String], _ source: SourceFor, via: EventPlace? = nil
  ) -> Int {
    guard let rep = playbooks[repId] else { return 0 }
    let res = Model.addLine(rep, sans, source)
    playbooks[repId] = res.rep
    if res.added > 0 {
      let name: String
      switch source {
      case .fixed(let s): name = s.rawValue
      case .each: name = "growth"
      }
      logEvent(AppEvent(kind: "add", via: via, playbookId: repId, color: rep.color, line: sans.joined(separator: " "), added: res.added, source: name))
    }
    return res.added
  }

  /// A move and everything after it.
  @discardableResult
  public mutating func removeNode(_ repId: String, _ nodeId: String, via: EventPlace? = nil) -> PlaybookUndo? {
    let undo = undoFor(repId, nodeId, kind: "remove-undo")
    guard undo != nil else { return nil }
    shrink(repId, { removeSubtree($0, nodeId) }) { before, after in
      AppEvent(kind: "remove", via: via, playbookId: repId, color: before.color, line: lineAt(before, nodeId)).with(removedBetween(before, after))
    }
    return undo
  }

  /// One line of an opening, with the moves only it had.
  @discardableResult
  public mutating func removeLine(_ repId: String, _ tipId: String) -> PlaybookUndo? {
    let undo = undoFor(repId, tipId, kind: "remove-undo")
    guard undo != nil else { return nil }
    shrink(repId, { pruneLine($0, tipId) }) { before, after in
      AppEvent(kind: "remove-line", playbookId: repId, color: before.color, line: lineAt(before, tipId)).with(removedBetween(before, after))
    }
    return undo
  }

  /// A derived opening, with the move order that only led to it.
  public mutating func removeOpening(_ repId: String, _ rootId: String, tips: [String]? = nil) {
    shrink(repId, { rep in tips.map { $0.reduce(rep) { pruneLine($0, $1) } } ?? pruneLine(rep, rootId) }) { before, after in
      AppEvent(kind: "remove-opening", playbookId: repId, color: before.color, line: lineAt(before, rootId)).with(removedBetween(before, after))
    }
  }

  /// A whole side's tree, with its schedule and logged mistakes.
  public mutating func removePlaybook(_ repId: String) {
    guard let gone = playbooks[repId] else { return }
    logEvent(AppEvent(kind: "remove-playbook", playbookId: repId, color: gone.color, count: gone.nodes.count))
    playbooks[repId] = nil
    playbookOrder.removeAll { $0 == repId }
    cards = cards.filter { $0.value.playbookId != repId }
    log.removeAll { $0.cardId.hasPrefix("\(repId)#") }
    mistakes.removeAll { $0.playbookId == repId }
  }

  public mutating func preferMove(_ repId: String, _ nodeId: String) {
    update(repId, { setPreferred($0, nodeId) }) { AppEvent(kind: "prefer", playbookId: repId, color: $0.color, line: lineAt($0, nodeId)) }
  }

  public mutating func annotate(_ repId: String, _ nodeId: String, _ note: String) {
    update(repId, { setNote($0, nodeId, note) }) { AppEvent(kind: "note", playbookId: repId, color: $0.color, line: lineAt($0, nodeId)) }
  }

  public mutating func reorder(_ repId: String, _ nodeId: String, _ delta: Int) {
    update(repId, { moveSibling($0, nodeId, delta) }) {
      AppEvent(kind: "reorder", playbookId: repId, color: $0.color, line: lineAt($0, nodeId), delta: delta)
    }
  }

  /// A reply strong players rarely choose, kept from Tidy's card.
  public mutating func tidyKeep(_ repId: String, _ nodeId: String) {
    guard let rep = playbooks[repId], rep.nodes[nodeId] != nil else { return }
    playbooks[repId]!.nodes[nodeId]!.keptAt = Env.now()
    logEvent(AppEvent(kind: "tidy-keep", playbookId: repId, color: rep.color, line: lineAt(rep, nodeId)))
  }

  /// That reply removed from Tidy's card, with everything under it.
  public mutating func tidyRemove(_ repId: String, _ nodeId: String) -> PlaybookUndo? {
    let undo = undoFor(repId, nodeId, kind: "tidy-remove-undo")
    guard undo != nil else { return nil }
    shrink(repId, { removeSubtree($0, nodeId) }) { before, after in
      AppEvent(kind: "tidy-remove", playbookId: repId, color: before.color, line: lineAt(before, nodeId)).with(removedBetween(before, after))
    }
    return undo
  }

  /// Tidy plays another move in place of yours: yours and everything under it
  /// go. The answer here changed, so what the old answer earned does not
  /// carry: the card starts over and the misses logged against it go.
  public mutating func tidySwitch(_ repId: String, _ nodeId: String, _ san: String) -> PlaybookUndo? {
    guard let rep = playbooks[repId], let node = rep.nodes[nodeId], let next = switchMove(rep, nodeId, san) else { return nil }
    let undo = undoFor(repId, nodeId, kind: "tidy-undo", to: san)
    shrink(repId, { _ in next }) { before, after in
      AppEvent(kind: "tidy-switch", playbookId: repId, color: before.color, line: lineAt(before, nodeId), to: san).with(removedBetween(before, after))
    }
    cards[cardId(repId, node.key)] = nil
    mistakes.removeAll { $0.playbookId == repId && $0.key == node.key }
    return undo
  }

  /// Puts back what a delete took.
  public mutating func undo(_ u: PlaybookUndo) {
    playbooks[u.repId] = u.rep
    cards = u.cards
    log = u.log
    mistakes = u.mistakes
    logEvent(u.event)
  }

  func undoFor(_ repId: String, _ nodeId: String, kind: String, to: String? = nil) -> PlaybookUndo? {
    guard let rep = playbooks[repId], rep.nodes[nodeId] != nil else { return nil }
    return PlaybookUndo(
      repId: repId, rep: rep, cards: cards, log: log, mistakes: mistakes,
      event: AppEvent(kind: kind, playbookId: repId, color: rep.color, line: lineAt(rep, nodeId), to: to))
  }

  mutating func update(_ repId: String, _ fn: (Playbook) -> Playbook, _ describe: (Playbook) -> AppEvent) {
    guard let rep = playbooks[repId] else { return }
    playbooks[repId] = fn(rep)
    logEvent(describe(rep))
  }

  /// Shrinks a tree, and drops what only existed for the positions that went:
  /// cards, review log entries and mistakes keyed by a position no longer in it.
  mutating func shrink(_ repId: String, _ fn: (Playbook) -> Playbook, _ describe: (Playbook, Playbook) -> AppEvent) {
    guard let rep = playbooks[repId] else { return }
    let next = fn(rep)
    let alive = Set(next.nodes.values.map(\.key))
    let orphaned = { (id: String, key: String) in id == repId && !alive.contains(key) }
    playbooks[repId] = next
    logEvent(describe(rep, next))
    cards = cards.filter { !orphaned($0.value.playbookId, $0.value.key) }
    log = log.filter { entry in
      let parts = entry.cardId.split(separator: "#", maxSplits: 1).map(String.init)
      return !orphaned(parts[0], parts.count > 1 ? parts[1] : "")
    }
    mistakes = mistakes.filter { !orphaned($0.playbookId, $0.key) }
  }
}
