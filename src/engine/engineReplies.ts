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

/** How long the engine thinks about each position: enough for a sensible top three. */
const THINK_MS = 700;

const asked = new Set<string>();

async function work(fen: string): Promise<void> {
  const snap = await queueSearch(fen, { movetime: THINK_MS, multiPv: ENGINE_REPLIES }, THINK_MS * 8);
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

/** Queue positions for the engine, once each. */
export function askEngine(fens: string[]): void {
  for (const fen of fens) {
    const key = positionKey(fen);
    if (asked.has(key) || engineReplies(fen) !== undefined) continue;
    asked.add(key);
    void work(fen);
  }
}

/**
 * Ask about these positions, and re-render as the answers come in. Returns
 * how many are still being worked out.
 */
export function useEngineReplies(fens: string[]): number {
  const [, setTick] = useState(0);
  const wanted = fens.join('\n');
  useEffect(() => onEngineReplies(() => setTick((n) => n + 1)), []);
  useEffect(() => {
    if (fens.length) askEngine(fens);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [wanted]);
  return fens.filter((fen) => engineReplies(fen) === undefined).length;
}
