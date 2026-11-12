import Book
import ChessCore
import Shared

/// Whether a position needs the engine before a run can offer or play anything there.
public func needsEngine(_ index: ReferenceIndex, _ fen: String) -> Bool {
  popularReplies(index, fen, 0).isEmpty && engineReplies(fen) == nil
}
