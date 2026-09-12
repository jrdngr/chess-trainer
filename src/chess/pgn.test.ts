import { describe, expect, it } from 'vitest';
import { allLines, mainline, parsePgn, renderMovetext, toPgn } from './pgn';

describe('parsePgn', () => {
  it('parses headers and a simple mainline', () => {
    const pgn = `[Event "Test"]\n[White "A"]\n[Black "B"]\n[Result "1-0"]\n\n1. e4 e5 2. Nf3 Nc6 3. Bb5 1-0`;
    const [game] = parsePgn(pgn);
    expect(game.headers.White).toBe('A');
    expect(game.result).toBe('1-0');
    expect(mainline(game)).toEqual(['e4', 'e5', 'Nf3', 'Nc6', 'Bb5']);
  });

  it('parses variations as siblings of the move they replace', () => {
    const pgn = '1. e4 c5 (1... e5 2. Nf3) 2. Nf3 d6';
    const [game] = parsePgn(pgn);
    // After 1.e4 there are two candidate replies.
    expect(game.moves[0].san).toBe('e4');
    expect(game.moves[0].children.map((c) => c.san)).toEqual(['c5', 'e5']);
    const lines = allLines(game).map((l) => l.sans.join(' '));
    expect(lines).toContain('e4 c5 Nf3 d6');
    expect(lines).toContain('e4 e5 Nf3');
  });

  it('handles nested variations', () => {
    const pgn = '1. d4 Nf6 2. c4 e6 (2... g6 3. Nc3 d5 (3... Bg7)) 3. Nc3 Bb4';
    const [game] = parsePgn(pgn);
    const lines = allLines(game).map((l) => l.sans.join(' '));
    expect(lines).toContain('d4 Nf6 c4 e6 Nc3 Bb4');
    expect(lines).toContain('d4 Nf6 c4 g6 Nc3 d5');
    expect(lines).toContain('d4 Nf6 c4 g6 Nc3 Bg7');
  });

  it('keeps comments and drops NAGs and annotations', () => {
    const pgn = '1. e4 {best by test} e5 $1 2. Nf3!? Nc6?!';
    const [game] = parsePgn(pgn);
    expect(game.moves[0].comment).toBe('best by test');
    expect(mainline(game)).toEqual(['e4', 'e5', 'Nf3', 'Nc6']);
  });

  it('stops at the first illegal move instead of throwing', () => {
    const [game] = parsePgn('1. e4 e5 2. Qxf7 Nc6');
    expect(mainline(game)).toEqual(['e4', 'e5']);
  });

  it('parses multiple games in one file', () => {
    const pgn = `[Event "One"]\n[Result "1-0"]\n\n1. e4 e5 1-0\n\n[Event "Two"]\n[Result "0-1"]\n\n1. d4 d5 0-1`;
    const games = parsePgn(pgn);
    expect(games).toHaveLength(2);
    expect(games[1].headers.Event).toBe('Two');
    expect(mainline(games[1])).toEqual(['d4', 'd5']);
  });
});

describe('PGN export', () => {
  it('round-trips a tree with a variation', () => {
    const text = renderMovetext([
      {
        san: 'e4',
        children: [
          { san: 'c5', children: [{ san: 'Nf3', children: [] }] },
          { san: 'e5', children: [] },
        ],
      },
    ]);
    const [game] = parsePgn(text);
    const lines = allLines(game).map((l) => l.sans.join(' '));
    expect(lines).toContain('e4 c5 Nf3');
    expect(lines).toContain('e4 e5');
  });

  it('emits headers with toPgn', () => {
    const pgn = toPgn({ Event: 'Repertoire', Result: '*' }, [{ san: 'e4', children: [] }]);
    expect(pgn).toContain('[Event "Repertoire"]');
    expect(pgn).toContain('1. e4 *');
  });
});
