import ChessCore
import Foundation
import Model
import Testing

/// A line is book for as long as the book has each move, for either side.
@Test func bookLengthStopsAtTheFirstMoveTheBookLacks() {
  #expect(bookLength(bookIndex, line("e4 e5 Nf3 Nc6 Bc4")) == 5)
  #expect(bookLength(bookIndex, line("e4 g5 d4 h6")) == 1)
  #expect(bookLength(bookIndex, []) == 0)
}
