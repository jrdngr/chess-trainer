import { useEffect, useRef, useState } from 'react';
import { positionStatus, type LegalMove } from '../../chess/core';
import { formatScore, type EngineLine, type EngineSnapshot } from '../../engine/types';
import { getEngine } from '../../engine/useEngine';
import { isUsersTurn, judgeByEval, type Run } from '../../model/openingRun';

/** Your move off the referee's script, held until the engine has scored it. */
export interface Pending {
  /** The position you moved in. */
  from: string;
  san: string;
  uci: string;
}

export interface Verdict {
  san: string;
  ok: boolean;
  /** Centipawns dropped. */
  lost: number;
}

/** How long the engine thinks about each question, in milliseconds. */
const THINK_MS = 700;

/** A forced mate reads as a huge swing; take it as one. */
function scoreOf(line: EngineLine): number | null {
  if (line.cp !== null) return line.cp;
  if (line.mate !== null) return line.mate > 0 ? 10_000 : -10_000;
  return null;
}

/** The engine's final word on a position: its top line's score, once it has stopped. */
function settled(snap: EngineSnapshot, fen: string): number | null {
  // A stopped search reports back under its old position, so check the fen.
  if (snap.thinking || snap.fen !== fen) return null;
  const line = snap.lines[0];
  return line ? scoreOf(line) : null;
}

/**
 * The engine as referee, and nothing else: it grades your move and never
 * picks the opponent's.
 *
 * It asks two questions of the position you moved in: what it is worth, and
 * what it is worth if the move has to be yours (`searchmoves`). Both are
 * answered from the same side of the board, which matters: an engine's score
 * for a position and its score for the position after the reply are not
 * mirror images — this build rates the side to move a pawn up at the start
 * — so comparing the two would fail a fine move. While `active` the first
 * answer is kept ready for the position you are looking at, so a verdict past
 * the hand-over costs one search rather than two; a move off your prep,
 * submitted cold, costs both. The referee runs whether or not evaluations are
 * switched on elsewhere — that setting is about seeing numbers during recall,
 * and here the engine is the judge.
 */
export function useReferee({
  run,
  active,
  onVerdict,
}: {
  run: Run | null;
  /** Keep a baseline ready for the current position, ahead of any move. */
  active: boolean;
  onVerdict: (verdict: Verdict) => void;
}) {
  const [pending, setPending] = useState<Pending | null>(null);
  /** The engine's read on the position you moved, or are about to move, in. */
  const [baseline, setBaseline] = useState<{ fen: string; cp: number } | null>(null);
  const verdict = useRef(onVerdict);
  verdict.current = onVerdict;

  const gameOver = run ? positionStatus(run.fen).gameOver : false;
  const warming = !!run && active && !run.over && !gameOver && isUsersTurn(run);
  /** The position a baseline is wanted for, if any. */
  const wanted = pending?.from ?? (warming ? run.fen : null);
  const haveBaseline = !!wanted && baseline?.fen === wanted;

  /** The score your move is measured against. */
  useEffect(() => {
    if (!wanted || haveBaseline) return;
    let cancelled = false;
    const { engine, backend } = getEngine();
    void backend.then(() => {
      if (cancelled) return;
      engine.analyse(wanted, { movetime: THINK_MS, multiPv: 1 }, (snap) => {
        if (cancelled) return;
        const cp = settled(snap, wanted);
        if (cp === null) return;
        cancelled = true;
        setBaseline({ fen: wanted, cp });
      });
    });
    return () => {
      cancelled = true;
      engine.stop();
    };
  }, [wanted, haveBaseline]);

  /** The score of the move you played, from the same side of the board. */
  useEffect(() => {
    if (!run || !pending || baseline?.fen !== pending.from) return;
    let cancelled = false;
    const { engine, backend } = getEngine();
    const before = baseline.cp;
    void backend.then(() => {
      if (cancelled) return;
      engine.analyse(pending.from, { movetime: THINK_MS, multiPv: 1, searchmoves: [pending.uci] }, (snap) => {
        if (cancelled) return;
        const after = settled(snap, pending.from);
        if (after === null) return;
        cancelled = true;
        const result = judgeByEval(run.color, before, after);
        setPending(null);
        verdict.current({ san: pending.san, ok: result.ok, lost: result.lost });
      });
    });
    return () => {
      cancelled = true;
      engine.stop();
    };
  }, [run, pending, baseline]);

  return {
    pending,
    /** Hand a move to the referee; the board shows it meanwhile. */
    submit(move: LegalMove) {
      if (!run || pending) return;
      setPending({ from: run.fen, san: move.san, uci: move.uci });
    },
    reset() {
      setPending(null);
      setBaseline(null);
    },
    /** The current position's score, once the engine has one. */
    liveScore:
      run && baseline?.fen === run.fen ? formatScore({ cp: baseline.cp, mate: null }) : null,
  };
}
