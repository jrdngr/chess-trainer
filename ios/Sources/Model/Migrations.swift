import Book

/// The save's version. A save from before it is brought up by `migrate`
/// once the book is loaded; a new save starts at it.
public let SAVE_VERSION = 1

extension AppState {
  /// Brings a save from an older version up to this one, step by step.
  /// Returns whether anything changed.
  /// 1: the Playbook holds only book moves.
  @discardableResult
  public mutating func migrate(_ index: ReferenceIndex) -> Bool {
    if version >= SAVE_VERSION { return false }
    if version < 1 { removeNonBookMoves(index) }
    version = SAVE_VERSION
    return true
  }
}
