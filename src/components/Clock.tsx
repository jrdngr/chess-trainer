import { useCallback, useEffect, useRef, useState } from 'react';

/**
 * A budget for one move.
 *
 * Only your own thinking is charged: the clock starts when `active` turns on
 * (your turn, nothing pending) and stops when it turns off. A new `turnKey`
 * is a new move and a fresh budget. Running out ends nothing and costs
 * nothing — the clock is pressure, not a rate — so it parks at zero and waits
 * with you. Taking your time still shows in the grade the move is reviewed at,
 * which is what decides when the position is asked again.
 */
export interface MoveClock {
  /** Seconds left, or null with no clock. */
  left: number | null;
  /** Seconds per move, or null with no clock. */
  budget: number | null;
  /** True once the budget is spent. */
  expired: boolean;
  /** Seconds spent on the current move so far. */
  elapsedNow: () => number;
}

export function useMoveClock({
  seconds,
  turnKey,
  active,
}: {
  seconds: number | null;
  turnKey: string | number;
  active: boolean;
}): MoveClock {
  const startedAt = useRef<number | null>(null);
  const spent = useRef(0);
  const [elapsed, setElapsed] = useState(0);

  useEffect(() => {
    startedAt.current = null;
    spent.current = 0;
    setElapsed(0);
  }, [turnKey]);

  useEffect(() => {
    if (!active) return;
    const from = spent.current;
    startedAt.current = Date.now();
    setElapsed(from);
    const timer = setInterval(() => {
      const now = from + (Date.now() - (startedAt.current ?? Date.now())) / 1000;
      setElapsed(now);
      if (seconds !== null && now >= seconds) clearInterval(timer);
    }, 100);
    return () => {
      clearInterval(timer);
      spent.current = from + (Date.now() - (startedAt.current ?? Date.now())) / 1000;
      startedAt.current = null;
    };
  }, [active, turnKey, seconds]);

  const elapsedNow = useCallback(
    () =>
      startedAt.current === null
        ? spent.current
        : spent.current + (Date.now() - startedAt.current) / 1000,
    [],
  );

  if (seconds === null) {
    return { left: null, budget: null, expired: false, elapsedNow };
  }
  const left = Math.max(0, seconds - elapsed);
  return { left, budget: seconds, expired: left <= 0, elapsedNow };
}

/**
 * The clock, in the app bar: a ring that empties as the budget goes, shaking
 * and greying out when it reaches nothing.
 */
export function ClockHud({ clock }: { clock: MoveClock }) {
  if (clock.left === null || clock.budget === null) return null;
  const share = clock.left / clock.budget;
  const tone = clock.expired ? 'out' : share < 0.5 ? 'late' : 'early';
  return (
    <span className={`clock-hud ${tone}`} key={clock.expired ? 'out' : 'in'}>
      <span className="ring" style={{ ['--share' as string]: share }} />
      <span className="left num">{Math.ceil(clock.left)}</span>
    </span>
  );
}
