import { describe, expect, it } from 'vitest';
import {
  applyMove,
  applySan,
  applyUci,
  isLightSquare,
  isPromotion,
  kingSquare,
  legalMoves,
  material,
  piecesFromFen,
  plyOf,
  positionKey,
  positionStatus,
  sansToMoveText,
  START_FEN,
  walkSan,
} from './core';

describe('legal moves', () => {
  it('gives 20 legal moves from the start position', () => {
    expect(legalMoves(START_FEN)).toHaveLength(20);
  });

  it('rejects an illegal move', () => {
    expect(applySan(START_FEN, 'e5')).toBeNull();
    expect(applyMove(START_FEN, 'e2', 'e5')).toBeNull();
  });

  it('only allows moves that answer a check', () => {
    // 1. e4 d5 2. Bb5+ — every legal reply must address the check.
    const fen = walkSan(['e4', 'd5', 'Bb5+']).fens.at(-1)!;
    expect(positionStatus(fen).check).toBe(true);
    const sans = legalMoves(fen).map((m) => m.san);
    expect(sans).toEqual(expect.arrayContaining(['c6', 'Nc6', 'Bd7', 'Nd7', 'Qd7']));
    expect(sans).not.toContain('a6');
    expect(sans).not.toContain('e6');
  });

  it('handles en passant', () => {
    const { moves } = walkSan(['e4', 'a6', 'e5', 'd5']);
    expect(moves).toHaveLength(4);
    const fen = moves[3].after;
    const ep = legalMoves(fen).find((m) => m.san === 'exd6');
    expect(ep).toBeDefined();
    expect(ep!.to).toBe('d6');
  });

  it('handles castling', () => {
    const { moves } = walkSan(['e4', 'e5', 'Nf3', 'Nc6', 'Bc4', 'Bc5']);
    const fen = moves[moves.length - 1].after;
    const castle = applySan(fen, 'O-O');
    expect(castle).not.toBeNull();
    expect(piecesFromFen(castle!.after).find((p) => p.square === 'g1')?.type).toBe('k');
    expect(piecesFromFen(castle!.after).find((p) => p.square === 'f1')?.type).toBe('r');
  });

  it('detects promotion squares', () => {
    const fen = '8/P7/8/8/8/8/8/K6k w - - 0 1';
    expect(isPromotion(fen, 'a7', 'a8')).toBe(true);
    const promoted = applyMove(fen, 'a7', 'a8', 'q');
    expect(promoted?.san).toBe('a8=Q+');
  });

  it('parses UCI moves', () => {
    expect(applyUci(START_FEN, 'e2e4')?.san).toBe('e4');
    expect(applyUci(START_FEN, 'e2e5')).toBeNull();
  });

  it('reports checkmate', () => {
    const { moves } = walkSan(['f3', 'e5', 'g4', 'Qh4']);
    const status = positionStatus(moves[3].after);
    expect(status.checkmate).toBe(true);
    expect(status.gameOver).toBe(true);
  });

  it('finds the king', () => {
    expect(kingSquare(START_FEN, 'w')).toBe('e1');
    expect(kingSquare(START_FEN, 'b')).toBe('e8');
  });
});

describe('position identity', () => {
  it('ignores move counters so transpositions collapse', () => {
    const a = walkSan(['e4', 'e5', 'Nf3', 'Nc6']).fens.at(-1)!;
    const b = walkSan(['Nf3', 'Nc6', 'e4', 'e5']).fens.at(-1)!;
    expect(a).not.toBe(b);
    expect(positionKey(a)).toBe(positionKey(b));
  });

  it('computes ply from the FEN counters', () => {
    expect(plyOf(START_FEN)).toBe(0);
    const fens = walkSan(['e4', 'c5', 'Nf3']).fens;
    expect(plyOf(fens[1])).toBe(1);
    expect(plyOf(fens[3])).toBe(3);
  });
});

describe('board helpers', () => {
  it('knows square colours', () => {
    expect(isLightSquare('a1')).toBe(false);
    expect(isLightSquare('h1')).toBe(true);
    expect(isLightSquare('e4')).toBe(true);
  });

  it('renders numbered move text', () => {
    expect(sansToMoveText(['e4', 'c5', 'Nf3', 'd6'])).toBe('1. e4 c5 2. Nf3 d6');
  });

  it('renders move text starting from black', () => {
    const fen = walkSan(['e4']).fens.at(-1)!;
    expect(sansToMoveText(['c5', 'Nf3'], fen)).toBe('1... c5 2. Nf3');
  });
});

describe('material', () => {
  it('has nothing taken and nobody ahead at the start', () => {
    const { byWhite, byBlack, lead } = material(START_FEN);
    expect(byWhite).toEqual([]);
    expect(byBlack).toEqual([]);
    expect(lead).toBe(0);
  });

  it('reads what is missing off the board, pawns first', () => {
    // White is a knight and a pawn up: Black has lost N + 2P, White 1P.
    const { byWhite, byBlack, lead } = material('rnbqkb1r/pp3ppp/8/8/8/8/PP3PPP/RNBQKBNR w KQkq - 0 1');
    expect(byWhite).toEqual(['p', 'p', 'p', 'n']);
    expect(byBlack).toEqual(['p', 'p', 'p']);
    expect(lead).toBe(3);
  });

  it('counts the lead from the pieces actually on the board', () => {
    // A queen each side and nothing else: level, whatever the captures read.
    expect(material('4k3/8/8/8/8/8/8/3QK3 w - - 0 1').lead).toBe(9);
    expect(material('3qk3/8/8/8/8/8/8/3QK3 w - - 0 1').lead).toBe(0);
    // A promoted queen is worth a queen, not the pawn it used to be.
    expect(material('Q3k3/8/8/8/8/8/8/3QK3 w - - 0 1').lead).toBe(18);
  });

  it('names the side ahead by the sign of the lead', () => {
    expect(material('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKB1R w KQkq - 0 1').lead).toBe(-3);
  });
});
