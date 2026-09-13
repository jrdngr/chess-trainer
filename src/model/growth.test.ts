import { describe, expect, it } from 'vitest';
import { applySan, positionKey, START_FEN } from '../chess/core';
import {
  advance,
  answerHole,
  atHole,
  enterHole,
  evidenceFor,
  findCoverage,
  findHoles,
  growthRows,
  isUsersTurn,
  lineFor,
  MAX_ADDS,
  movesToDraw,
  nextHole,
  optionsAt,
  preparedHere,
  recommended,
  rowUrgency,
  startGrowth,
  steer,
  thinness,
} from './growth';
import { referenceIndex } from './referenceIndex';
import { addLine, createRepertoire, hasLine } from './repertoire';
import type { Repertoire } from './types';

const index = referenceIndex();

/** The shape a real user ends up with: one line saved from a run or a game. */
function thin(color: 'w' | 'b', line: string, name = 'Test'): Repertoire {
  const rep = createRepertoire(name, color, `r_${color}`);
  return addLine(rep, line.split(' '), 'reference').rep;
}

const white = thin('w', 'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3');
const black = thin('b', 'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6');

describe('finding holes', () => {
  it('finds the unanswered replies in a thin repertoire', () => {
    expect(findHoles(white, index).length).toBeGreaterThan(0);
    expect(findHoles(black, index).length).toBeGreaterThan(0);
  });

  it('counts a line that simply ends, which findGaps deliberately does not', () => {
    // 1.e4 c5 2.Nf3 d6 3.d4 cxd4 4.Nxd4 Nf6 5.Nc3 ends on White's move, so
    // Black is to move with nothing prepared. Every popular reply is a hole.
    const deep = findHoles(white, index).filter((hole) => hole.path.length === 9);
    expect(deep.length).toBeGreaterThan(0);
  });

  it('only ever asks about positions where the opponent is to move', () => {
    for (const rep of [white, black]) {
      for (const hole of findHoles(rep, index)) {
        const turn = hole.path.length % 2 === 0 ? 'w' : 'b';
        expect(turn).not.toBe(rep.color);
      }
    }
  });

  it('says whether answering a hole would widen the prep or only lengthen it', () => {
    const holes = findHoles(black, index);
    // The root is a junction: 1.d4 is answered, 1.e4 and the rest are not.
    const root = holes.find((hole) => hole.path.length === 0 && hole.san === 'e4');
    expect(root?.answered).toBe(1);
    // The tip: eight plies in, the prep stops and answers nothing at all.
    const tip = holes.find((hole) => hole.path.length === 8);
    expect(tip?.answered).toBe(0);
  });

  it('never reports a reply the repertoire already answers', () => {
    for (const hole of findHoles(white, index)) {
      expect(hasLine(white, [...hole.path, hole.san])).toBe(false);
    }
  });

  it('respects the popularity threshold', () => {
    const loose = findHoles(white, index, { minShare: 0.2 });
    const tight = findHoles(white, index, { minShare: 3 });
    expect(tight.length).toBeLessThanOrEqual(loose.length);
    for (const hole of tight) expect(hole.share).toBeGreaterThanOrEqual(3);
  });

  it('respects the depth limit', () => {
    for (const hole of findHoles(white, index, { maxPly: 4 })) {
      expect(hole.path.length).toBeLessThan(4);
    }
  });

  it('orders shallowest and most popular first', () => {
    const holes = findHoles(white, index);
    for (let i = 1; i < holes.length; i += 1) {
      const a = holes[i - 1];
      const b = holes[i];
      expect(a.path.length <= b.path.length).toBe(true);
      if (a.path.length === b.path.length) expect(a.share).toBeGreaterThanOrEqual(b.share);
    }
  });

  it('finds nothing in an empty White repertoire, whose first move answers nothing', () => {
    expect(findHoles(createRepertoire('Empty', 'w', 'e'), index)).toEqual([]);
  });
});

describe('how bare a repertoire is', () => {
  /** A King's Indian and nothing else: one reply met at every junction. */
  const kid = black;
  /** The same opening met several ways, plus something against every first move. */
  const broad = (() => {
    let rep = createRepertoire('Broad', 'b', 'r_broad');
    for (const line of [
      'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6',
      'd4 Nf6 c4 g6 Nf3 Bg7 g3 O-O',
      'd4 Nf6 c4 g6 g3 Bg7 Bg2 O-O',
      'd4 Nf6 c4 g6 f3 Bg7 e4 d6',
      'd4 Nf6 c4 g6 Bf4 Bg7',
      'd4 Nf6 c4 g6 h4 Bg7',
      'd4 Nf6 Nf3 g6 g3 Bg7',
      'd4 Nf6 Bg5 Ne4',
      'd4 Nf6 Bf4 g6',
      'd4 Nf6 Nc3 d5',
      'd4 Nf6 e3 g6',
      'd4 Nf6 g3 g6',
      'e4 e5 Nf3 Nc6',
      'c4 e5 Nc3 Nf6',
      'Nf3 Nf6 g3 g6',
      'g3 d5 Bg2 Nf6',
      'b3 e5 Bb2 Nc6',
      'f4 d5 Nf3 Nf6',
      'Nc3 d5 e4 d4',
      'b4 e5 Bb2 Bxb4',
      'd3 e5 Nf3 Nc6',
      'e3 d5 d4 Nf6',
      'c3 e5 d4 exd4',
      'h3 d5 d4 Nf6',
      'a3 e5 e4 Nf6',
    ]) {
      rep = addLine(rep, line.split(' '), 'reference').rep;
    }
    return rep;
  })();

  it('reads a repertoire with nothing in it as as bare as it gets', () => {
    expect(thinness(findCoverage(createRepertoire('Empty', 'b', 'r_e'), index))).toBe(1);
    expect(thinness([])).toBe(1);
  });

  it('reads one deep line as barer than many shallow ones', () => {
    const narrow = thinness(findCoverage(kid, index));
    const wide = thinness(findCoverage(broad, index));
    // Eight plies of prep, and an answer to one White reply at each junction.
    expect(narrow).toBeGreaterThan(0.35);
    expect(wide).toBeLessThan(narrow);
    expect(wide).toBeLessThan(0.3);
  });

  it('weighs an early choice above a late one', () => {
    const at = (depth: number, covered: number) => ({ path: Array(depth).fill('x'), covered, choice: 1 });
    expect(thinness([at(0, 0), at(10, 1)])).toBeGreaterThan(thinness([at(0, 1), at(10, 0)]));
  });

  it('discounts a position the opponent has no real choice in', () => {
    const forced = { path: ['x'], covered: 1, choice: 0 };
    const open = { path: ['x'], covered: 0, choice: 1 };
    // The recapture being answered barely counts against the open reply not.
    expect(thinness([forced, open])).toBeGreaterThan(0.9);
    expect(thinness([{ ...forced, choice: 1 }, open])).toBeCloseTo(0.5, 5);
  });

  it('ignores the tip of a line, which is depth missing rather than breadth', () => {
    // One move of prep: after 1.d4 Black answers, and then nothing. The only
    // junction is the root, so the tip cannot make the repertoire read wider.
    const oneMove = addLine(createRepertoire('One', 'b', 'r_one'), ['d4', 'Nf6'], 'reference').rep;
    const paths = findCoverage(oneMove, index).map((at) => at.path.join(' '));
    expect(paths).toEqual(['']);
  });
});

describe('the lobby', () => {
  it('puts the row most worth doing at the top', () => {
    const rows = growthRows([white], index);
    expect(rows.length).toBeGreaterThan(1);
    for (let i = 1; i < rows.length; i += 1) {
      expect(rows[i - 1].score).toBeGreaterThanOrEqual(rows[i].score);
    }
    expect(recommended(rows)).toBe(rows[0]);
    expect(recommended([])).toBeNull();
  });

  it('scores a shallow hole above a deep one played just as often', () => {
    // Depth is the urgency: a reply you cannot meet at move one costs a share
    // of every game, the same reply at move nine costs almost none.
    expect(rowUrgency(0, 20, 1)).toBeGreaterThan(rowUrgency(8, 20, 1));
    expect(rowUrgency(2, 40, 1)).toBeGreaterThan(rowUrgency(2, 5, 1));
    expect(rowUrgency(2, 20, 6)).toBeGreaterThan(rowUrgency(2, 20, 1));
    expect(rowUrgency(4, 0, 1)).toBe(0);
  });

  it('gives every hole exactly one row', () => {
    const rows = growthRows([white], index);
    const total = rows.reduce((sum, row) => sum + row.holes.length, 0);
    expect(total).toBe(findHoles(white, index).length);
  });

  it('names a row for where its holes lead, not where they sit', () => {
    // The bug this replaced: a Black King's Indian repertoire that cannot meet
    // 1.e4 had its first-move holes filed under "King's Indian", so picking
    // that row promised a King's Indian and delivered a Sicilian.
    const rows = growthRows([black], index);
    const first = rows.find((row) => row.depth === 0);
    expect(first).toBeDefined();
    expect(first!.name).not.toBe('Test');
    expect(first!.holes[0].san).toBe('e4');
    expect(first!.name).toMatch(/King's Pawn/);
  });

  it('files every variation under the family it belongs to', () => {
    // One row per variation is an accurate reading of the prep and an unusable
    // way to choose: a thin King's Indian produced Sämisch, Smyslov and Bf4
    // System as three separate rows, all of them a King's Indian.
    const names = growthRows([black], index).map((row) => row.name);
    expect(names).toContain("King's Indian Defence");
    for (const name of names) expect(name).not.toMatch(/^KID: /);
    expect(new Set(names).size).toBe(names.length);
  });

  it('keeps the family row pointing at every hole it absorbed', () => {
    const rows = growthRows([black], index);
    const kid = rows.find((row) => row.name === "King's Indian Defence")!;
    const total = growthRows([black], index).reduce((sum, row) => sum + row.holes.length, 0);
    expect(kid.holes.length).toBeGreaterThan(1);
    expect(total).toBe(findHoles(black, index).length);
  });

  it('lifts an opening the player starred without letting it jump the queue', () => {
    // Starring says which openings they mean to play. It is a reason to lift a
    // row, not a reason to call a deep variation more urgent than a first move
    // they cannot meet at all.
    const plain = growthRows([black], index);
    const kidLine = "d4 Nf6 c4 g6 Nc3 Bg7 e4";
    const lifted = growthRows([black], index, { starred: [kidLine] });
    const before = plain.find((row) => row.name === "King's Indian Defence")!;
    const after = lifted.find((row) => row.name === "King's Indian Defence")!;
    expect(before.starred).toBe(false);
    expect(after.starred).toBe(true);
    expect(after.score).toBeGreaterThan(before.score);
    expect(after.urgency).toBe(before.urgency);
    expect(after.score).toBeLessThanOrEqual(1);
  });

  it('stars only the rows inside the opening that was starred', () => {
    const rows = growthRows([black], index, { starred: ['d4 Nf6 c4 g6 Nc3 Bg7 e4'] });
    for (const row of rows) {
      if (row.name !== "King's Indian Defence") expect(row.starred).toBe(false);
    }
  });

  it('leads with the hole that costs the most games', () => {
    for (const rep of [white, black]) {
      const rows = growthRows([rep], index);
      for (let i = 1; i < rows.length; i += 1) {
        expect(rows[i - 1].score).toBeGreaterThanOrEqual(rows[i].score);
      }
    }
  });

  it('reports the biggest hole in a row, not merely the first', () => {
    // A row can span depths, and the holes are stored shallowest first, so the
    // most played one is not always at the front.
    for (const row of growthRows([black], index)) {
      expect(row.topShare).toBe(Math.max(...row.holes.map((hole) => hole.share)));
    }
  });

  it('calls a move the book cannot name after the move itself', () => {
    const names = growthRows([black], index).map((row) => row.name);
    // 1.g3 has no opening name here, and must not borrow the repertoire's.
    expect(names).toContain('vs 1.g3');
    expect(names).not.toContain('King\u2019s Indian Defence');
  });

  it('offers an empty Black repertoire a row per first move it cannot meet', () => {
    // One row per opening it would be answering, rather than one lump: the
    // point of the lobby is choosing what to prepare against.
    const rows = growthRows([createRepertoire('Empty', 'b', 'e')], index);
    expect(rows.length).toBeGreaterThan(1);
    for (const row of rows) expect(row.depth).toBe(0);
    expect(rows[0].holes[0].san).toBe('e4');
  });

  it('offers an empty White repertoire nothing, because there is nothing to answer', () => {
    // A hole is a reply you cannot meet, and White's first move answers
    // nothing. An empty White repertoire has to be seeded elsewhere — the
    // lobby says so rather than showing an empty list.
    expect(growthRows([createRepertoire('Empty', 'w', 'e')], index)).toEqual([]);
  });
});

describe('walking a run', () => {
  it('starts at the root with the player to move for White', () => {
    const row = growthRows([white], index)[0];
    const run = startGrowth(white, row);
    expect(run.path).toEqual([]);
    expect(isUsersTurn(run)).toBe(true);
    expect(run.hole).toBeNull();
  });

  it('accepts a prepared move and refuses anything else', () => {
    const row = growthRows([white], index)[0];
    const run = startGrowth(white, row);
    expect(advance(white, run, 'e4')).not.toBeNull();
    expect(advance(white, run, 'd4')).toBeNull();
    expect(advance(white, run, 'Nf3')).toBeNull();
  });

  it('steers to a hole and stops there', () => {
    const row = growthRows([white], index)[0];
    let run = startGrowth(white, row);
    for (let i = 0; i < 24 && !atHole(white, run); i += 1) {
      if (isUsersTurn(run)) {
        const mine = preparedHere(white, run);
        if (!mine.length) break;
        run = advance(white, run, mine[0].san)!;
      } else {
        const reply = steer(white, index, run);
        expect(reply).not.toBeNull();
        if (reply!.hole) {
          run = enterHole(run, reply!.hole);
          break;
        }
        run = advance(white, run, reply!.san)!;
      }
    }
    expect(atHole(white, run)).toBe(true);
    expect(isUsersTurn(run)).toBe(true);
  });

  it('lands on a hole the chosen row was actually aiming at', () => {
    const row = growthRows([white], index)[0];
    let run = startGrowth(white, row);
    run = advance(white, run, 'e4')!;
    const reply = steer(white, index, run);
    expect(reply!.hole).not.toBeNull();
    expect(run.targets.has(positionKey(run.fen))).toBe(true);
  });

  it('offers the book its replies at the hole, most played first', () => {
    const row = growthRows([white], index)[0];
    let run = startGrowth(white, row);
    run = advance(white, run, 'e4')!;
    const reply = steer(white, index, run)!;
    run = enterHole(run, reply.hole!);
    const options = optionsAt(index, run.fen);
    expect(options.length).toBeGreaterThan(0);
    for (let i = 1; i < options.length; i += 1) {
      expect(options[i - 1].games).toBeGreaterThanOrEqual(options[i].games);
    }
  });

  it('writes the opponent reply and your answer together', () => {
    const row = growthRows([white], index)[0];
    let run = startGrowth(white, row);
    run = advance(white, run, 'e4')!;
    const reply = steer(white, index, run)!;
    run = enterHole(run, reply.hole!);
    const line = lineFor(run, 'Nf3');
    // Their move has to be stored too, or the answer has no parent.
    expect(line).toEqual(['e4', reply.hole!.san, 'Nf3']);
  });
});

describe('answering a hole', () => {
  /** Walk a run to its first hole, the way the screen does. */
  function toHole() {
    const row = growthRows([white], index)[0];
    let run = startGrowth(white, row);
    for (let i = 0; i < 24 && !atHole(white, run); i += 1) {
      if (isUsersTurn(run)) {
        const mine = preparedHere(white, run);
        if (!mine.length) break;
        run = advance(white, run, mine[0].san)!;
      } else {
        const reply = steer(white, index, run)!;
        if (reply.hole) {
          run = enterHole(run, reply.hole);
          break;
        }
        run = advance(white, run, reply.san)!;
      }
    }
    return run;
  }

  it('plays your answer, leaving the hole behind', () => {
    const run = toHole();
    const san = optionsAt(index, run.fen)[0].san;
    const answered = answerHole(run, san)!;
    expect(answered.path).toEqual([...run.path, san]);
    expect(answered.hole).toBeNull();
    // Their turn again, which is what makes another hole possible.
    expect(isUsersTurn(answered)).toBe(false);
  });

  it('refuses a move that is not legal in the position', () => {
    expect(answerHole(toHole(), 'Qxh8')).toBeNull();
  });

  it('offers their commonest reply as the next hole to answer', () => {
    const run = toHole();
    const answered = answerHole(run, optionsAt(index, run.fen)[0].san)!;
    const hole = nextHole(index, answered);
    expect(hole).not.toBeNull();
    // The most played move there, and nothing rarer.
    const replies = optionsAt(index, answered.fen);
    expect(hole!.san).toBe(replies[0].san);
    expect(hole!.share).toBe(replies[0].share);

    // Stepping into it leaves you to move, with the whole line behind you.
    const next = enterHole(answered, hole!);
    expect(next.path).toEqual([...answered.path, hole!.san]);
    expect(isUsersTurn(next)).toBe(true);
    expect(optionsAt(index, next.fen).length).toBeGreaterThan(0);
  });

  it('runs the loop to the cap, writing every answer into the line', () => {
    let run = toHole();
    const added: string[] = [];
    while (added.length < MAX_ADDS) {
      const san = optionsAt(index, run.fen)[0].san;
      // What the screen writes into the repertoire at each step.
      expect(lineFor(run, san)).toEqual([...run.path, san]);
      run = answerHole(run, san)!;
      added.push(san);
      if (added.length === MAX_ADDS) break;
      const hole = nextHole(index, run);
      expect(hole).not.toBeNull();
      run = enterHole(run, hole!);
    }
    expect(added).toHaveLength(3);
    // Your three answers and the two replies between them.
    expect(run.path.slice(-5)).toEqual([added[0], expect.any(String), added[1], expect.any(String), added[2]]);
    expect(hasLine(white, run.path)).toBe(false);
  });

  it('has nothing to offer once the book runs out', () => {
    const run = toHole();
    // A position the database has never seen has no reply to give.
    const nowhere = { ...run, fen: '8/8/4k3/8/8/4K3/8/8 b - - 0 1' };
    expect(nextHole(index, nowhere)).toBeNull();
  });
});

describe('the moves drawn on the board', () => {
  it('draws three, one for each of three different pieces', () => {
    const drawn = movesToDraw(index, START_FEN);
    expect(drawn).toHaveLength(3);
    expect(new Set(drawn.map((m) => m.from)).size).toBe(3);
    for (const move of drawn) {
      const played = applySan(START_FEN, move.san)!;
      expect(played.from).toBe(move.from);
      expect(played.to).toBe(move.to);
    }
  });

  it('keeps only the best move of any one piece', () => {
    const replies = optionsAt(index, START_FEN, 24);
    const drawn = movesToDraw(index, START_FEN);
    for (const move of drawn) {
      // Nothing the book likes better leaves the same square.
      const better = replies
        .slice(0, replies.findIndex((r) => r.san === move.san))
        .map((r) => applySan(START_FEN, r.san)!.from);
      expect(better).not.toContain(move.from);
    }
  });

  it('reaches past the best moves to find a third piece', () => {
    // 1.e4 and 1.d4 are the two most played first moves by a distance, and the
    // third arrow is whatever the best move of some other piece is.
    const drawn = movesToDraw(index, START_FEN);
    expect(drawn[2]).toBeDefined();
    expect(drawn[2].from).not.toBe(drawn[0].from);
    expect(drawn[2].from).not.toBe(drawn[1].from);
  });

  it('draws fewer when the book has fewer to offer, and none off the book', () => {
    expect(movesToDraw(index, START_FEN, 1)).toHaveLength(1);
    expect(movesToDraw(index, '8/8/4k3/8/8/4K3/8/8 w - - 0 1')).toEqual([]);
  });
});

describe('what your games say about a hole', () => {
  const after = applySan(applySan(START_FEN, 'e4')!.after, 'c5')!.after;
  const hole = { path: ['e4'], fen: applySan(START_FEN, 'e4')!.after, san: 'c5', share: 20, games: 9, after, nodeId: null, answered: 0 };

  it('weighs a hole by the games you reached it with nothing prepared', () => {
    expect(evidenceFor([])(hole)).toBe(1);
    const weigh = evidenceFor([
      { kind: 'unprepared', fen: after, games: 3 },
      { kind: 'unprepared', fen: after, games: 1 },
      { kind: 'offprep', fen: after, games: 5 },
      { kind: 'unprepared', fen: START_FEN, games: 7 },
    ]);
    expect(weigh(hole)).toBe(5);
    expect(weigh({ ...hole, after: START_FEN })).toBe(8);
    expect(weigh({ ...hole, after: applySan(START_FEN, 'd4')!.after })).toBe(1);
  });
});
