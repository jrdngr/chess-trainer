import { describe, expect, it } from 'vitest';
import { roleArrows } from './answerArrows';

// The Italian after 3...Bc5, White to answer.
const fen = 'r1bqk1nr/pppp1ppp/2n5/2b1p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4';
const listed = [
  { san: 'c3', share: 45 },
  { san: 'd3', share: 30 },
  { san: 'O-O', share: 16 },
  { san: 'b4', share: 5 },
];
const roles = (deltas: Record<string, number | null>, moves = listed) =>
  roleArrows(fen, moves, (san) => deltas[san] ?? null).map((arrow) => `${arrow.san}:${arrow.role}`);

describe("Growth's arrows by who recommends them", () => {
  it("draws strong players' top reply and the engine's best two", () => {
    expect(roles({ c3: -20, d3: -10, 'O-O': 0, b4: -40 })).toEqual(['c3:strong', 'O-O:engine', 'd3:engine-next']);
  });

  it("keeps a move both agree on blue and brings in the engine's next", () => {
    expect(roles({ c3: 0, d3: -10, 'O-O': -20, b4: -40 })).toEqual(['c3:strong', 'd3:engine', 'O-O:engine-next']);
  });

  it('draws only the blue arrow until the engine has weighed anything', () => {
    expect(roles({})).toEqual(['c3:strong']);
  });

  it("draws the engine's three past the book, in its order until it has weighed them", () => {
    const engine = ['O-O', 'd3', 'c3', 'b4'].map((san) => ({ san, share: 0 }));
    expect(roles({}, engine)).toEqual(['O-O:engine', 'd3:engine-next', 'c3:engine-next']);
    expect(roles({ 'O-O': -30, d3: 0, c3: -10, b4: -20 }, engine)).toEqual([
      'd3:engine',
      'c3:engine-next',
      'b4:engine-next',
    ]);
  });
});
