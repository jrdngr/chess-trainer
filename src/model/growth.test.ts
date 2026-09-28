import { describe, expect, it } from 'vitest';
import { applySan, fenTurn, positionKey, START_FEN } from '../chess/core';
import { deepestName, familyName, lookup } from './reference';
import {
  addsToFit,
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
  onePerPiece,
  nextHole,
  optionsAt,
  preparedHere,
  recommended,
  resumeAdding,
  rowUrgency,
  startGrowth,
  steer,
  thinness,
  type GrowthRun,
  firstHole,
  startGrowthAt,
  choicesAt,
  findLineEnds,
  firstEnd,
  needsEngine,
  startGrowthAtEnd,
  unaskedPastBook,
  type Hole,
} from './growth';
import { clearEngineReplies, rememberEngineReplies } from './engineReplies';
import { nodeById, openingTree } from './openingTree';
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

/**
 * The row covering the prep itself, as opposed to the first moves the
 * repertoire cannot meet at all. Found by depth rather than by name: which
 * family the book puts at the head of a King's Indian is the book's business,
 * and it moves when the book is rebuilt.
 */
const prepRow = (rows: ReturnType<typeof growthRows>) => rows.find((row) => row.depth > 0)!;

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

  it('counts how often a hole is actually reached, not merely how deep it is', () => {
    const holes = findHoles(black, index);
    // Every game starts at the root, so a first move is met as often as it is played.
    const root = holes.find((hole) => hole.path.length === 0 && hole.san === 'e4')!;
    expect(root.reach).toBe(1);
    // Eight plies in, only the games that took every step on the way get there.
    const tip = holes.find((hole) => hole.path.length === 8)!;
    expect(tip.reach).toBeGreaterThan(0);
    expect(tip.reach).toBeLessThan(0.2);
    // An unanswered 1.e4 is met far more often than the end of the one line.
    expect(root.reach * root.share).toBeGreaterThan(tip.reach * tip.share * 5);
  });

  it('keeps a hole reachable however unpopular the way in', () => {
    // Prep off 1.b3, a move almost nobody plays: the holes past it are worth
    // little, but a weight of zero would hide them from the draw for ever.
    const odd = addLine(createRepertoire('Odd', 'b', 'r_odd'), 'b3 e5 Bb2 Nc6'.split(' '), 'reference').rep;
    const holes = findHoles(odd, index);
    expect(holes.length).toBeGreaterThan(0);
    for (const hole of holes) expect(hole.reach).toBeGreaterThan(0);
    const deep = holes.find((hole) => hole.path.length === 4)!;
    expect(deep.reach).toBeLessThan(0.02);
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
  /**
   * Broad where the narrow one is deep: every reply the book gives at each of
   * the first few junctions, answered.
   *
   * Built from the book rather than listed by hand. A fixed list of lines is
   * only "broad" relative to the book it is measured against, and this book
   * offers about five replies in every position — a hand-written 25 lines
   * stopped being wide the moment the book got real.
   */
  const broad = (() => {
    let rep = createRepertoire('Broad', 'b', 'r_broad');
    const walk = (path: string[], fen: string) => {
      if (path.length >= 4) {
        rep = addLine(rep, path, 'reference').rep;
        return;
      }
      const entry = lookup(index, fen);
      if (!entry?.moves.length) {
        if (path.length) rep = addLine(rep, path, 'reference').rep;
        return;
      }
      // Their choices are all met; ours is the one move the book likes best.
      const ours = fenTurn(fen) === 'b';
      for (const move of ours ? entry.moves.slice(0, 1) : entry.moves.slice(0, 4)) {
        const played = applySan(fen, move.san);
        if (played) walk([...path, played.san], played.after);
      }
    };
    walk([], START_FEN);
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
    const rows = growthRows([black], index);
    const names = rows.map((row) => row.name);
    // Everything below the prep is one row, headed by the family the book names
    // at the top of it rather than by each variation underneath.
    expect(rows.filter((row) => row.depth > 0)).toHaveLength(1);
    for (const name of names) expect(name).not.toMatch(/: /);
    expect(new Set(names).size).toBe(names.length);
  });

  it('keeps the family row pointing at every hole it absorbed, past the book too', () => {
    // A hole past the book is answered by the engine, so none is dropped.
    const rows = growthRows([black], index);
    const family = prepRow(rows);
    const total = rows.reduce((sum, row) => sum + row.holes.length, 0);
    expect(family.holes.length).toBeGreaterThan(1);
    expect(total).toBe(findHoles(black, index).length);
  });

  it('starts a run standing on the hole the row most wants answered', () => {
    const row = prepRow(growthRows([black], index));
    const first = firstHole(index, row)!;
    expect(optionsAt(index, first.after, 1).length).toBeGreaterThan(0);
    const worth = (hole: typeof first) => hole.reach * hole.share;
    expect(row.holes.every((hole) => worth(hole) <= worth(first))).toBe(true);
    const run = startGrowthAt(black, row, first);
    expect(atHole(black, run)).toBe(true);
    expect(run.path).toEqual([...first.path, first.san]);
  });

  it('lifts an opening the player starred without letting it jump the queue', () => {
    // Starring says which openings they mean to play. It is a reason to lift a
    // row, not a reason to call a deep variation more urgent than a first move
    // they cannot meet at all.
    const plain = growthRows([black], index);
    const kidLine = 'd4 Nf6 c4 g6 Nc3 Bg7 e4';
    const lifted = growthRows([black], index, { starred: [kidLine] });
    const before = prepRow(plain);
    const after = prepRow(lifted);
    expect(before.starred).toBe(false);
    expect(after.starred).toBe(true);
    expect(after.score).toBeGreaterThan(before.score);
    expect(after.urgency).toBe(before.urgency);
    expect(after.score).toBeLessThanOrEqual(1);
  });

  it('stars only the rows inside the opening that was starred', () => {
    const rows = growthRows([black], index, { starred: ['d4 Nf6 c4 g6 Nc3 Bg7 e4'] });
    const starred = prepRow(rows);
    for (const row of rows) {
      if (row !== starred) expect(row.starred).toBe(false);
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

  it('offers only the selected opening, not every route that could reach it', () => {
    // The bug: select the King's Indian with a King's Indian repertoire and the
    // lobby led with the King's Pawn Game. 1.e4 d6 2.d4 Nf6 3.c4 g6 is a King's
    // Indian, so an unanswered 1.e4 passes the positional region test — and an
    // unanswered first move outscores everything, so it took the top row.
    const tree = openingTree(index);
    const kingsIndian = nodeById(tree, 'd4 Nf6 c4 g6 Nc3');
    const rows = growthRows([black], index, { region: { tree, node: kingsIndian } });
    expect(rows.length).toBeGreaterThan(0);
    for (const row of rows) expect(row.depth).toBeGreaterThan(0);
    expect(rows.map((row) => row.name)).not.toContain("King's Pawn Game");
    expect(recommended(rows)).toBe(prepRow(rows));
  });

  it('keeps an opening the selection is only on the way into', () => {
    // The White rep is a Sicilian and the selection a variation of it, so the
    // row sits above the Najdorf rather than inside it. It is still the work
    // the selection asks for, and dropping it would leave the lobby empty.
    const tree = openingTree(index);
    const najdorf = nodeById(tree, 'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6');
    const rows = growthRows([white], index, { region: { tree, node: najdorf } });
    // The way in keeps its own name; 5...a6 itself is the Najdorf, and is
    // called that rather than by the family above it.
    expect(rows.map((row) => row.name).sort()).toEqual(['Sicilian Defence', najdorf.name].sort());
    const inside = rows.find((row) => row.name === najdorf.name)!;
    expect(inside.holes.map((hole) => hole.san)).toEqual(['a6']);
  });

  it('scopes nothing when the selection is every opening there is', () => {
    // The guard against over-filtering: the root covers everything, so the
    // first moves a repertoire cannot meet are still the lobby's top rows.
    const tree = openingTree(index);
    const rows = growthRows([black], index, { region: { tree, node: tree.root } });
    expect(rows).toEqual(growthRows([black], index));
    expect(recommended(rows)!.depth).toBe(0);
  });

  it('reports the biggest hole in a row, not merely the first', () => {
    // A row can span depths, and the holes are stored shallowest first, so the
    // most played one is not always at the front.
    for (const row of growthRows([black], index)) {
      expect(row.topShare).toBe(Math.max(...row.holes.map((hole) => hole.share)));
    }
  });

  it('never lets a row borrow a name from the repertoire it sits in', () => {
    // A row is named after the position it covers or after the move itself —
    // never after the prep it happens to belong to. The book names every first
    // move it holds, so the "vs 1.g3" fallback is rare rather than unreachable,
    // and the invariant is what matters: a name is earned by a position.
    for (const row of growthRows([black], index)) {
      // The row is named for the move the hole asks about, not the position the
      // hole is asked from.
      const hole = row.holes[0];
      const deepest = deepestName(index, [...hole.path, hole.san]);
      if (deepest) expect(row.name).toBe(familyName(index, deepest.name));
      else expect(row.name).toMatch(/^vs \d+\./);
    }
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

  it('runs the loop to the batch it was given, writing every answer into the line', () => {
    let run = toHole();
    const allowance = addsToFit(run.path.length);
    expect(allowance).toBeGreaterThan(1);
    const added: string[] = [];
    while (added.length < allowance) {
      const san = optionsAt(index, run.fen)[0].san;
      // What the screen writes into the repertoire at each step.
      expect(lineFor(run, san)).toEqual([...run.path, san]);
      run = answerHole(run, san)!;
      added.push(san);
      if (added.length === allowance) break;
      const hole = nextHole(index, run);
      expect(hole).not.toBeNull();
      run = enterHole(run, hole!);
    }
    // Your answers, and their replies in between.
    expect(run.path.slice(-(allowance * 2 - 1)).filter((_, i) => i % 2 === 0)).toEqual(added);
    expect(hasLine(white, run.path)).toBe(false);
  });

  it('carries on from the hole it stopped at, or from their next reply', () => {
    const at = toHole();
    // Stopped by hand at a hole: another batch answers that same hole.
    expect(resumeAdding(white, index, at)).toBe(at);

    // Stopped having answered: their commonest reply becomes the next hole.
    const answered = answerHole(at, optionsAt(index, at.fen)[0].san)!;
    const on = resumeAdding(white, index, answered)!;
    expect(on).not.toBeNull();
    expect(on.path).toEqual([...answered.path, (nextHole(index, answered) as Hole).san]);
    expect(isUsersTurn(on)).toBe(true);
    expect(optionsAt(index, on.fen).length).toBeGreaterThan(0);
  });

  it('asks the engine for their reply at the edge of the book', () => {
    // The King's Indian Sämisch: the book records no reply at all after
    // 7.Nge2. That used to end the batch; now the engine plays for them.
    const line = 'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 f3 O-O Be3 c5'.split(' ');
    let fen = START_FEN;
    for (const san of line) fen = applySan(fen, san)!.after;
    expect(optionsAt(index, fen)[0].san).toBe('Nge2');
    const edgeFen = applySan(fen, 'Nge2')!.after;
    expect(optionsAt(index, edgeFen)).toHaveLength(0);

    const edge: GrowthRun = {
      repertoireId: white.id,
      color: 'b',
      rowId: 'row',
      targets: new Set(),
      path: [...line, 'Nge2'],
      fen: edgeFen,
      nodeId: null,
      hole: null,
    };
    clearEngineReplies();
    // Not asked yet: nothing to say, and a batch can still carry on once it is.
    expect(nextHole(index, edge)).toBeUndefined();
    expect(resumeAdding(white, index, edge)).toBe(edge);
    expect(needsEngine(index, edgeFen)).toBe(true);

    rememberEngineReplies(edgeFen, ['cxd4', 'Nc6', 'Qa5']);
    const hole = nextHole(index, edge) as Hole;
    expect(hole.san).toBe('cxd4');
    expect(hole.engine).toBe(true);
    expect(hole.share).toBe(0);
    clearEngineReplies();
  });

  it('has nothing to offer in a position with no moves at all', () => {
    const run = toHole();
    const nowhere = { ...run, fen: '8/8/4k3/8/8/4K3/8/8 b - - 0 1' };
    clearEngineReplies();
    rememberEngineReplies(nowhere.fen, []);
    expect(nextHole(index, nowhere)).toBeNull();
    expect(resumeAdding(white, index, nowhere)).toBeNull();
    clearEngineReplies();
  });
});

describe('growing past the book', () => {
  /** The Albin line from a real repertoire, ending past the book on Black's move. */
  const albin = thin('w', 'd4 d5 c4 e5 dxe5 d4 Nf3 Nc6 g3 Nge7 Bg2');

  it('lists a line past the book as an end until the engine is asked', () => {
    clearEngineReplies();
    const ends = findLineEnds(albin, index);
    expect(ends.map((end) => end.path.join(' '))).toEqual(['d4 d5 c4 e5 dxe5 d4 Nf3 Nc6 g3 Nge7 Bg2']);
    const row = growthRows([albin], index).find((r) => r.ends.length > 0)!;
    expect(row).toBeDefined();
    expect(firstEnd(row)!.path).toHaveLength(11);
    expect(unaskedPastBook(albin, index)).toContain(ends[0].fen);
  });

  it("turns the engine's moves into replies to answer once it has them", () => {
    clearEngineReplies();
    const [end] = findLineEnds(albin, index);
    rememberEngineReplies(end.fen, ['Ng6', 'Nf5', 'Be6']);
    expect(findLineEnds(albin, index)).toHaveLength(0);
    const holes = findHoles(albin, index).filter((hole) => hole.path.length === 11);
    expect(holes.map((hole) => hole.san)).toEqual(['Ng6', 'Nf5', 'Be6']);
    expect(holes.every((hole) => hole.engine && hole.share === 0)).toBe(true);
    // Every one of them survives the threshold, which only the book can be held to.
    expect(findHoles(albin, index, { minShare: 5 }).filter((hole) => hole.path.length === 11)).toHaveLength(3);
    expect(choicesAt(index, end.fen)!.map((choice) => choice.san)).toEqual(['Ng6', 'Nf5', 'Be6']);
    clearEngineReplies();
  });

  it('starts a run on a line end with the opponent to move', () => {
    clearEngineReplies();
    const row = growthRows([albin], index).find((r) => r.ends.length > 0)!;
    const end = firstEnd(row)!;
    const run = startGrowthAtEnd(albin, row, end);
    expect(run.path).toEqual(end.path);
    expect(isUsersTurn(run)).toBe(false);
    expect(nextHole(index, run)).toBeUndefined();
  });
});

describe('replies you kept with no answer', () => {
  /** A Queen's Gambit where the answer to 3...c5 was deleted, leaving the reply behind. */
  const qg = (() => {
    let rep = thin('w', 'd4 d5 c4 e6 Nc3');
    rep = addLine(rep, 'd4 d5 c4 c5'.split(' '), 'reference').rep;
    return rep;
  })();

  it('counts the kept reply as a hole, whatever its share', () => {
    const holes = findHoles(qg, index, { minShare: 50 });
    const c5 = holes.find((hole) => hole.path.join(' ') === 'd4 d5 c4' && hole.san === 'c5');
    expect(c5).toBeDefined();
    expect(c5!.kept).toBe(true);
  });

  it('does not count it once it is answered, here or by another move order', () => {
    const answered = addLine(qg, 'd4 d5 c4 c5 cxd5'.split(' '), 'reference').rep;
    expect(findHoles(answered, index, { minShare: 0 }).some((hole) => hole.san === 'c5' && hole.path.length === 3)).toBe(false);
  });

  it('names Queen\'s Gambit work after the Queen\'s Gambit when that is the selection', () => {
    const tree = openingTree(index);
    const node = nodeById(tree, 'd4 d5 c4');
    const rows = growthRows([qg], index, { region: { tree, node } });
    const row = rows.find((r) => r.holes.some((hole) => hole.kept))!;
    expect(row.name).toBe(node.name);
  });
});

describe('the batch a run is given', () => {
  it('grows a shallow hole into a line and a deep one by a move', () => {
    expect(addsToFit(2)).toBe(8);
    expect(addsToFit(6)).toBe(6);
    expect(addsToFit(8)).toBe(5);
    expect(addsToFit(12)).toBe(3);
    expect(addsToFit(14)).toBe(2);
    // Past the horizon a hole is still worth one answer, and never more.
    expect(addsToFit(18)).toBe(1);
    expect(addsToFit(40)).toBe(1);
    // A tighter horizon is a smaller batch at the same depth.
    expect(addsToFit(2, 8)).toBe(3);
    expect(addsToFit(6, 8)).toBe(1);
    // However shallow, never more than a run may add at the edge of its prep.
    expect(addsToFit(0)).toBe(MAX_ADDS);
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

  it('gives each piece the first of its moves in the order handed over', () => {
    // Best first: Nf3 beats Nh3 for the g1 knight, so h3 is never drawn.
    const drawn = onePerPiece(START_FEN, ['Nf3', 'e4', 'Nh3', 'd4'], 3);
    expect(drawn.map((move) => move.san)).toEqual(['Nf3', 'e4', 'd4']);
    expect(onePerPiece(START_FEN, ['Nh3', 'Nf3']).map((move) => move.san)).toEqual(['Nh3']);
  });
});

describe('what your games say about a hole', () => {
  const after = applySan(applySan(START_FEN, 'e4')!.after, 'c5')!.after;
  const hole = { path: ['e4'], fen: applySan(START_FEN, 'e4')!.after, san: 'c5', share: 20, games: 9, after, nodeId: null, reach: 1 };

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

describe('which way a run is steered', () => {
  /** A repertoire with prep down two of Black's first moves. */
  function branching(lines: string[]): Repertoire {
    let rep = createRepertoire('Test', 'w', 'r_steer');
    for (const line of lines) rep = addLine(rep, line.split(' '), 'reference').rep;
    return rep;
  }

  /** The run as it stands after 1.e4, aiming at the tips of both branches. */
  function afterE4(rep: Repertoire, aims: string[]): GrowthRun {
    const e4 = Object.values(rep.nodes).find((node) => node.parentId === null)!;
    return {
      repertoireId: rep.id,
      color: 'w',
      rowId: 'row',
      targets: new Set(aims.map((line) => positionKey(fenAfter(line)))),
      path: ['e4'],
      fen: e4.fenAfter,
      nodeId: e4.id,
      hole: null,
    };
  }

  function fenAfter(line: string): string {
    let fen = START_FEN;
    for (const san of line.split(' ')) fen = applySan(fen, san)!.after;
    return fen;
  }

  const SICILIAN = 'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3';
  const ALEKHINE = 'e4 Nf6 e5';

  it('walks to the main line rather than the nearest sideline', () => {
    // 1...Nf6 is played in one game in fifty and its hole is two plies away;
    // the Najdorf tabiya is eight plies away and is where the games go. The
    // old rule took whichever hole was nearest, which is how a run inside a
    // starred Sicilian ended up in an Alekhine.
    const rep = branching([SICILIAN, ALEKHINE]);
    const run = afterE4(rep, [SICILIAN, ALEKHINE]);
    expect(steer(rep, index, run)!.san).toBe('c5');
  });

  it('takes the nearer of two holes the player would meet as often', () => {
    // 1...d6 and 1...g6 are played as often as each other and both branches
    // end in a reply the book plays every time, so the two holes are worth
    // exactly the same. All that is left to choose on is the walk: one is a
    // move away, the other three.
    const near = 'e4 d6 d4';
    const far = 'e4 g6 d4 Bg7 Nc3';
    const rep = branching([near, far]);
    expect(steer(rep, index, afterE4(rep, [near, far]))!.san).toBe('d6');
  });

  it('answers the reply they play most, where several here have no answer', () => {
    const rep = branching([SICILIAN]);
    const run = afterE4(rep, [SICILIAN]);
    // Aim at the position the run is standing in: 1...c5 is prepared, so the
    // hole taken is the most played of the rest.
    const here = { ...run, targets: new Set([positionKey(run.fen)]) };
    const reply = steer(rep, index, here)!;
    expect(reply.hole).not.toBeNull();
    expect(reply.san).toBe('e5');
  });

  it('still reaches a hole when only an unplayed branch has one', () => {
    const rep = branching([SICILIAN, ALEKHINE]);
    const run = afterE4(rep, [ALEKHINE]);
    expect(steer(rep, index, run)!.san).toBe('Nf6');
  });
});
