/**
 * Link every book move to the position it leads to.
 *
 * The app needs the book as a graph — what leads where, for regions, and what
 * follows what, for the picker's difficulty — and working that out means
 * playing every move in the book through chess.js. That is tens of thousands
 * of moves and several seconds, so it is done once here, when the book is
 * built, rather than on every device that opens the app.
 *
 * Each move row gains a fifth field: the index of the position it leads to in
 * `positions`, or -1 where that position is not in the book.
 */
import { Chess } from 'chess.js';

export function linkBook(book) {
  const at = new Map(book.positions.map(([key], i) => [key, i]));
  for (const [key, , moves] of book.positions) {
    const chess = new Chess(`${key} 0 1`);
    for (const move of moves) {
      let next = -1;
      try {
        chess.move(move[0]);
        next = at.get(chess.fen().split(' ').slice(0, 4).join(' ')) ?? -1;
        chess.undo();
      } catch {
        next = -1;
      }
      move[4] = next;
    }
  }
  book.version = 2;
  return book;
}
