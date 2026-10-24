import { useEffect, useState } from 'react';
import { applySan, fenTurn, walkSan } from '../chess/core';
import { whiteCp } from '../model/evalDelta';
import { evalLoss } from '../model/openingRun';
import { queueSearch } from './searchQueue';

/**
 * What the engine says of the moves in a line, for the Save sheet: how much
 * each one gives away against the engine's best, and what the position is
 * worth after it.
 *
 * Two searches a move: the position as it stands, which also names the best
 * move, then the position held to the move itself. The engine's own move
 * needs only the first. Answers are kept for the page's lifetime and asked
 * one at a time, since there is one engine.
 */

export interface MoveCheck {
  /** Centipawns given away, from the mover's side. Never negative. */
  lost: number;
  /** The position's worth after the move, centipawns from White's side. */
  after: number;
}

const THINK_MS = 700;

const answers = new Map<string, MoveCheck | null>();
const listeners = new Set<() => void>();
const queue: { fen: string; san: string }[] = [];
let busy = false;

const keyOf = (fen: string, san: string) => `${fen}|${san}`;

async function check(fen: string, san: string): Promise<MoveCheck | null> {
  const move = applySan(fen, san);
  if (!move) return null;
  const limits = { movetime: THINK_MS, depth: 14 };
  const full = await queueSearch(fen, { ...limits, multiPv: 1 }, THINK_MS * 8);
  const best = full?.lines[0];
  const before = whiteCp(best);
  if (!best || before === null) return null;
  if (best.pv[0] === move.uci) return { lost: 0, after: before };
  const held = await queueSearch(fen, { ...limits, multiPv: 1, searchmoves: [move.uci] }, THINK_MS * 8);
  const after = whiteCp(held?.lines[0]);
  if (after === null) return null;
  return { lost: Math.max(0, evalLoss(fenTurn(fen), before, after)), after };
}

async function pump() {
  if (busy) return;
  busy = true;
  while (queue.length) {
    const { fen, san } = queue.shift()!;
    const key = keyOf(fen, san);
    if (answers.has(key)) continue;
    answers.set(key, await check(fen, san));
    for (const listen of listeners) listen();
  }
  busy = false;
}

/**
 * Checks for the moves of `sans` (a line from the start) at the plies asked
 * for, filled in as the engine answers. A move the engine could not judge
 * reads null; one not answered yet is missing.
 */
export function useLineChecks(sans: string[], plies: number[], enabled = true): Map<number, MoveCheck | null> {
  const [, setTick] = useState(0);
  const { fens } = walkSan(sans);
  const questions = plies.filter((ply) => ply < fens.length - 1).map((ply) => ({ ply, fen: fens[ply], san: sans[ply] }));
  const wanted = questions.map((q) => keyOf(q.fen, q.san)).join('\n');

  useEffect(() => {
    const listen = () => setTick((n) => n + 1);
    listeners.add(listen);
    return () => {
      listeners.delete(listen);
    };
  }, []);

  useEffect(() => {
    if (!enabled) return;
    let added = false;
    for (const q of questions) {
      const key = keyOf(q.fen, q.san);
      if (answers.has(key) || queue.some((w) => keyOf(w.fen, w.san) === key)) continue;
      queue.push({ fen: q.fen, san: q.san });
      added = true;
    }
    if (added) void pump();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [wanted, enabled]);

  const out = new Map<number, MoveCheck | null>();
  for (const q of questions) {
    const key = keyOf(q.fen, q.san);
    if (answers.has(key)) out.set(q.ply, answers.get(key)!);
  }
  return out;
}
