import { describe, expect, it } from 'vitest';
import { START_FEN } from '../chess/core';
import {
  asMover,
  breakCandidates,
  holes,
  kingReport,
  kingsLens,
  loosePieces,
  newlyLoose,
  outposts,
  pawnFeatures,
  pawnsLens,
  piecesLens,
  spaceCount,
  spaceLens,
  structureName,
  threatsLens,
} from './boardHints';

const feature = (fen: string, square: string) => pawnFeatures(fen).find((p) => p.square === square)!;

describe('pawns', () => {
  it('finds nothing to say about the starting pawns', () => {
    expect(pawnsLens(START_FEN).tags).toEqual([]);
    expect(holes(START_FEN, 'w')).toEqual([]);
    expect(structureName(START_FEN)).toBeNull();
  });

  it('tags a lone passed pawn as passed', () => {
    const fen = '8/8/4k3/8/3P4/8/5K2/8 w - - 0 1';
    expect(feature(fen, 'd4')).toMatchObject({ passed: true, isolated: true });
    expect(pawnsLens(fen).tags).toEqual([{ square: 'd4', tone: 'good' }]);
  });

  it('finds a backward pawn whose neighbours have gone ahead', () => {
    const fen = '4k3/8/3p4/2p1p3/2P1P3/8/8/4K3 w - - 0 1';
    expect(feature(fen, 'd6')).toMatchObject({ backward: true, passed: false, isolated: false });
    expect(feature(fen, 'c5').backward).toBe(false);
  });

  it('marks the holes no pawn can guard again', () => {
    const fen = '4k3/8/3p4/2p1p3/2P1P3/8/8/4K3 w - - 0 1';
    expect(holes(fen, 'w')).toContain('d4');
    expect(holes(fen, 'w')).toContain('d3');
  });

  it('names common structures', () => {
    expect(structureName('r1bq1rk1/pp2bppp/2n1pn2/8/3P4/2NB1N2/PP3PPP/R1BQ1RK1 w - - 0 1')).toBe(
      'Isolated queen pawn (White)',
    );
    expect(structureName('r1bq1rk1/pp1nbppp/2p2n2/3p2B1/3P4/2NBP3/PPQ2PPP/R3K1NR w KQ - 0 1')).toBe('Carlsbad');
    expect(structureName('r1bq1rk1/pppnn1bp/3p2p1/3Pp3/2P1Pp2/2N5/PP2BPPP/R1BQNRK1 w - - 0 1')).toBe(
      "King's Indian chain",
    );
    expect(structureName('r1bqkb1r/1p3ppp/p1np1n2/4p3/4P3/2N2N2/PPP1BPPP/R1BQK2R w KQkq - 0 1')).toBe(
      'Sicilian ...e5 (d5 hole)',
    );
  });

  it('fades the pieces and names the structure', () => {
    const marks = pawnsLens('r1bq1rk1/pp1nbppp/2p2n2/3p2B1/3P4/2NBP3/PPQ2PPP/R3K1NR w KQ - 0 1');
    expect(marks.ghost).toBe(true);
    expect(marks.caption).toBe('Carlsbad');
  });
});

describe('breaks', () => {
  it('lists captures of pawns and pushes that attack one', () => {
    const fen = 'rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w KQkq d6 0 2';
    const moves = breakCandidates(fen, 'w');
    expect(moves).toContain('e4d5');
    expect(moves).toContain('c2c4');
    expect(moves).not.toContain('a2a3');
  });

  it('hands the move over only when that leaves a real position', () => {
    expect(asMover(START_FEN, 'b')?.split(' ')[1]).toBe('b');
    expect(asMover(START_FEN, 'w')).toBe(START_FEN);
    // White is in check: Black cannot be the one to move.
    expect(asMover('6k1/8/8/8/8/8/8/3q2K1 w - - 0 1', 'b')).toBeNull();
  });
});

describe('pieces', () => {
  const sicilian = 'r1bqkb1r/1p3ppp/p1np1n2/4p3/4P3/2N2N2/PPP1BPPP/R1BQK2R w KQkq - 0 1';

  it('stars an outpost and routes a knight to it', () => {
    expect(outposts(sicilian, 'w')).toContain('d5');
    const marks = piecesLens(sicilian, 'w');
    expect(marks.stars).toContainEqual({ square: 'd5', side: 'mine' });
    expect(marks.arrows).toContainEqual({ from: 'c3', to: 'd5', tone: 'route' });
  });

  it('rings one worst piece per side', () => {
    const marks = piecesLens(sicilian, 'w');
    // Red for both sides: a ring means "worst", whoever's piece it is.
    expect(marks.rings).toHaveLength(2);
    expect(marks.rings?.every((r) => r.tone === 'bad')).toBe(true);
  });
});

describe('space', () => {
  it('counts nothing at the start', () => {
    expect(spaceCount(START_FEN, 'w')).toEqual({ mine: 0, theirs: 0 });
  });

  it('tints by margin and from your side', () => {
    // Two white rooks on the d-file against one black rook: d5 is strongly White's.
    const fen = '3r2k1/8/8/8/8/8/3R4/3RK3 w - - 0 1';
    const fromWhite = spaceLens(fen, 'w').tints!.find((t) => t.square === 'd3');
    expect(fromWhite).toMatchObject({ color: 'blue' });
    const fromBlack = spaceLens(fen, 'b').tints!.find((t) => t.square === 'd3');
    expect(fromBlack).toMatchObject({ color: 'red' });
  });

  it('leans an even fight to the cheaper attacker', () => {
    // e5: a white pawn and a black queen each attack it once; the pawn wins it.
    const fen = '6k1/4q3/8/8/3P4/8/8/6K1 w - - 0 1';
    const c = spaceLens(fen, 'w').tints!.find((t) => t.square === 'e5');
    expect(c).toMatchObject({ color: 'purple-blue' });
  });
});

describe('kings', () => {
  it('calls a castled king behind its pawns safe', () => {
    expect(kingReport('r4rk1/ppp2ppp/8/8/8/8/PPP2PPP/R4RK1 w - - 0 1', 'w')?.grade).toBe('safe');
  });

  it('calls a king in check under attack', () => {
    expect(kingReport('6k1/5ppp/8/8/8/8/8/3q2K1 w - - 0 1', 'w')?.grade).toBe('attacked');
  });

  it('marks missing shield pawns and open files', () => {
    const report = kingReport('r4rk1/ppp2ppp/8/8/8/8/PPP2P1P/R4RK1 w - - 0 1', 'w')!;
    expect(report.missingShield).toEqual(['g2']);
    expect(report.lines).toContainEqual({ from: 'g8', to: 'g1' });
  });

  it('names both kings from your side', () => {
    expect(kingsLens(START_FEN, 'b').caption).toBe('You: Safe · Them: Safe');
  });
});

describe('threats', () => {
  it('rings a queen hit by a rook, not the defended rook', () => {
    const fen = '4k3/8/8/3q4/8/8/3R4/4K3 w - - 0 1';
    expect(loosePieces(fen)).toEqual([{ square: 'd5', color: 'b', kind: 'hanging' }]);
  });

  it('draws what the last move newly threatens', () => {
    const before = '4k3/8/8/8/1n6/8/2Q5/4K3 b - - 0 1';
    const after = '4k3/8/8/8/8/3n4/2Q5/4K3 w - - 1 2';
    const marks = threatsLens(after, 'w', before);
    expect(marks.arrows).toContainEqual({ from: 'd3', to: 'e1', tone: 'threat' });
  });

  it('finds what a move leaves loose', () => {
    const before = '4k3/8/4p3/8/8/2N5/8/4K3 w - - 0 1';
    const after = '4k3/8/4p3/3N4/8/8/8/4K3 b - - 1 1';
    expect(newlyLoose(before, after, 'w', { from: 'c3', to: 'd5' })).toEqual(['d5']);
    expect(newlyLoose(before, before, 'w', { from: 'c3', to: 'c3' })).toEqual([]);
  });
});
