import { useEffect, useRef, useState } from 'react';
import { applyUci, positionStatus, type LegalMove } from '../../chess/core';
import type { EngineLine, EngineSnapshot } from '../../engine/types';
import { getEngine } from '../../engine/useEngine';
import { judgeByEval } from '../../model/openingRun';
import { isMoment, MOMENT_FOUND } from '../../model/survival';
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
  /** The position was a moment: one move far better than the rest. */
  moment: boolean;
  /** At a moment, your move was that one, or close enough to it. */
  found: boolean;
}

/** How long the engine thinks about each question, in milliseconds. */
const THINK_MS = 700;

/**
 * How far one search may go on a move that looks like a blunder at the quick
 * check: this deep, capped at this long. Past the quick check the same search
 * simply keeps thinking, so only a suspected blunder pays for the extra time.
 */
const CONFIRM_DEPTH = 16;
const CONFIRM_MS = 4000;

/** The better of two scores in White's frame, for the side to move. */
function colorBest(color: Color, a: number, b: number): number {
  return color === 'w' ? Math.max(a, b) : Math.min(a, b);
}

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
  moments,
  onJudged,
}: {
  /** The position on the board, or null with nothing to judge. */
  fen: string | null;
  color: Color;
  active: boolean;
  /**
   * Look for moments: the engine is asked for its two best moves, and a
   * position where the best is far ahead is one. Your move there is judged
   * against the second best, so missing the chance is not a blunder.
   */
  moments: boolean;
  onJudged: (judgement: Judgement) => void;
}) {
  const [pending, setPending] = useState<Pending | null>(null);
  const [baseline, setBaseline] = useState<{
    fen: string;
    cp: number;
    best: string | null;
    bestUci: string | null;
    /** The engine's second choice, when it was asked for two. */
    second: { cp: number; uci: string } | null;
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
      engine.analyse(wanted, { movetime: THINK_MS, multiPv: moments ? 2 : 1 }, (snap) => {
        if (cancelled) return;
        const line = settled(snap, wanted);
        if (!line) return;
        cancelled = true;
        const best = line.pv[0] ? (applyUci(wanted, line.pv[0])?.san ?? null) : null;
        const next = moments ? snap.lines[1] : undefined;
        const nextCp = next ? scoreOf(next) : null;
        setBaseline({
          fen: wanted,
          cp: scoreOf(line)!,
          best,
          bestUci: line.pv[0] ?? null,
          second: next && next.pv[0] && nextCp !== null ? { cp: nextCp, uci: next.pv[0] } : null,
        });
      });
    });
    return () => {
      cancelled = true;
      engine.stop();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [wanted, haveBaseline]);

  useEffect(() => {
    if (!pending || baseline?.fen !== pending.from) return;
    let cancelled = false;
    const { engine, backend } = getEngine();
    const { best, bestUci } = baseline;
    const theirs = bestUci && bestUci !== pending.uci ? bestUci : null;
    const moment = moments && isMoment(color, baseline.cp, baseline.second?.cp ?? null);
    /** At a moment you missed, the second best is what your move answers to. */
    const second = moment && theirs && baseline.second && baseline.second.uci !== pending.uci ? baseline.second.uci : null;
    const started = Date.now();

    /**
     * Both moves scored at the same depth of the same search, or null while
     * the search is between iterations. Once it has stopped, the last word on
     * each, even when a time limit cut one iteration short.
     */
    const weigh = (snap: EngineSnapshot) => {
      const yours = snap.lines.find((line) => line.pv[0] === pending.uci);
      const top = theirs ? snap.lines.find((line) => line.pv[0] === theirs) : yours;
      const next = second ? snap.lines.find((line) => line.pv[0] === second) : null;
      if (!yours || !top || (snap.thinking && yours.depth !== top.depth)) return null;
      if (second && (!next || (snap.thinking && next.depth !== yours.depth))) return null;
      const yourCp = scoreOf(yours);
      const topCp = scoreOf(top);
      if (yourCp === null || topCp === null) return null;
      // Your move scored above the engine's: nothing lost, and the position is worth what yours is.
      const before = colorBest(color, topCp, yourCp);
      const result = judgeByEval(color, before, yourCp);
      const found = moment && result.lost <= MOMENT_FOUND;
      // A moment missed is judged against the next best move, not the one you did not see.
      const nextCp = next ? scoreOf(next) : null;
      const ok =
        moment && !found && nextCp !== null ? judgeByEval(color, colorBest(color, nextCp, yourCp), yourCp).ok : result.ok;
      return { ok, lost: result.lost, before, after: yourCp, found };
    };

    void backend.then(() => {
      if (cancelled) return;
      engine.analyse(
        pending.from,
        {
          depth: CONFIRM_DEPTH,
          movetime: CONFIRM_MS,
          multiPv: second ? 3 : theirs ? 2 : 1,
          searchmoves: second ? [theirs!, second, pending.uci] : theirs ? [theirs, pending.uci] : [pending.uci],
        },
        (snap) => {
          if (cancelled || snap.fen !== pending.from) return;
          const verdict = weigh(snap);
          const finished = !snap.thinking;
          // Your move is the engine's own choice: never a blunder, whatever the score.
          const passed = verdict && (verdict.ok || !theirs);
          // A sound move is settled at the quick check; a blunder waits for the whole search.
          if (!finished && !(passed && Date.now() - started >= THINK_MS)) return;
          cancelled = true;
          if (!finished) engine.stop();
          setPending(null);
          const judgement = verdict ?? { ok: true, lost: 0, before: baseline.cp, after: baseline.cp, found: false };
          judged.current({
            san: pending.san,
            best,
            moment,
            ...judgement,
            // Your move is the engine's own choice: sound, and at a moment, found.
            ...(theirs ? {} : { ok: true, lost: 0, found: moment }),
          });
        },
      );
    });
    return () => {
      cancelled = true;
      engine.stop();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [pending, baseline, color]);

  return {
    pending,
    /** The engine's score for the position it last weighed, White's side. */
    baseline: baseline ? { fen: baseline.fen, cp: baseline.cp } : null,
    /** The position it last weighed is a moment — see `isMoment`. */
    momentAt: baseline && moments && isMoment(color, baseline.cp, baseline.second?.cp ?? null) ? baseline.fen : null,
    /** The engine's best move where it last weighed, as a UCI move. */
    bestUci: baseline?.bestUci ?? null,
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
