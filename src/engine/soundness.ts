import { useEffect, useState } from 'react';
import { applySan, fenTurn } from '../chess/core';
import { judgeByEval } from '../model/openingRun';
import type { EngineLine, EngineSnapshot } from './types';
import { getEngine } from './useEngine';

/**
 * Is a move the book does not have sound?
 *
 * A familiar move off the book is only offered — as a yellow arrow in Growth,
 * or a find in Tidy — once the engine has passed it, by the same test a move
 * off your prep gets in a round: what the position is worth, against what it
 * is worth with the move forced, within the blunder limit. Answers are kept
 * for the page's lifetime, and questions wait their turn, since there is one
 * engine.
 */

/** How long the engine thinks about each half of the question. */
const THINK_MS = 400;

const answers = new Map<string, boolean>();
const listeners = new Set<() => void>();
const queue: { fen: string; san: string }[] = [];
let busy = false;

const keyOf = (fen: string, san: string) => `${fen}|${san}`;

function scoreOf(line: EngineLine | undefined): number | null {
  if (!line) return null;
  if (line.cp !== null) return line.cp;
  if (line.mate !== null) return line.mate > 0 ? 10_000 : -10_000;
  return null;
}

/** One search, resolved with its score once the engine settles. */
function search(fen: string, uci?: string): Promise<number | null> {
  return new Promise((resolve) => {
    const { engine, backend } = getEngine();
    void backend.then(() => {
      let done = false;
      getEngine().engine.analyse(
        fen,
        { movetime: THINK_MS, multiPv: 1, ...(uci ? { searchmoves: [uci] } : {}) },
        (snap: EngineSnapshot) => {
          if (done || snap.thinking || snap.fen !== fen) return;
          done = true;
          resolve(scoreOf(snap.lines[0]));
        },
      );
      // A search that never settles (no engine at all) is not a pass.
      setTimeout(() => {
        if (done) return;
        done = true;
        engine.stop();
        resolve(null);
      }, THINK_MS * 8);
    });
  });
}

async function pump() {
  if (busy) return;
  busy = true;
  while (queue.length) {
    const { fen, san } = queue.shift()!;
    const key = keyOf(fen, san);
    if (answers.has(key)) continue;
    const move = applySan(fen, san);
    let ok = false;
    if (move) {
      const before = await search(fen);
      const after = before === null ? null : await search(fen, move.uci);
      ok = before !== null && after !== null && judgeByEval(fenTurn(fen), before, after).ok;
    }
    answers.set(key, ok);
    for (const listen of listeners) listen();
  }
  busy = false;
}

/** The engine's answer so far: true sound, false not, undefined not asked yet. */
export function soundness(fen: string, san: string): boolean | undefined {
  return answers.get(keyOf(fen, san));
}

/** Ask about moves, and re-render as the answers come in. */
export function useSoundness(questions: { fen: string; san: string }[]): (fen: string, san: string) => boolean | undefined {
  const [, setTick] = useState(0);
  const wanted = questions.map((q) => keyOf(q.fen, q.san)).join('\n');
  useEffect(() => {
    const listen = () => setTick((n) => n + 1);
    listeners.add(listen);
    let added = false;
    for (const q of questions) {
      const key = keyOf(q.fen, q.san);
      if (answers.has(key) || queue.some((w) => keyOf(w.fen, w.san) === key)) continue;
      queue.push(q);
      added = true;
    }
    if (added) void pump();
    return () => {
      listeners.delete(listen);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [wanted]);
  return soundness;
}
