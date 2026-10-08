import { useEffect, useMemo, useRef, useState } from 'react';
import { ANY_FAVORITE } from '../model/anyFavorite';
import { earned, milestones, nextUp, progress, type Milestone } from '../model/milestones';
import { openingTree } from '../model/openingTree';
import { referenceIndex } from '../model/referenceIndex';
import { ratingChange, streak } from '../model/scoring';
import { HISTORY_RUNS, survivalFor } from '../model/survival';
import { useStore } from '../store/useStore';
import { TierBar } from './ScoreBar';
import { favoriteEntries, SideDot } from './Selection';
import { Icons, Sheet, toast } from './ui';

/* ── Survival runs ──────────────────────────────────────────────────────── */

/**
 * The last runs' moves survived as bars, the latest lit, with a dashed line at
 * the best. Follows the selection: one opening's runs, or every run under Any
 * opening and Any favorite. Runs you ended yourself are not in it.
 */
export function SurvivalRuns() {
  const selection = useStore((s) => s.settings.selection);
  const record = useStore((s) => s.survival);
  const id = selection.opening === ANY_FAVORITE ? '' : selection.opening;
  const score = survivalFor(record, id);
  const runs = score.history;

  const W = 320;
  const H = 92;
  const base = H - 14;
  const top = 8;
  const max = Math.max(10, score.best, ...runs) * 1.1;
  const y = (v: number) => base - (v / max) * (base - top);
  const slot = (W - 8) / HISTORY_RUNS;
  // The latest run sits at the right edge; slots before the first run stay empty.
  const offset = HISTORY_RUNS - runs.length;

  return (
    <div className="card home-card">
      <div className="home-card-head">
        <span className="t">Survival</span>
        {score.best > 0 && <span className="aside">best {score.best}</span>}
      </div>
      <svg viewBox={`0 0 ${W} ${H}`} width="100%" role="img" aria-label={`Moves survived in the last ${runs.length} runs`}>
        {Array.from({ length: HISTORY_RUNS }, (_, i) => {
          const v = runs[i - offset];
          const x = 4 + i * slot + 2;
          if (v === undefined) return <rect key={i} x={x} y={base - 3} width={slot - 4} height={3} rx={1.5} fill="var(--surface-2)" />;
          const h = Math.max(3, base - y(v));
          const last = i === HISTORY_RUNS - 1;
          return <rect key={i} x={x} y={base - h} width={slot - 4} height={h} rx={3} fill={last ? 'var(--accent)' : 'var(--surface-3)'} />;
        })}
        {score.best > 0 && (
          <line x1={4} x2={W - 4} y1={y(score.best)} y2={y(score.best)} stroke="var(--warn)" strokeDasharray="3 4" strokeWidth={1.5} />
        )}
        <text x={4} y={H - 2} fontSize={10} fill="var(--text-3)">
          {HISTORY_RUNS} runs ago
        </text>
        <text x={W - 4} y={H - 2} fontSize={10} fill="var(--text-3)" textAnchor="end">
          last
        </text>
      </svg>
    </div>
  );
}

/* ── Favorites ──────────────────────────────────────────────────────────── */

/**
 * Every favorite with its tier and its rating, highest first, and how far the
 * rating moved this week. Tapping one selects it, with its side.
 */
export function FavoritesLadder() {
  const favorites = useStore((s) => s.settings.favoriteOpenings);
  const score = useStore((s) => s.score);
  const selection = useStore((s) => s.settings.selection);
  const setSelection = useStore((s) => s.setSelection);

  const rows = useMemo(() => {
    const now = Date.now();
    return favoriteEntries(favorites)
      .map((entry) => {
        const stats = score.nodes[entry.node.id];
        const rated = stats?.rated ?? 0;
        return {
          ...entry,
          rating: stats?.rating ?? 0,
          rated,
          change: stats && rated > 0 ? Math.round(ratingChange(stats, 7, now)) : null,
        };
      })
      .sort((a, b) => Number(b.rated > 0) - Number(a.rated > 0) || b.rating - a.rating);
  }, [favorites, score]);

  if (rows.length === 0) return null;
  return (
    <div className="card home-card">
      <div className="home-card-head">
        <span className="t">Favorites</span>
        <span className="aside">this week</span>
      </div>
      <div className="fav-ladder">
        {rows.map((row) => (
          <button
            key={row.node.id}
            className={`fav-row${selection.opening === row.node.id ? ' selected' : ''}`}
            onClick={() => setSelection({ opening: row.node.id, color: row.side })}
          >
            <SideDot side={row.side} />
            <span className="nm truncate">{row.label}</span>
            <TierBar rating={row.rating} rated={row.rated} />
            <span className="num">{row.rated > 0 ? Math.round(row.rating) : ''}</span>
            <span className={`chg${row.change === null || row.change === 0 ? ' flat' : row.change > 0 ? ' up' : ' down'}`}>
              {row.change === null ? '' : row.change === 0 ? '–' : `${row.change > 0 ? '▲' : '▼'}${Math.abs(row.change)}`}
            </span>
          </button>
        ))}
      </div>
    </div>
  );
}

/* ── Milestones ─────────────────────────────────────────────────────────── */

/** Every milestone, recomputed as the record changes. */
export function useMilestones(): Milestone[] {
  const score = useStore((s) => s.score);
  const survival = useStore((s) => s.survival);
  return useMemo(() => milestones(score, survival, openingTree(referenceIndex())), [score, survival]);
}

/**
 * A toast for each milestone earned, once the round that earned it is
 * recorded, so a tier reached mid-run waits for the run to end. What was
 * already earned when the app opened is never announced.
 */
export function useMilestoneToasts() {
  const list = useMilestones();
  const rounds = useStore((s) => s.score.rounds.length);
  const ready = useStore((s) => s.ready);
  const announced = useRef<Set<string> | null>(null);
  const lastRounds = useRef(rounds);
  useEffect(() => {
    if (!ready) return;
    const won = list.filter(earned);
    if (announced.current === null) {
      announced.current = new Set(won.map((m) => m.id));
      lastRounds.current = rounds;
      return;
    }
    if (rounds === lastRounds.current) return;
    lastRounds.current = rounds;
    const fresh = won.filter((m) => !announced.current!.has(m.id));
    for (const m of fresh) announced.current.add(m.id);
    if (fresh.length) toast(`Milestone · ${fresh.map((m) => m.label).join(', ')}`);
  }, [list, rounds, ready]);
}

/** The next four to earn, ringed by how close they are; all of them in a sheet. */
export function MilestonesCard() {
  const list = useMilestones();
  const [open, setOpen] = useState(false);
  const days = useStore((s) => streak(s.score.global));
  const done = list.filter(earned).length;
  // The streak always leads; the three closest of the rest follow it.
  const next = nextUp(
    list.filter((m) => m.kind !== 'streak'),
    3,
  );

  return (
    <>
      <button className="card home-card" onClick={() => setOpen(true)}>
        <div className="home-card-head">
          <span className="t">Milestones</span>
          <span className="aside">
            {done} of {list.length}
          </span>
        </div>
        <div className="badge-row">
          <StreakBadge days={days} />
          {(next.length ? next : list.filter((m) => m.kind !== 'streak').slice(-3)).map((m) => (
            <Badge key={m.id} milestone={m} />
          ))}
        </div>
      </button>
      <Sheet open={open} onClose={() => setOpen(false)} title="Milestones">
        <div className="badge-grid">
          {list.map((m) => (
            <Badge key={m.id} milestone={m} />
          ))}
        </div>
      </Sheet>
    </>
  );
}

/** Streak goals the ring climbs toward; past the last one it stays full. */
const STREAK_STEPS = [3, 7, 30];

/** Your current streak: the days in the middle, ringed toward the next streak milestone. */
function StreakBadge({ days }: { days: number }) {
  const goal = STREAK_STEPS.find((n) => n > days);
  const share = goal ? days / goal : 1;
  const lit = days > 0;
  return (
    <span className={`badge${lit ? ' won' : ''}`} aria-label={`${days} day streak`}>
      <svg width="52" height="52" viewBox="0 0 52 52" aria-hidden>
        <circle cx="26" cy="26" r={RING} fill="none" stroke="var(--surface-3)" strokeWidth="4" />
        {share > 0 && (
          <circle
            cx="26"
            cy="26"
            r={RING}
            fill="none"
            stroke="var(--warn)"
            strokeWidth="4"
            strokeLinecap="round"
            strokeDasharray={`${CIRC * share} ${CIRC}`}
            transform="rotate(-90 26 26)"
          />
        )}
        <foreignObject x="13" y="13" width="26" height="26">
          <span className="badge-glyph streak" style={{ color: lit ? 'var(--warn)' : 'var(--text-3)' }}>
            <Icons.flame size={13} filled={lit} />
            <b className="badge-num">{days}</b>
          </span>
        </foreignObject>
      </svg>
      <span className="badge-name">{days === 1 ? '1 day' : `${days} days`}</span>
    </span>
  );
}

const RING = 21;
const CIRC = 2 * Math.PI * RING;

/** One milestone: lit when earned, dimmed with a ring of progress when not. */
export function Badge({ milestone }: { milestone: Milestone }) {
  const won = earned(milestone);
  const tint = milestone.color ?? (milestone.kind === 'streak' ? 'var(--warn)' : 'var(--accent)');
  return (
    <span className={`badge${won ? ' won' : ''}`} aria-label={`${milestone.label}${won ? ', earned' : ''}`}>
      <svg width="52" height="52" viewBox="0 0 52 52" aria-hidden>
        <circle cx="26" cy="26" r={RING} fill={won ? 'var(--surface-3)' : 'none'} stroke="var(--surface-3)" strokeWidth="4" />
        {!won && progress(milestone) > 0 && (
          <circle
            cx="26"
            cy="26"
            r={RING}
            fill="none"
            stroke={tint}
            strokeWidth="4"
            strokeLinecap="round"
            strokeDasharray={`${CIRC * progress(milestone)} ${CIRC}`}
            transform="rotate(-90 26 26)"
          />
        )}
        <foreignObject x="13" y="13" width="26" height="26">
          <span className="badge-glyph" style={{ color: won ? tint : 'var(--text-3)' }}>
            <Glyph milestone={milestone} />
          </span>
        </foreignObject>
      </svg>
      <span className="badge-name">{milestone.label}</span>
    </span>
  );
}

function Glyph({ milestone }: { milestone: Milestone }) {
  switch (milestone.kind) {
    case 'streak':
      return <Icons.flame size={20} filled={earned(milestone)} />;
    case 'tier':
      return <Icons.star size={20} filled={earned(milestone)} />;
    case 'breadth':
      return <Icons.tree size={20} />;
    case 'survival':
      return <b className="badge-num">{milestone.target}</b>;
    case 'rounds':
      return <b className="badge-num">{milestone.target >= 1000 ? `${milestone.target / 1000}k` : milestone.target}</b>;
  }
}
