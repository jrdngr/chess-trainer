import { useMemo, useState, type ReactNode } from 'react';
import type { Color } from '../chess/core';
import { useCashOut } from '../engine/cashOut';
import { goalRoute } from '../model/boardHints';
import { planFor, structureLabel, structureOf } from '../model/structures';
import type { Arrow } from './Board';
import { Icons } from './Icons';

/**
 * The cards past the end of prep: the plan for the pawn structure on the
 * board, and Cash out when you are well ahead. Each is a row under the board
 * that opens on a tap and draws its arrows while open; the × puts it away
 * until there is something new to say.
 */

/** Cyan reads on both square colors, where the app's violet sank into the dark ones (Jordan picked it from five). */
const PLAN_COLOR = '#22c3e6';
const TRADE_COLOR = 'var(--good)';

interface CardArgs {
  fen: string;
  me: Color;
  enabled: boolean;
  /** A put-away card comes back when this changes: a new run. */
  resetKey: string;
}

export function usePlanCard({ fen, me, enabled, resetKey }: CardArgs): {
  card: ReactNode;
  arrows: Arrow[];
} {
  const structure = useMemo(() => (enabled ? structureOf(fen) : null), [fen, enabled]);
  const [open, setOpen] = useState(false);
  /** The structure whose card was put away; a new structure brings it back. */
  const [dismissed, setDismissed] = useState<string | null>(null);
  const shown = !!structure && dismissed !== `${resetKey}:${structure.template.id}:${structure.a}`;
  const steps = useMemo(
    () =>
      structure && shown
        ? planFor(structure, me).map((s) => ({ ...s, route: s.goal ? goalRoute(fen, me, s.goal) : null }))
        : [],
    [structure, shown, fen, me],
  );
  if (!structure || !shown) return { card: null, arrows: [] };
  const arrows: Arrow[] = open
    ? steps.flatMap((s) => (s.route?.done ? [] : (s.route?.arrows ?? []).map((a) => ({ ...a, color: PLAN_COLOR }))))
    : [];
  const card = (
    <div className="card plan-card">
      <div className="plan-head">
        <button className="plan-toggle" onClick={() => setOpen((o) => !o)} aria-expanded={open}>
          <span className="plan-kind">Plan</span>
          <span className="truncate">{structureLabel(structure)}</span>
          <span className={`plan-chev${open ? ' open' : ''}`}>{Icons.chevron({ size: 16 })}</span>
        </button>
        <button
          className="icon-btn plain plan-x"
          aria-label="Hide plan"
          onClick={() => {
            setDismissed(`${resetKey}:${structure.template.id}:${structure.a}`);
            setOpen(false);
          }}
        >
          {Icons.close({ size: 16 })}
        </button>
      </div>
      {open && (
        <ol className="plan-steps">
          {steps.map((s) => (
            <li key={s.text} className={s.route?.done ? 'done' : undefined}>
              {s.route?.done && <span className="plan-done">{Icons.check({ size: 14 })}</span>}
              {s.text}
            </li>
          ))}
        </ol>
      )}
    </div>
  );
  return { card, arrows };
}

export function useCashOutCard({ fen, me, enabled, resetKey }: CardArgs): {
  card: ReactNode;
  arrows: Arrow[];
} {
  /** Put away for the rest of the run: once said, it would only nag. */
  const [dismissedIn, setDismissedIn] = useState<string | null>(null);
  const [open, setOpen] = useState(false);
  const trade = useCashOut(fen, me, enabled && dismissedIn !== resetKey);
  if (!trade) return { card: null, arrows: [] };
  const card = (
    <div className="card plan-card">
      <div className="plan-head">
        <button className="plan-toggle" onClick={() => setOpen((o) => !o)} aria-expanded={open}>
          <span className="plan-kind good">Cash out</span>
          <span className="truncate">{open ? `Trade with ${trade.san}` : 'Ahead: trade down?'}</span>
        </button>
        <button className="icon-btn plain plan-x" aria-label="Hide cash out" onClick={() => setDismissedIn(resetKey)}>
          {Icons.close({ size: 16 })}
        </button>
      </div>
    </div>
  );
  return { card, arrows: open ? [{ from: trade.from, to: trade.to, color: TRADE_COLOR }] : [] };
}
