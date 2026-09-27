import { useEffect, useState } from 'react';
import { applyUci, positionKey } from '../chess/core';
import { ENGINE_REPLIES, engineReplies, onEngineReplies, rememberEngineReplies } from '../model/engineReplies';
import { queueSearch } from './searchQueue';

/**
 * Ask the engine what it would play in positions past the book.
 *
 * The answers land in the model's cache (`src/model/engineReplies.ts`), where
 * Growth reads them synchronously, and every screen asking re-renders as each
 * one comes in. Positions are worked out one at a time, in the order asked,
 * behind any other background search.
 */

/**
 * How hard the engine thinks about each position: to this depth, or this long,
 * whichever comes first. Enough for its second and third moves to be real ones.
 */
const DEPTH = 16;
const THINK_MS = 1500;

/** Positions waiting for the engine, the ones a run is standing on first. */
const waiting: string[] = [];
const asked = new Set<string>();
let busy = false;

async function work(fen: string): Promise<void> {
  const snap = await queueSearch(fen, { depth: DEPTH, movetime: THINK_MS, multiPv: ENGINE_REPLIES }, THINK_MS * 6);
  const sans: string[] = [];
  for (const line of snap?.lines ?? []) {
    const move = line.pv[0] ? applyUci(fen, line.pv[0]) : null;
    if (move && !sans.includes(move.san)) sans.push(move.san);
  }
  // A search that never settled is asked again next time rather than
  // remembered as a position with no moves in it.
  if (!snap) {
    asked.delete(positionKey(fen));
    return;
  }
  rememberEngineReplies(fen, sans);
}

async function pump(): Promise<void> {
  if (busy) return;
  busy = true;
  while (waiting.length) {
    const fen = waiting.shift()!;
    if (engineReplies(fen) === undefined) await work(fen);
  }
  busy = false;
}

/**
 * Queue positions for the engine, once each. `urgent` is for a position a run
 * is standing on: it goes ahead of everything the lobby asked about in the
 * background.
 */
export function askEngine(fens: string[], urgent = false): void {
  for (const fen of fens) {
    const key = positionKey(fen);
    if (engineReplies(fen) !== undefined) continue;
    if (asked.has(key)) {
      if (urgent) {
        const at = waiting.findIndex((other) => positionKey(other) === key);
        if (at > 0) waiting.unshift(...waiting.splice(at, 1));
      }
      continue;
    }
    asked.add(key);
    if (urgent) waiting.unshift(fen);
    else waiting.push(fen);
  }
  void pump();
}

/**
 * Ask about these positions, and re-render as the answers come in. Returns
 * how many are still being worked out.
 */
export function useEngineReplies(fens: string[], urgent = false): number {
  const [, setTick] = useState(0);
  const wanted = fens.join('\n');
  useEffect(() => onEngineReplies(() => setTick((n) => n + 1)), []);
  useEffect(() => {
    if (fens.length) askEngine(fens, urgent);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [wanted]);
  return fens.filter((fen) => engineReplies(fen) === undefined).length;
}
