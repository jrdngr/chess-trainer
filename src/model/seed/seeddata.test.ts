import { describe, expect, it } from 'vitest';
import { Chess } from 'chess.js';
import { BOOK_LINES } from './bookLines';
import { REFERENCE_GAMES } from './games';

function illegalIn(moves: string[]): string | null {
  const c = new Chess();
  for (const san of moves) {
    try {
      c.move(san);
    } catch {
      return san;
    }
  }
  return null;
}

describe('book lines', () => {
  it.each(BOOK_LINES.map((l) => [l.name, l] as const))('%s is legal', (_name, line) => {
    expect(illegalIn(line.moves)).toBeNull();
  });

  it('have unique ids', () => {
    const ids = BOOK_LINES.map((l) => l.id);
    expect(new Set(ids).size).toBe(ids.length);
  });
});

describe('reference games', () => {
  it.each(REFERENCE_GAMES.map((g) => [`${g.white}-${g.black}`, g] as const))('%s is legal', (_n, game) => {
    expect(illegalIn(game.moves)).toBeNull();
  });
});
