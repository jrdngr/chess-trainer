import { useEffect, useRef, useState } from 'react';
import { applyUci, positionStatus, type LegalMove } from '../../chess/core';
import type { EngineLine, EngineSnapshot } from '../../engine/types';
import { getEngine } from '../../engine/useEngine';
import { judgeByEval } from '../../model/openingRun';
import type { Color } from '../../chess/core';

/** Your move, held until the engine has scored it. */
export interface Pending {
  /** The position you moved in. */
  from: string;
  san: string;
  uci: string;
}

export interface Judgement {
  san: string;
  ok: boolean;
  /** Centipawns dropped. */
  lost: number;
  /** The engine's own choice in the position, in SAN, when it had one. */
  best: string | null;
}

/** How long the engine thinks about each question, in milliseconds. */
const THINK_MS = 700;

/** A forced mate reads as a huge swing; take it as one. */
function scoreOf(line: EngineLine): number | null {
  if (line.cp !== null) return line.cp;
  if (line.mate !== null) return line.mate > 0 ? 10_000 : -10_000;
  return null;
}

/** The engine's final word on a position, once it has stopped. */
function settled(snap: EngineSnapshot, fen: string): EngineLine | null {
  // A stopped search reports back under its old position, so check the fen.
  if (snap.thinking || snap.fen !== fen) return null;
  const line = snap.lines[0];
  return line && scoreOf(line) !== null ? line : null;
}

/**
 * The engine as Survival's judge.
 *
 * The same two questions a Run's referee asks — what the position is worth,
 * and what it is worth with your move forced (`searchmoves`), both from the
 * same side of the board — plus the engine's own move, which the end screen
 * shows in green beside a blunder. Kept apart from the Run's referee so that
 * Survival and Autopilot never share a code path that could change one when
 * the other is changed.
 *
 * While `active` the first answer is kept ready for the position on the
 * board, so a verdict costs one search rather than two.
 */
export function useJudge({
  fen,
  color,
  active,
  onJudged,
}: {
  /** The position on the board, or null with nothing to judge. */
  fen: string | null;
  color: Color;
  active: boolean;
  onJudged: (judgement: Judgement) => void;
}) {
  const [pending, setPending] = useState<Pending | null>(null);
  const [baseline, setBaseline] = useState<{ fen: string; cp: number; best: string | null } | null>(null);
  const judged = useRef(onJudged);
  judged.current = onJudged;

  const warming = !!fen && active && !positionStatus(fen).gameOver;
  const wanted = pending?.from ?? (warming ? fen : null);
  const haveBaseline = !!wanted && baseline?.fen === wanted;

  useEffect(() => {
    if (!wanted || haveBaseline) return;
    let cancelled = false;
    const { engine, backend } = getEngine();
    void backend.then(() => {
      if (cancelled) return;
      engine.analyse(wanted, { movetime: THINK_MS, multiPv: 1 }, (snap) => {
        if (cancelled) return;
        const line = settled(snap, wanted);
        if (!line) return;
        cancelled = true;
        const best = line.pv[0] ? (applyUci(wanted, line.pv[0])?.san ?? null) : null;
        setBaseline({ fen: wanted, cp: scoreOf(line)!, best });
      });
    });
    return () => {
      cancelled = true;
      engine.stop();
    };
  }, [wanted, haveBaseline]);

  useEffect(() => {
    if (!pending || baseline?.fen !== pending.from) return;
    let cancelled = false;
    const { engine, backend } = getEngine();
    const { cp: before, best } = baseline;
    void backend.then(() => {
      if (cancelled) return;
      engine.analyse(pending.from, { movetime: THINK_MS, multiPv: 1, searchmoves: [pending.uci] }, (snap) => {
        if (cancelled) return;
        const line = settled(snap, pending.from);
        if (!line) return;
        cancelled = true;
        const result = judgeByEval(color, before, scoreOf(line)!);
        setPending(null);
        judged.current({ san: pending.san, ok: result.ok, lost: result.lost, best });
      });
    });
    return () => {
      cancelled = true;
      engine.stop();
    };
  }, [pending, baseline, color]);

  return {
    pending,
    submit(from: string, move: LegalMove) {
      if (pending) return;
      setPending({ from, san: move.san, uci: move.uci });
    },
    reset() {
      setPending(null);
      setBaseline(null);
    },
  };
}
