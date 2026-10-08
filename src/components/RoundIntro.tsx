import { useEffect, useMemo, useState, type ReactNode } from 'react';
import { lastMoveOf, sansToMoveText, walkSan, type Color, type Square } from '../chess/core';
import { deepestNodeWithin, nodeById, openingTree } from '../model/openingTree';
import { referenceIndex } from '../model/referenceIndex';
import { useStore } from '../store/useStore';
import { selectionTrail } from './Selection';

/**
 * How a round begins, in every mode and in Autopilot: the mode and the
 * opening announced full screen with no board, then the moves that lead to
 * the round's first position played out by the computer on a locked board.
 *
 * Openings change from one round to the next — under "Any favorite" every
 * round is another favorite — and a round that drops you straight into a
 * position is easy to play as the wrong line. So the opening is named large
 * before the board appears, stays on a pill over the board while the way in
 * plays, and a round that starts at move one keeps the pill until your first
 * move, which is where you choose the line.
 */
export interface IntroPlan {
  /** A new key is a new round, announced again. */
  key: string | number;
  /** The mode as the round is called, e.g. "Survival: Cold Start". */
  mode: string;
  /** The opening the round is in, an opening tree node id. */
  opening: string;
  /** What to call it where the node says too little, e.g. a Growth row's own name over "Any opening". */
  name?: string;
  color: Color;
  /** The moves to the round's first position, from move one; empty for a round that starts there. */
  path: string[];
}

/** How long the announcement holds before the board, unless tapped away. */
export const ANNOUNCE_MS = 2500;
/** The beat between replayed moves. */
export const REPLAY_MS = 400;
/** How long the board's edge pulses once the replay hands you the move. */
const PULSE_MS = 900;

type Stage = 'announce' | 'replay' | 'done';

interface IntroState {
  key: string | number | null;
  stage: Stage;
  ply: number;
  /** The plan as it was when the round began; the screen's own line moves on. */
  plan: IntroPlan | null;
  /** The first move has been made: the pill of a round from move one is gone for good. */
  moved: boolean;
  pulse: boolean;
}

export interface RoundIntro {
  /** Announcing or replaying: the board is locked, and clocks and the opponent wait. */
  held: boolean;
  /** The replay's position while it runs, in place of the round's. */
  fen: string | null;
  lastMove: { from: Square; to: Square } | null;
  /** The full-screen announcement, drawn over the whole screen. */
  cover: ReactNode;
  /** Over the board: the opening pill, the Autoplay chip, tap-to-skip and the pulse. */
  overlay: ReactNode;
  /** Under the board while the replay runs: the moves so far. */
  below: ReactNode;
}

const IDLE: IntroState = { key: null, stage: 'done', ply: 0, plan: null, moved: false, pulse: false };

/**
 * The opening a round is named by: the deepest named opening its way in
 * reaches inside the region, or the region itself.
 */
export function introOpening(region: string, path: string[]): string {
  const tree = openingTree(referenceIndex());
  return deepestNodeWithin(tree, nodeById(tree, region), path).id;
}

/**
 * The intro for the round `plan` describes, or nothing while there is no
 * round yet. `moved` is whether you have made a move this round.
 */
export function useRoundIntro(plan: IntroPlan | null, moved: boolean): RoundIntro {
  const [state, setState] = useState<IntroState>(IDLE);
  /**
   * With Autoplay off the round starts on its position, and the opening pill
   * stays until your first move as it does for a round from move one.
   */
  const autoplay = useStore((s) => s.settings.autoplay);

  // A new round starts its intro at once, in the same render, so the board
  // never shows the round's position before the announcement covers it.
  let current = state;
  if (plan && plan.key !== state.key) {
    current = { key: plan.key, stage: 'announce', ply: 0, plan: autoplay ? plan : { ...plan, path: [] }, moved: false, pulse: false };
    setState(current);
  }
  const shown = current.plan;
  const path = shown?.path ?? [];
  const fens = useMemo(() => walkSan(path).fens, [path]);

  const toBoard = () =>
    setState((s) => (s.stage !== 'announce' ? s : { ...s, stage: s.plan?.path.length ? 'replay' : 'done' }));
  const skip = () =>
    setState((s) => (s.stage !== 'replay' ? s : { ...s, stage: 'done', ply: s.plan?.path.length ?? 0, pulse: true }));

  useEffect(() => {
    if (current.stage !== 'announce') return;
    const timer = window.setTimeout(toBoard, ANNOUNCE_MS);
    return () => window.clearTimeout(timer);
  }, [current.stage, current.key]);

  useEffect(() => {
    if (current.stage !== 'replay') return;
    const timer = window.setTimeout(() => {
      setState((s) => {
        if (s.stage !== 'replay') return s;
        const total = s.plan?.path.length ?? 0;
        return s.ply < total ? { ...s, ply: s.ply + 1 } : { ...s, stage: 'done', pulse: true };
      });
    }, REPLAY_MS);
    return () => window.clearTimeout(timer);
  }, [current.stage, current.ply, current.key]);

  useEffect(() => {
    if (!current.pulse) return;
    const timer = window.setTimeout(() => setState((s) => ({ ...s, pulse: false })), PULSE_MS);
    return () => window.clearTimeout(timer);
  }, [current.pulse]);

  useEffect(() => {
    if (moved && current.plan && !current.moved && current.stage === 'done') setState((s) => ({ ...s, moved: true }));
  }, [moved, current.plan, current.moved, current.stage]);

  if (!plan || !shown) return { held: false, fen: null, lastMove: null, cover: null, overlay: null, below: null };

  const held = current.stage !== 'done';
  const replaying = current.stage === 'replay';
  const announcing = current.stage === 'announce';
  const trail = shown.name ? [shown.name] : selectionTrail(shown.opening);
  const name = trail[trail.length - 1];
  const pill = replaying || (current.stage === 'done' && path.length === 0 && !current.moved && !moved);

  return {
    held,
    fen: held ? fens[current.ply] : null,
    lastMove: held ? lastMoveOf(path.slice(0, current.ply)) : null,
    cover: announcing ? (
      <div className="round-intro" onPointerDown={toBoard} role="presentation">
        <div className="ri-mode" style={{ ['--len' as string]: shown.mode.length }}>
          {shown.mode}
        </div>
        <div className="ri-opening">
          <span>{trail.join(' › ')}</span>
        </div>
      </div>
    ) : null,
    overlay:
      pill || replaying || current.pulse ? (
        <>
          {replaying && <div className="intro-skip" onPointerDown={skip} />}
          {pill && (
            <div className="intro-pill" key={replaying ? 'replay' : 'wait'}>
              {replaying && <span className="chip intro-auto">Autoplay</span>}
              <span className="truncate">{name}</span>
            </div>
          )}
          {current.pulse && <div className="intro-pulse" />}
        </>
      ) : null,
    below: replaying ? <div className="center small muted mt-8 intro-moves">{sansToMoveText(path.slice(0, current.ply)) || ' '}</div> : null,
  };
}
