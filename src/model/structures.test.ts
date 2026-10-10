import { describe, expect, it } from 'vitest';
import { START_FEN } from '../chess/core';
import { goalRoute } from './boardHints';
import { planFor, placeSquare, stepText, STRUCTURE_TEMPLATES, structureLabel, structureOf } from './structures';

const id = (fen: string) => structureOf(fen)?.template.id ?? null;
const side = (fen: string) => structureOf(fen)?.a ?? null;

describe('structureOf', () => {
  it('names nothing at the start', () => {
    expect(structureOf(START_FEN)).toBeNull();
  });

  it.each([
    ['stonewall', 'rnbqkb1r/ppp1pppp/5n2/3p4/3P1P2/2P1P3/PP4PP/RNBQKBNR w KQkq - 0 1'],
    ['carlsbad', 'r1bq1rk1/pp1nbppp/2p2n2/3p2B1/3P4/2NBP3/PPQ2PPP/R3K1NR w KQ - 0 1'],
    ['french-chain', 'rnbqkbnr/pp3ppp/4p3/2ppP3/3P4/5N2/PPP2PPP/RNBQKB1R b KQkq - 0 1'],
    ['caro-advance', 'rn1qkbnr/pp2pppp/2p5/3pPb2/3P4/8/PPP2PPP/RNBQKBNR w KQkq - 0 1'],
    ['czech-benoni', 'rnbqkb1r/pp3ppp/3p1n2/2pPp3/2P1P3/2N5/PP3PPP/R1BQKBNR w KQkq - 0 1'],
    ['kid-chain', 'r1bq1rk1/pppnn1bp/3p2p1/3Pp3/2P1Pp2/2N5/PP2BPPP/R1BQNRK1 w - - 0 1'],
    ['benoni', 'rnbqkb1r/pp3ppp/3p1n2/2pP4/4P3/2N5/PP3PPP/R1BQKBNR w KQkq - 0 1'],
    ['hedgehog', 'r1bqkb1r/3n1ppp/pp1ppn2/8/2P1P3/2N2N2/PP2BPPP/R1BQK2R w KQkq - 0 1'],
    ['botvinnik', 'r1bqk1nr/ppp2pbp/2np2p1/4p3/2P1P3/2NP2P1/PP3PBP/R1BQK1NR w KQkq - 0 1'],
    ['maroczy', 'r1bqkb1r/pp2pp1p/2np1np1/8/2P1P3/2N5/PP2BPPP/R1BQK1NR w KQkq - 0 1'],
    ['dragon', 'rnbqkb1r/pp2pp1p/3p1np1/8/3NP3/2N5/PPP2PPP/R1BQKB1R w KQkq - 0 1'],
    ['scheveningen', 'rnbqkb1r/1p3ppp/p2ppn2/8/3NP3/2N5/PPP2PPP/R1BQKB1R w KQkq - 0 1'],
    ['sicilian-e5', 'r1bqkb1r/1p3ppp/p1np1n2/4p3/4P3/2N2N2/PPP1BPPP/R1BQK2R w KQkq - 0 1'],
    ['hanging-pawns', 'r2q1rk1/p3bppp/1p2pn2/8/2PP4/5N2/P3BPPP/R2Q1RK1 w - - 0 1'],
    ['iqp', 'r1bq1rk1/pp2bppp/2n1pn2/8/3P4/2NB1N2/PP3PPP/R1BQ1RK1 w - - 0 1'],
    ['big-center', 'rnbqk2r/pp2ppbp/6p1/8/3PP3/2P5/P4PPP/R1BQKBNR w KQkq - 0 1'],
    ['central-tension', 'r1bqkbnr/ppp2ppp/2np4/4p3/3PP3/5N2/PPP2PPP/RNBQKB1R w KQkq - 0 1'],
    ['symmetrical', 'rnbqkbnr/ppp2ppp/8/3p4/3P4/8/PPP2PPP/RNBQKBNR w KQkq - 0 1'],
    ['open-center', 'r1bqk2r/ppp2ppp/2n2n2/8/1b6/2N2N2/PPP2PPP/R1BQKB1R w KQkq - 0 1'],
  ])('recognizes %s', (name, fen) => {
    expect(id(fen)).toBe(name);
  });

  it('covers every template with a test above', () => {
    expect(STRUCTURE_TEMPLATES).toHaveLength(19);
  });

  it('finds a structure owned by Black, and names the side', () => {
    const dutch = 'rnbq1rk1/pp2b1pp/2p1pn2/3p1p2/2PP4/5NP1/PP2PPBP/RNBQ1RK1 w - - 0 1';
    expect(id(dutch)).toBe('stonewall');
    expect(side(dutch)).toBe('b');
    expect(structureLabel(structureOf(dutch)!)).toBe('Stonewall (Black)');
    expect(structureLabel(structureOf('r1bq1rk1/pp1nbppp/2p2n2/3p2B1/3P4/2NBP3/PPQ2PPP/R3K1NR w KQ - 0 1')!)).toBe(
      'Carlsbad',
    );
  });
});

describe('plans', () => {
  it('mirrors the squares when the structure is Black’s', () => {
    expect(placeSquare('e5', 'b')).toBe('e4');
    expect(placeSquare('e5', 'w')).toBe('e5');
    const dutch = structureOf('rnbq1rk1/pp2b1pp/2p1pn2/3p1p2/2PP4/5NP1/PP2PPBP/RNBQ1RK1 w - - 0 1')!;
    // Black's knight wants e4; White's wants the hole on e5.
    expect(planFor(dutch, 'b')[0].goal).toEqual({ piece: 'n', to: 'e4' });
    expect(planFor(dutch, 'w')[0].goal).toEqual({ piece: 'n', to: 'e5' });
  });

  it('gives each side its own steps', () => {
    const carlsbad = structureOf('r1bq1rk1/pp1nbppp/2p2n2/3p2B1/3P4/2NBP3/PPQ2PPP/R3K1NR w KQ - 0 1')!;
    expect(planFor(carlsbad, 'w')[0].text).toMatch(/Minority attack/);
    expect(planFor(carlsbad, 'b')[0].text).toMatch(/kingside/);
  });
});

describe('goalRoute', () => {
  const carlsbad = 'r1bq1rk1/pp1nbppp/2p2n2/3p2B1/3P4/2NBP3/PPQ2PPP/R3K1NR w KQ - 0 1';

  it('routes a knight by its shortest hops', () => {
    expect(goalRoute(carlsbad, 'w', { piece: 'n', to: 'e5' })).toEqual({
      done: false,
      arrows: [
        { from: 'g1', to: 'f3' },
        { from: 'f3', to: 'e5' },
      ],
    });
  });

  it('pushes a pawn up its file when the way is clear', () => {
    expect(goalRoute(carlsbad, 'w', { piece: 'p', to: 'b5' }).arrows).toEqual([{ from: 'b2', to: 'b5' }]);
    // Black's c-pawn has nowhere to go: d5 is not on its file.
    expect(goalRoute(carlsbad, 'b', { piece: 'p', to: 'c5' }).arrows).toEqual([{ from: 'c6', to: 'c5' }]);
  });

  it('calls a step done once the piece is there', () => {
    expect(goalRoute(carlsbad, 'w', { piece: 'n', to: 'c3' })).toEqual({ done: true, arrows: [] });
  });
});

describe('stepText', () => {
  it('gives Black its dots and leaves White plain', () => {
    expect(stepText('Break with {c5}', 'w', 'b')).toBe('Break with ...c5');
    expect(stepText('Stop <b5> with {a4}', 'w', 'w')).toBe('Stop ...b5 with a4');
  });

  it('mirrors the squares when Black owns the structure', () => {
    // The Dutch Stonewall: Black's knight goes to e4, its pawn storm is ...g5–g4.
    expect(stepText('Plant a knight on e5', 'b', 'b')).toBe('Plant a knight on e4');
    expect(stepText('rook lift, or {g4–g5}', 'b', 'b')).toBe('rook lift, or ...g5–g4');
    expect(stepText('Break with {c5} to open the queenside', 'b', 'w')).toBe('Break with c4 to open the queenside');
  });

  it('leaves no markers in any plan', () => {
    for (const template of STRUCTURE_TEMPLATES) {
      for (const a of ['w', 'b'] as const) {
        for (const me of ['w', 'b'] as const) {
          for (const step of planFor({ template, a }, me)) expect(step.text).not.toMatch(/[{}<>]/);
        }
      }
    }
  });
});
