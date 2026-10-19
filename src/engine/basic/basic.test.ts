import { describe, expect, it } from 'vitest';
import { START_FEN, walkSan } from '../../chess/core';
import { Position } from './board';
import { search } from './search';

function perft(pos: Position, depth: number): number {
  if (depth === 0) return 1;
  let total = 0;
  for (const move of pos.pseudoMoves()) {
    if (!pos.make(move)) continue;
    total += perft(pos, depth - 1);
    pos.unmake(move);
  }
  return total;
}

const fenAfter = (sans: string[]) => walkSan(sans, START_FEN).fens.at(-1)!;

describe('backup engine board', () => {
  // Reference counts from the Chess Programming Wiki's perft results.
  it.each([
    [START_FEN, 3, 8902],
    ['r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1', 2, 2039],
    ['8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1', 3, 2812],
    ['r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1', 3, 9467],
    ['rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8', 2, 1486],
  ])('generates the right number of positions from %s', (fen, depth, nodes) => {
    expect(perft(new Position(fen), depth)).toBe(nodes);
  });
});

describe('backup engine search', () => {
  const quick = { maxDepth: 64, timeMs: 400, multiPv: 1 };

  it('takes a hanging queen', () => {
    const result = search('rnb1kbnr/pppp1ppp/8/4p1q1/3P4/2N5/PPP1PPPP/R1BQKBNR w KQkq - 0 1', quick)!;
    expect(result.lines[0].uci).toBe('c1g5');
  });

  it('finds a mate in one', () => {
    const result = search('6k1/5ppp/8/8/8/8/5PPP/3R2K1 w - - 0 1', quick)!;
    expect(result.lines[0].uci).toBe('d1d8');
    expect(result.lines[0].mate).toBe(1);
  });

  it('sees the recapture behind a queen raid', () => {
    // 1.d4 d5 2.c4 Nc6 3.cxd5 Qxd5 4.Nc3: the old evaluator took 4...Qc4 as winning the knight.
    const fen = fenAfter(['d4', 'd5', 'c4', 'Nc6', 'cxd5', 'Qxd5', 'Nc3']);
    const result = search(fen, { ...quick, multiPv: 3 })!;
    for (const line of result.lines) expect(Math.abs(line.score)).toBeLessThan(150);
  });

  it('finds the pawn 4.Nc3 drops in that line', () => {
    // Stockfish: 4...Qxd4, and 5.Qxd4 Nxd4 leaves Black a pawn up.
    const fen = fenAfter(['d4', 'd5', 'c4', 'Nc6', 'cxd5', 'Qxd5', 'Nc3']);
    const best = search(fen, { ...quick, timeMs: 800 })!.lines[0];
    expect(best.uci).toBe('d5d4');
    expect(best.score).toBeGreaterThan(0);
  });

  it('scores only the moves asked for, all at the same depth', () => {
    const result = search(START_FEN, { ...quick, multiPv: 3, searchmoves: ['e2e4', 'a2a3'] })!;
    expect(result.lines.map((l) => l.uci).sort()).toEqual(['a2a3', 'e2e4']);
    expect(result.lines[0].uci).toBe('e2e4');
  });

  it('stops near its time limit', () => {
    const started = Date.now();
    search(fenAfter(['e4', 'e5', 'Nf3', 'Nc6', 'Bb5', 'a6']), { maxDepth: 64, timeMs: 300, multiPv: 3 });
    expect(Date.now() - started).toBeLessThan(900);
  });

  it('has nothing to say with no legal moves', () => {
    expect(search('7k/5Q2/6K1/8/8/8/8/8 b - - 0 1', quick)).toBeNull();
  });
});

describe('backup engine hashing', () => {
  it('keeps its running key equal to one worked out from scratch', () => {
    const pos = new Position('r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1');
    const walk = (depth: number) => {
      for (const move of pos.pseudoMoves()) {
        if (!pos.make(move)) continue;
        expect([pos.keyLo, pos.keyHi]).toEqual(pos.freshKey());
        if (depth > 1) walk(depth - 1);
        pos.unmake(move);
      }
    };
    const before = [pos.keyLo, pos.keyHi];
    walk(2);
    expect([pos.keyLo, pos.keyHi]).toEqual(before);
  });
});
