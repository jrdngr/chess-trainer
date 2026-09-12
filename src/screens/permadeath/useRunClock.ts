import { useEffect, useRef, useState } from 'react';
import { clockSpec, type ClockMode } from '../../model/permadeath';

/**
 * The run's clock. Only your own thinking is charged, so the opponent's beat
 * is free: a per-move budget is refilled at the start of each of your turns,
 * and a per-run budget carries what is left of it from turn to turn.
 *
 * Returns the seconds left to show, or null when there is no clock.
 */
export function useRunClock({
  mode,
  runId,
  active,
  onExpire,
}: {
  mode: ClockMode;
  /** A new id resets the budget. */
  runId: string | null;
  /** True while the clock should be running: your turn, nothing pending. */
  active: boolean;
  onExpire: () => void;
}): number | null {
  const { perMove, perRun } = clockSpec(mode);
  const budget = useRef<number | null>(null);
  const [shown, setShown] = useState<number | null>(null);
  const expire = useRef(onExpire);
  expire.current = onExpire;

  useEffect(() => {
    budget.current = perRun ?? perMove;
    setShown(budget.current);
  }, [runId, perRun, perMove]);

  useEffect(() => {
    if (!active || budget.current === null) return;
    if (perMove !== null) budget.current = perMove;
    const from = budget.current;
    const startedAt = Date.now();
    setShown(from);
    const timer = setInterval(() => {
      const left = from - (Date.now() - startedAt) / 1000;
      setShown(Math.max(0, left));
      if (left <= 0) {
        clearInterval(timer);
        expire.current();
      }
    }, 100);
    return () => {
      clearInterval(timer);
      // Charge only the time actually spent on this turn.
      budget.current = Math.max(0, from - (Date.now() - startedAt) / 1000);
    };
  }, [active, runId, perMove]);

  return shown;
}

export function formatClock(seconds: number): string {
  const whole = Math.ceil(seconds);
  if (whole < 60) return `${whole}s`;
  return `${Math.floor(whole / 60)}:${String(whole % 60).padStart(2, '0')}`;
}
