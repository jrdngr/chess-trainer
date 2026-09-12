import { useEffect, useRef, useState } from 'react';
import { applyUci, positionStatus, type LegalMove } from '../../chess/core';
import { formatScore, type EngineLine } from '../../engine/types';
import { useEngine } from '../../engine/useEngine';
import { isUsersTurn, judgeByEval, type Run } from '../../model/permadeath';

/** Your move past the prep, held until the engine has scored it. */
export interface Pending {
  /** The position you moved in. */
  from: string;
  san: string;
  /** The position you left behind. */
  after: string;
}

export type Verdict =
  | { san: string; ok: true; reply: string | null }
  | { san: string; ok: false; lost: number };

/** A forced mate reads as a huge swing; take it as one. */
function scoreOf(line: EngineLine): number | null {
  if (line.cp !== null) return line.cp;
  if (line.mate !== null) return line.mate > 0 ? 10_000 : -10_000;
  return null;
}

/**
 * The engine as referee, for the part of a run that has left the prep.
 *
 * It is asked about two positions in turn: the one you are about to move in,
 * which gives the score your move is measured against, and the one you leave
 * behind, which gives both the verdict and the opponent's reply. It runs
 * whether or not evaluations are switched on elsewhere — that setting is about
 * seeing numbers during recall, and here the engine is the judge. A short fixed
 * think keeps it quick on the asm.js build.
 */
export function useReferee({
  run,
  active,
  onVerdict,
}: {
  run: Run | null;
  active: boolean;
  onVerdict: (verdict: Verdict) => void;
}) {
  const [pending, setPending] = useState<Pending | null>(null);
  /** The engine's read on the position you are about to move in. */
  const [baseline, setBaseline] = useState<{ fen: string; cp: number } | null>(null);
  const verdict = useRef(onVerdict);
  verdict.current = onVerdict;

  const gameOver = run ? positionStatus(run.fen).gameOver : false;
  const probeFen =
    !active || !run || run.over || gameOver
      ? null
      : pending
        ? baseline?.fen === pending.from
          ? pending.after
          : pending.from
        : isUsersTurn(run)
          ? run.fen
          : null;
  const { snapshot } = useEngine(probeFen, {
    enabled: active,
    movetime: 700,
    multiPv: 1,
    debounceMs: 120,
  });

  /** Keep the score your next move will be measured against. */
  useEffect(() => {
    if (!active || !run || snapshot.thinking || snapshot.fen !== run.fen) return;
    const line = snapshot.lines[0];
    const cp = line ? scoreOf(line) : null;
    if (cp === null || baseline?.fen === run.fen) return;
    setBaseline({ fen: run.fen, cp });
  }, [active, run, snapshot, baseline?.fen]);

  /** Score the move you played, and let the engine answer if it stands. */
  useEffect(() => {
    if (!active || !run || !pending || baseline?.fen !== pending.from) return;
    // A stopped search reports back under its old position, so check the fen.
    if (snapshot.fen !== pending.after || snapshot.thinking) return;
    const line = snapshot.lines[0];
    const after = line ? scoreOf(line) : null;
    if (after === null) return;

    const result = judgeByEval(run.color, baseline.cp, after);
    setPending(null);
    if (!result.ok) {
      verdict.current({ san: pending.san, ok: false, lost: result.lost });
      return;
    }
    const replyUci = positionStatus(pending.after).gameOver ? null : (line!.pv[0] ?? null);
    const reply = replyUci ? (applyUci(pending.after, replyUci)?.san ?? null) : null;
    verdict.current({ san: pending.san, ok: true, reply });
  }, [active, run, pending, baseline, snapshot]);

  return {
    pending,
    /** Hand a move to the referee; the board shows it meanwhile. */
    submit(move: LegalMove) {
      if (!run || pending) return;
      setPending({ from: run.fen, san: move.san, after: move.after });
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
