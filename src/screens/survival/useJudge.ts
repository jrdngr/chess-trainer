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
  /** The position before your move, in centipawns from White's side. */
  before: number;
  /** The position after your move, in centipawns from White's side. */
  after: number;
}

/** How long the engine thinks about each question, in milliseconds. */
const THINK_MS = 700;

/**
 * The second look at a move the quick check calls a blunder: both moves in
 * one search, to this depth, capped at this long. Two quick searches, run
 * apart, can land at different depths and disagree by more than a blunder on
 * the same move; one search that scores both side by side cannot.
 */
const CONFIRM_DEPTH = 16;
const CONFIRM_MS = 4000;

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
  const [baseline, setBaseline] = useState<{
    fen: string;
    cp: number;
    best: string | null;
    bestUci: string | null;
  } | null>(null);
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
        setBaseline({ fen: wanted, cp: scoreOf(line)!, best, bestUci: line.pv[0] ?? null });
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
    const { cp: before, best, bestUci } = baseline;
    const done = (judgement: Omit<Judgement, 'san' | 'best'>) => {
      cancelled = true;
      setPending(null);
      judged.current({ san: pending.san, best, ...judgement });
    };

    /** The quick check says blunder: look again, both moves in one deeper search. */
    const confirm = (quick: Omit<Judgement, 'san' | 'best'>) => {
      if (!bestUci || bestUci === pending.uci) {
        // Your move is the engine's own choice: whatever the scores say, not a blunder.
        done({ ...quick, ok: true, lost: 0 });
        return;
      }
      engine.analyse(
        pending.from,
        { depth: CONFIRM_DEPTH, movetime: CONFIRM_MS, multiPv: 2, searchmoves: [bestUci, pending.uci] },
        (snap) => {
          if (cancelled || snap.thinking || snap.fen !== pending.from) return;
          const top = snap.lines[0];
          const yours = snap.lines.find((line) => line.pv[0] === pending.uci);
          const topCp = top ? scoreOf(top) : null;
          const yourCp = yours ? scoreOf(yours) : null;
          if (topCp === null || yourCp === null) {
            done(quick);
            return;
          }
          const result = judgeByEval(color, topCp, yourCp);
          done({ ok: result.ok, lost: result.lost, before: topCp, after: yourCp });
        },
      );
    };

    void backend.then(() => {
      if (cancelled) return;
      engine.analyse(pending.from, { movetime: THINK_MS, multiPv: 1, searchmoves: [pending.uci] }, (snap) => {
        if (cancelled) return;
        const line = settled(snap, pending.from);
        if (!line) return;
        const after = scoreOf(line)!;
        const result = judgeByEval(color, before, after);
        const quick = { ok: result.ok, lost: result.lost, before, after };
        if (result.ok) done(quick);
        else confirm(quick);
      });
    });
    return () => {
      cancelled = true;
      engine.stop();
    };
  }, [pending, baseline, color]);

  return {
    pending,
    /** The engine's score for the position it last weighed, White's side. */
    baseline: baseline ? { fen: baseline.fen, cp: baseline.cp } : null,
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
