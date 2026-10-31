import { useEffect, useState } from 'react';
import { applySan, positionKey } from '../chess/core';
import { whiteCp } from '../model/evalDelta';
import { queueSearch } from './searchQueue';
import type { EngineLine } from './types';

/**
 * The eval bar's number for a position, and what each of a few moves there
 * would make it — for Growth, which shows both.
 *
 * Two searches: the position as it stands, which is the bar, and one held to
 * the moves on offer, which scores each of them from the same side of the
 * board. Only the position being looked at is worked out: a newer one asked
 * for replaces an older one still waiting, so walking through a line does not
 * leave a queue of positions nobody is looking at any more.
 */

export interface MoveEvals {
  /** The position's eval, centipawns from White's side. */
  position: number;
  /** Each move's eval, centipawns from White's side, where the engine gave one. */
  moves: Map<string, number>;
}

const DEPTH = 16;
const THINK_MS = 1200;

const known = new Map<string, MoveEvals>();
const listeners = new Set<() => void>();
let waiting: { fen: string; sans: string[] } | null = null;
let busy = false;

const keyOf = (fen: string, sans: string[]) => `${positionKey(fen)}|${[...sans].sort().join(' ')}`;

/** The position's eval alone, once any search of it has settled. */
const positions = new Map<string, number>();

async function work(fen: string, sans: string[]): Promise<void> {
  const key = keyOf(fen, sans);
  let position = positions.get(positionKey(fen));
  if (position === undefined) {
    const snap = await queueSearch(fen, { depth: DEPTH, movetime: THINK_MS, multiPv: 1 }, THINK_MS * 6);
    const cp = whiteCp(snap?.lines[0]);
    if (cp === null) return;
    position = cp;
    positions.set(positionKey(fen), cp);
    for (const listen of listeners) listen();
  }
  const ucis = sans.map((san) => applySan(fen, san)?.uci).filter((uci): uci is string => !!uci);
  const moves = new Map<string, number>();
  if (ucis.length) {
    const snap = await queueSearch(
      fen,
      { depth: DEPTH, movetime: THINK_MS, multiPv: ucis.length, searchmoves: ucis },
      THINK_MS * 6,
    );
    for (const line of snap?.lines ?? ([] as EngineLine[])) {
      const san = sans[ucis.indexOf(line.pv[0])];
      const cp = whiteCp(line);
      if (san && cp !== null) moves.set(san, cp);
    }
  }
  // Two searches never agree exactly. A move scoring better than the position
  // itself means the position's search came up short, not that the move
  // gains anything: the position is worth at least its best move.
  const white = fen.split(' ')[1] !== 'b';
  for (const cp of moves.values()) position = white ? Math.max(position, cp) : Math.min(position, cp);
  positions.set(positionKey(fen), position);
  known.set(key, { position, moves });
  for (const listen of listeners) listen();
}

async function pump(): Promise<void> {
  if (busy) return;
  busy = true;
  while (waiting) {
    const next: { fen: string; sans: string[] } = waiting;
    waiting = null;
    if (!known.has(keyOf(next.fen, next.sans))) await work(next.fen, next.sans);
  }
  busy = false;
}

/**
 * The eval of a position and of the moves offered there, as far as it has
 * been worked out: the bar alone first, then the moves.
 */
export function useMoveEvals(fen: string | null, sans: string[], enabled = true): { position: number | null; moves: Map<string, number> } {
  const [, setTick] = useState(0);
  const wanted = fen ? keyOf(fen, sans) : '';
  useEffect(() => {
    const listen = () => setTick((n) => n + 1);
    listeners.add(listen);
    return () => {
      listeners.delete(listen);
    };
  }, []);
  useEffect(() => {
    if (!enabled || !fen || known.has(wanted)) return;
    waiting = { fen, sans };
    void pump();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [wanted, enabled]);
  if (!fen) return { position: null, moves: new Map() };
  const full = known.get(wanted);
  return {
    position: full?.position ?? positions.get(positionKey(fen)) ?? null,
    moves: full?.moves ?? new Map(),
  };
}
