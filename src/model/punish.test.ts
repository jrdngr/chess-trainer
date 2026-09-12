import { describe, expect, it } from 'vitest';
import { applySan, fenTurn, legalMoves, START_FEN, walkSan } from '../chess/core';
import { bestCaptures, findBlunders, findPuzzle, isPunishment, opponentPositions, puzzlesFrom } from './punish';
import { referenceIndex } from './referenceIndex';
import { addLine, createRepertoire } from './repertoire';
import { buildSeedRepertoires } from '../store/seed';

const index = referenceIndex();

/** The position after these moves from the start. */
function at(sans: string[]): string {
  return walkSan(sans).fens[sans.length];
}

describe('counting what a capture wins', () => {
  it('wins the whole piece when nothing defends it', () => {
    // 1.d4 e5 (the Englund): dxe5 takes a pawn nothing is defending.
    const best = bestCaptures(at(['d4', 'e5']));
    expect(best.map((c) => c.san)).toContain('dxe5');
    expect(best[0].gain).toBe(1);
  });

  it('counts a defended pawn as an even trade, not a win', () => {
    // 1.e4 d5: exd5 takes a pawn, but the queen takes straight back.
    const best = bestCaptures(at(['e4', 'd5']));
    expect(best.find((c) => c.san === 'exd5')?.gain ?? 1).toBe(0);
  });

  it('subtracts the recapture', () => {
    // 1.d4 d5 2.c4 e6 3.Nc3 Nf6 4.Bg5: taking on f6 is met by the queen.
    const fen = at(['d4', 'd5', 'c4', 'e6', 'Nc3', 'Nf6', 'Bg5']);
    const capture = bestCaptures(fen).find((c) => c.san.startsWith('Bxf6'));
    // Bishop takes knight, queen takes bishop: three for three.
    expect(capture?.gain ?? 0).toBeLessThanOrEqual(0);
  });

  it('reports the square, so a punishment can be tied to a move', () => {
    const fen = at(['e4', 'd5']);
    expect(bestCaptures(fen).every((c) => c.to.length === 2)).toBe(true);
    expect(bestCaptures(fen).find((c) => c.san === 'exd5')?.to).toBe('d5');
  });

  it('finds nothing where there is nothing to take', () => {
    expect(bestCaptures(START_FEN)).toEqual([]);
  });
});

describe('finding a blunder', () => {
  it('catches a queen taking a defended pawn', () => {
    // 1.d4 d5 2.c4 e6 3.Nc3 Nf6 4.cxd5 and Qxd5?? runs into Nxd5.
    const fen = at(['d4', 'd5', 'c4', 'e6', 'Nc3', 'Nf6', 'cxd5']);
    const blunder = findBlunders(fen).find((b) => b.san === 'Qxd5');
    expect(blunder).toBeDefined();
    expect(blunder!.answers).toContain('Nxd5');
    // Queen for a pawn.
    expect(blunder!.gain).toBeGreaterThanOrEqual(5);
    expect(blunder!.greedy).toBe(true);
  });

  it('does not call an even trade a blunder', () => {
    // 1.d4 d5 2.c4 e6 3.Nc3 Nf6 4.cxd5 exd5 5.Bg5 Bb4 6.e3 and Bxc3+ bxc3 is
    // bishop for knight, which is not a mistake however big the recapture is.
    const fen = at(['d4', 'd5', 'c4', 'e6', 'Nc3', 'Nf6', 'cxd5', 'exd5', 'Bg5', 'Bb4', 'e3']);
    expect(findBlunders(fen).map((b) => b.san)).not.toContain('Bxc3+');
  });

  it('only looks at moves a player would have a reason to make', () => {
    const fen = at(['d4', 'd5', 'c4']);
    for (const blunder of findBlunders(fen)) {
      const move = legalMoves(fen).find((m) => m.san === blunder.san)!;
      const check = blunder.san.includes('+') || blunder.san.includes('#');
      expect(!!move.captured || check, blunder.san).toBe(true);
    }
  });

  it('punishes on the square they moved to, not somewhere else', () => {
    const fen = at(['d4', 'd5', 'c4', 'e6', 'Nc3', 'Nf6', 'cxd5']);
    for (const blunder of findBlunders(fen)) {
      const move = legalMoves(fen).find((m) => m.san === blunder.san)!;
      for (const answer of blunder.answers) {
        const reply = legalMoves(blunder.after).find((m) => m.san === answer)!;
        expect(reply.to).toBe(move.to);
      }
    }
  });

  it('leaves prepared and book moves alone', () => {
    const fen = at(['d4', 'd5', 'c4', 'e6', 'Nc3', 'Nf6', 'cxd5']);
    const all = findBlunders(fen).map((b) => b.san);
    expect(all).toContain('Qxd5');
    expect(findBlunders(fen, { known: (san) => san === 'Qxd5' }).map((b) => b.san)).not.toContain(
      'Qxd5',
    );
  });

  it('says nothing about a quiet position', () => {
    expect(findBlunders(START_FEN)).toEqual([]);
  });
});

describe('drawing puzzles from a repertoire', () => {
  const reps = buildSeedRepertoires();

  it('only looks at positions where the opponent is on move', () => {
    for (const rep of reps) {
      for (const spot of opponentPositions(rep, 8)) {
        expect(fenTurn(spot.fen)).not.toBe(rep.color);
        expect(spot.prepared.size).toBeGreaterThan(0);
      }
    }
  });

  it('produces sound puzzles: the answer really is legal and really wins', () => {
    for (const rep of reps) {
      const puzzles = puzzlesFrom(rep, index, { maxPly: 10 });
      expect(puzzles.length).toBeGreaterThan(0);
      for (const puzzle of puzzles) {
        // The blunder is legal from the position it claims.
        expect(applySan(puzzle.fen, puzzle.blunder)?.after).toBe(puzzle.after);
        expect(puzzle.answers.length).toBeGreaterThan(0);
        for (const answer of puzzle.answers) {
          expect(applySan(puzzle.after, answer), `${answer} after ${puzzle.blunder}`).not.toBeNull();
        }
        expect(puzzle.gain).toBeGreaterThanOrEqual(2);
        // It is your turn in the position you are shown.
        expect(fenTurn(puzzle.after)).toBe(puzzle.color);
      }
    }
  });

  it('never asks you to punish a move the book plays', () => {
    for (const rep of reps) {
      for (const puzzle of puzzlesFrom(rep, index, { maxPly: 10 })) {
        const book = index.entries.get(walkSan(puzzle.path).fens[puzzle.path.length].split(' ').slice(0, 4).join(' '));
        expect(book?.moves.some((m) => m.san === puzzle.blunder) ?? false).toBe(false);
      }
    }
  });

  it('finds one quickly, without working out all of them', () => {
    const rep = reps[0];
    const started = Date.now();
    const puzzle = findPuzzle(rep, index, { seed: 4 });
    expect(puzzle).not.toBeNull();
    // Generous: the point is that it stops early rather than scanning everything.
    expect(Date.now() - started).toBeLessThan(2000);
  });

  it('gives different puzzles on different draws', () => {
    const rep = buildSeedRepertoires()[0];
    const seen = new Set<string>();
    for (let seed = 0; seed < 12; seed += 1) {
      const puzzle = findPuzzle(rep, index, { seed });
      if (puzzle) seen.add(`${puzzle.path.join('')}${puzzle.blunder}`);
    }
    expect(seen.size).toBeGreaterThan(4);
  });

  it('accepts every answer it lists and nothing else', () => {
    const puzzle = findPuzzle(buildSeedRepertoires()[0], index, { seed: 9 })!;
    for (const answer of puzzle.answers) expect(isPunishment(puzzle, answer)).toBe(true);
    expect(isPunishment(puzzle, 'Ke2')).toBe(false);
  });

  it('has nothing to offer a repertoire with no prepared replies', () => {
    const bare = createRepertoire('White — bare', 'w', 'rep_bare');
    expect(puzzlesFrom(bare, index)).toEqual([]);
    expect(findPuzzle(bare, index, { seed: 1 })).toBeNull();
  });

  it('reads a one-line repertoire without inventing anything', () => {
    let rep = createRepertoire('White — tiny', 'w', 'rep_tiny');
    rep = addLine(rep, ['d4', 'd5', 'c4', 'e6'], 'seed').rep;
    for (const puzzle of puzzlesFrom(rep, index)) {
      expect(applySan(puzzle.fen, puzzle.blunder)).not.toBeNull();
    }
  });
});
