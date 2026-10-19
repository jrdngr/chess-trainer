import { useEffect, useRef } from 'react';
import { applyUci, positionStatus } from '../../chess/core';
import { createHeuristicEngine } from '../../engine/heuristic';
import type { Engine, EngineSnapshot } from '../../engine/types';
import { engineReady } from '../../engine/useEngine';
import { chooseMove, levelById, type Level } from '../../model/play';

/** The engine plays the opponent at Club, once the book has nothing left. */
export const OPPONENT_LEVEL: Level = levelById('club');

/** How long the opponent waits on the engine before the heuristic answers instead. */
const GIVE_UP_MS = 15_000;

/**
 * The engine as opponent, for the part of a run the book has run out on.
 *
 * Only ever past the hand-over, and only where the book is silent: while the
 * book has a move the opponent plays that, by popularity, because you are
 * still in the opening and the book is what you would actually meet. Here the
 * engine picks a move the way Play does at Club — a short search over a few
 * candidates, and not always the best of them — rather than the top line at
 * full strength, which is nobody's opponent.
 */
export function useOpponent({
  fen,
  enabled,
  onMove,
}: {
  /** The position to move in, on the opponent's turn. */
  fen: string | null;
  enabled: boolean;
  onMove: (san: string) => void;
}) {
  const move = useRef(onMove);
  move.current = onMove;
  const rand = useRef(Math.random);

  useEffect(() => {
    if (!enabled || !fen || positionStatus(fen).gameOver) return;
    let cancelled = false;
    let engine: Engine | null = null;
    /** Play the first usable answer, from whichever engine gives it. */
    const answer = (snap: EngineSnapshot) => {
      const uci = chooseMove(snap.lines, OPPONENT_LEVEL, rand.current);
      const chosen = uci ? applyUci(fen, uci) : null;
      if (!chosen) return false;
      cancelled = true;
      window.clearTimeout(watchdog);
      move.current(chosen.san);
      return true;
    };
    // Never leave the run waiting on an engine with nothing to say: an empty
    // answer, or none at all, and the heuristic picks the move instead.
    const fallBack = () => {
      if (cancelled) return;
      engine?.stop();
      const backup = createHeuristicEngine();
      backup.analyse(fen, { depth: OPPONENT_LEVEL.depth, multiPv: OPPONENT_LEVEL.multiPv }, (snap) => {
        if (snap.thinking) return;
        if (!cancelled) answer(snap);
        backup.dispose();
      });
    };
    const watchdog = window.setTimeout(fallBack, GIVE_UP_MS);
    void engineReady().then((ready) => {
      if (cancelled) return;
      engine = ready;
      ready.analyse(fen, { depth: OPPONENT_LEVEL.depth, multiPv: OPPONENT_LEVEL.multiPv }, (snap) => {
        if (cancelled || snap.thinking) return;
        if (!answer(snap)) fallBack();
      });
    });
    return () => {
      cancelled = true;
      window.clearTimeout(watchdog);
      engine?.stop();
    };
  }, [fen, enabled]);
}
