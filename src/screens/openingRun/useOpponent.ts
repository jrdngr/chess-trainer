import { useEffect, useRef } from 'react';
import { applyUci, positionStatus } from '../../chess/core';
import { getEngine } from '../../engine/useEngine';
import { chooseMove, levelById, type Level } from '../../model/play';

/** The engine plays the opponent at Club, once the book has nothing left. */
export const OPPONENT_LEVEL: Level = levelById('club');

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
    const { engine, backend } = getEngine();
    void backend.then(() => {
      if (cancelled) return;
      engine.analyse(fen, { depth: OPPONENT_LEVEL.depth, multiPv: OPPONENT_LEVEL.multiPv }, (snap) => {
        if (cancelled || snap.thinking) return;
        const uci = chooseMove(snap.lines, OPPONENT_LEVEL, rand.current);
        const chosen = uci ? applyUci(fen, uci) : null;
        if (!chosen) return;
        cancelled = true;
        move.current(chosen.san);
      });
    });
    return () => {
      cancelled = true;
      engine.stop();
    };
  }, [fen, enabled]);
}
