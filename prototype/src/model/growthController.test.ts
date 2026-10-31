import { describe, expect, it } from 'vitest';
import { firstHole, growthRows, nextHole, optionsAt, type Hole } from './growth';
import {
  allowanceOf,
  anotherBatch,
  beginGrowth,
  choose,
  growthRound,
  inBatch,
  measureBatch,
  nothingPrepared,
  opponentToMove,
  reachedEdge,
  stop,
  theyReply,
  undo,
  walk,
  type GrowthSession,
} from './growthController';
import { nodeById, openingTree } from './openingTree';
import { referenceIndex } from './referenceIndex';
import { addLine, createRepertoire, nodeAtLine } from './repertoire';
import type { Repertoire } from './types';

const index = referenceIndex();

function thin(color: 'w' | 'b', line: string): Repertoire {
  return addLine(createRepertoire('Test', color, `r_${color}`), line.split(' '), 'book').rep;
}

const black = thin('b', 'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6');
const row = growthRows([black], index).find((r) => r.depth > 0)!;
const MAX_PLY = 9;

/** A session standing at the row's best hole, with its batch measured. */
function atHole(): GrowthSession {
  return measureBatch(beginGrowth(black, index, row), MAX_PLY);
}

/** The first answer the book offers where the session stands. */
const offered = (session: GrowthSession) => optionsAt(index, session.run.fen, 1).map((option) => option.san);

describe('a Growth run as state and events', () => {
  it('starts standing on the hole the row most wants answered', () => {
    const session = beginGrowth(black, index, row);
    expect(session.phase).toBe('hole');
    expect(session.run.hole).toEqual(firstHole(index, row));
    expect(opponentToMove(session, black)).toBe(false);
  });

  it('a run from move one walks your prep, and a move off it loses', () => {
    const fromStart = { ...beginGrowth(black, index, row, null), phase: 'walking' as const };
    const walking: GrowthSession = { ...fromStart, run: { ...fromStart.run, path: ['d4'], fen: 'rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq - 0 1', nodeId: nodeAtLine(black, ['d4'])!.id, hole: null } };
    const good = walk(walking, black, 'Nf6');
    expect(good.session.run.path).toEqual(['d4', 'Nf6']);
    expect(good.effects).toEqual([{ kind: 'buzz', pattern: 10 }]);
    const bad = walk(walking, black, 'e6');
    expect(bad.session.phase).toBe('lost');
    expect(bad.session.wrong).toBe('e6');
  });

  it('nothing prepared on your move is a hole', () => {
    const walking: GrowthSession = { ...atHole(), phase: 'walking' };
    expect(nothingPrepared(walking, 0).phase).toBe('hole');
    expect(nothingPrepared(walking, 1)).toBe(walking);
  });

  it('measures the batch from the depth of its first hole, once', () => {
    const session = atHole();
    expect(session.batch).toEqual({ base: 0, allowance: allowanceOf(session, MAX_PLY) });
    expect(measureBatch(session, MAX_PLY)).toBe(session);
  });

  it('choosing an answer saves the line, logs it, and waits on their reply', () => {
    const session = atHole();
    const san = offered(session)[0];
    const step = choose(session, san, 3, [san]);
    expect(step.effects.map((effect) => effect.kind)).toEqual(['addLine', 'log', 'buzz', 'toast']);
    expect(step.effects[0]).toEqual({ kind: 'addLine', line: [...session.run.path, san] });
    expect(step.session.phase).toBe('answered');
    expect(step.session.added).toEqual([session.run.path.length]);
    expect(step.session.answer?.san).toBe(san);
    expect(inBatch(step.session)).toBe(1);
  });

  it('the last answer the batch allows brings the run to rest', () => {
    const session = atHole();
    const step = choose(session, offered(session)[0], 1, []);
    expect(step.session.phase).toBe('done');
  });

  it('their reply stands the run at the next hole, or ends the batch when there is none', () => {
    const answered = choose(atHole(), offered(atHole())[0], 3, []).session;
    const hole = nextHole(index, answered.run) as Hole;
    const next = theyReply(answered, hole);
    expect(next.phase).toBe('hole');
    expect(next.answer).toBeNull();
    expect(next.run.path.at(-1)).toBe(hole.san);
    expect(theyReply(answered, null).phase).toBe('done');
  });

  it('Undo takes the answer back out and stands at the reply again', () => {
    const session = atHole();
    const san = offered(session)[0];
    const answered = choose(session, san, 3, []).session;
    const saved = addLine(black, [...session.run.path, san], 'growth').rep;
    const step = undo(answered, saved);
    expect(step.session.phase).toBe('hole');
    expect(step.session.run).toBe(session.run);
    expect(step.session.added).toEqual([]);
    expect(step.session.batch).toEqual(session.batch);
    // Standing in a hole, the reply had no node either, so it goes with the answer.
    expect(step.effects[0]).toEqual({ kind: 'removeLine', nodeId: nodeAtLine(saved, session.run.path)!.id });
    expect(step.effects.at(-1)).toEqual({ kind: 'toast', text: `${san} undone` });
    expect(undo(session, saved)).toEqual({ session, effects: [] });
  });

  it('another batch starts afresh from where the reveal says', () => {
    const done = stop(atHole());
    const step = anotherBatch(done, black, atHole().run);
    expect(step.session.batch).toBeNull();
    expect(step.session.phase).toBe('hole');
  });

  it('stops at the edge of the book, and says so', () => {
    const step = reachedEdge(atHole());
    expect(step.session.phase).toBe('done');
    expect(step.session.edge).toBe(true);
    expect(step.effects).toEqual([{ kind: 'edgeFlash' }]);
    expect(reachedEdge(step.session).effects).toEqual([]);
  });

  it('a sitting is one round, drawn up once the run is at rest', () => {
    const catalogue = openingTree(index);
    const within = nodeById(catalogue, catalogue.root.id);
    expect(growthRound(atHole(), catalogue, within, 3)).toBeNull();
    const full = choose(atHole(), offered(atHole())[0], 1, []).session;
    expect(growthRound(full, catalogue, within, 1)).toMatchObject({ mode: 'growth', color: 'b', perfect: true });
  });
});
