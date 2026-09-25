import { describe, expect, it } from 'vitest';
import { walkSan } from '../chess/core';
import { movesToDraw, popularReplies } from './growth';
import { nudgeArrows, openingOf, reachable, sameMove, type NudgePrefs } from './nudge';
import { referenceIndex } from './referenceIndex';
import { addLine, createRepertoire } from './repertoire';
import type { Repertoire } from './types';

const index = referenceIndex();

function rep(color: 'w' | 'b', lines: string[]): Repertoire {
  let out = createRepertoire('Test', color, `r_${color}`);
  for (const line of lines) out = addLine(out, line.split(' '), 'reference').rep;
  return out;
}

/** Three King's Indians, each with ...e5. */
const kid = rep('b', [
  'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O Be2 e5',
  'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 f3 O-O Be3 e5',
  'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nge2 O-O Ng3 e5',
]);

function arrowsAt(r: Repertoire, line: string, prefs: Partial<NudgePrefs> = {}) {
  const path = line.split(' ');
  const fen = walkSan(path).fens.at(-1)!;
  return nudgeArrows(
    r,
    index,
    path,
    fen,
    movesToDraw(index, fen),
    popularReplies(index, fen, 1),
    { priority: 'transposition', pawns: false, ...prefs },
    1,
  );
}

const tone = (arrows: ReturnType<typeof arrowsAt>, san: string) =>
  arrows.find((arrow) => arrow.san === san)?.tone;

describe('nudging toward the familiar move', () => {
  it('greens a move you play in other lines of the same opening', () => {
    const arrows = arrowsAt(kid, 'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O h3');
    expect(tone(arrows, 'e5')).toBe('toward');
    expect(arrows.find((arrow) => arrow.tone === 'toward')!.reason).toMatch(/You play e5 in 3 /);
  });

  it('pulls a familiar move the book ranks too low onto the board, in yellow', () => {
    const line = 'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Be2 O-O Bg5';
    const fen = walkSan(line.split(' ')).fens.at(-1)!;
    expect(movesToDraw(index, fen).map((move) => move.san)).not.toContain('e5');
    const arrows = arrowsAt(kid, line);
    expect(arrows).toHaveLength(3);
    expect(tone(arrows, 'e5')).toBe('toward-far');
  });

  it('greens a move that transposes into a line you have', () => {
    const classical = rep('b', ['d4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O Be2 e5']);
    // The same position by another move order: Be2 before Nf3.
    const arrows = arrowsAt(classical, 'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Be2 O-O Nf3');
    const green = arrows.find((arrow) => arrow.tone === 'toward')!;
    expect(green.san).toBe('e5');
    expect(green.reason).toMatch(/^e5 transposes into your /);
  });

  it('colours nothing on a repertoire with nothing in the opening', () => {
    const arrows = arrowsAt(rep('b', ['e4 c5']), 'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O h3');
    expect(arrows.every((arrow) => !arrow.tone)).toBe(true);
  });
});

describe('the reverse signal', () => {
  it('reds a move you have chosen against, at most once', () => {
    const arrows = arrowsAt(kid, 'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O h3', { priority: 'habit' });
    expect(tone(arrows, 'c5')).toBe('away');
    expect(arrows.filter((arrow) => arrow.tone === 'away')).toHaveLength(1);
  });

  it('never reds the green move', () => {
    for (const priority of ['transposition', 'habit'] as const) {
      const arrows = arrowsAt(kid, 'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Be2 O-O Bg5', { priority });
      const green = arrows.filter((arrow) => arrow.tone?.startsWith('toward'));
      expect(green).toHaveLength(1);
      expect(green[0].tone).not.toBe('away');
    }
  });

  it('reds a pawn move that closes off lines you still could reach', () => {
    const arrows = arrowsAt(kid, 'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Be2 O-O Bg5');
    const red = arrows.find((arrow) => arrow.tone === 'away')!;
    expect(red.reason).toMatch(/closes off 3 of your/);
  });
});

describe('pawn structure', () => {
  it('counts reaching your usual pawns only when the toggle is on', () => {
    // No e5 habit in this opening — only the structure after ...e5.
    const r = rep('b', ['d4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O Be2 e5']);
    const line = 'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 h3 O-O Be3';
    const off = arrowsAt(r, line, { priority: 'habit' });
    const on = arrowsAt(r, line, { priority: 'habit', pawns: true });
    expect(off.some((arrow) => arrow.reason?.includes('pawns'))).toBe(false);
    expect(on.find((arrow) => arrow.tone === 'toward')?.reason).toMatch(/^e5 reaches your usual .*pawns$/);
  });
});

describe('the pieces', () => {
  it('treats captures and checks as the same move', () => {
    expect(sameMove('Nxe5+')).toBe('Ne5');
    expect(sameMove('O-O')).toBe('O-O');
  });

  it('files a line under the family of its deepest name', () => {
    expect(openingOf(index, 'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6'.split(' '))).toMatch(/King's Indian/);
  });

  it('knows which positions a pawn push shuts off', () => {
    const [start, afterE4] = walkSan(['e4']).fens;
    expect(reachable(start, afterE4)).toBe(true);
    expect(reachable(afterE4, start)).toBe(false);
    const afterNf3 = walkSan(['Nf3']).fens[1];
    // Pieces can go back; pawns cannot.
    expect(reachable(afterNf3, start)).toBe(true);
  });
});
