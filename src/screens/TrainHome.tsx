import { useMemo } from 'react';
import { Icons } from '../components/ui';
import { buildSession, type TrainingItem } from '../model/session';
import { countDue, DAY, forecast, masteryBuckets, retention } from '../model/srs';
import { itemsFor, repertoireList, useStore } from '../store/useStore';
import type { Repertoire } from '../model/types';

export interface TrainHomeProps {
  onStart: (queue: TrainingItem[], title: string) => void;
  onOpenSettings: () => void;
}

export function TrainHome({ onStart, onOpenSettings }: TrainHomeProps) {
  const state = useStore();
  const reps = repertoireList(state);
  const now = Date.now();

  const perRep = useMemo(
    () =>
      reps.map((rep) => {
        const items = itemsFor(rep);
        const cards = items.map((i) => state.cards[i.cardId]).filter(Boolean);
        const unseen = items.length - cards.length;
        const counts = countDue(cards, now);
        return { rep, items, counts, unseen, total: items.length };
      }),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [reps, state.cards],
  );

  const allCards = Object.values(state.cards);
  const totalItems = perRep.reduce((s, r) => s + r.total, 0);
  const totalDue = perRep.reduce((s, r) => s + r.counts.due, 0);
  const totalUnseen = perRep.reduce((s, r) => s + r.unseen, 0);
  const learning = perRep.reduce((s, r) => s + r.counts.learning, 0);
  const mastery = masteryBuckets(allCards);
  const ret = retention(allCards);
  const week = forecast(allCards, 7, now);
  const maxWeek = Math.max(1, ...week);

  const startAll = () => {
    const items = perRep.flatMap((r) => r.items);
    const queue = buildSession(items, state.cards, {
      mode: 'due',
      now,
      maxItems: state.settings.maxSessionLength,
      maxNew: state.settings.newCardsPerSession,
      seed: Math.floor(now / 60000),
    });
    onStart(queue, 'Due review');
  };

  const startRep = (entry: (typeof perRep)[number], mode: 'due' | 'cram' | 'new') => {
    const queue = buildSession(entry.items, state.cards, {
      mode,
      now,
      maxItems: state.settings.maxSessionLength,
      maxNew: mode === 'new' ? state.settings.newCardsPerSession : state.settings.newCardsPerSession,
      seed: Math.floor(now / 60000),
    });
    onStart(queue, entry.rep.name);
  };

  const readyCount = Math.min(
    state.settings.maxSessionLength,
    totalDue + Math.min(totalUnseen, state.settings.newCardsPerSession),
  );

  return (
    <>
      <div className="appbar">
        <div className="appbar-title">
          <h1>Train</h1>
        </div>
        <button className="btn plain sm" onClick={onOpenSettings} aria-label="Settings">
          <Icons.gear size={21} />
        </button>
      </div>

      <div className="screen">
        <div className="stat-grid">
          <div className="stat due">
            <div className="n">{totalDue}</div>
            <div className="l">Due</div>
          </div>
          <div className="stat new">
            <div className="n">{totalUnseen}</div>
            <div className="l">New</div>
          </div>
          <div className="stat learn">
            <div className="n">{learning}</div>
            <div className="l">Learning</div>
          </div>
        </div>

        <div className="spacer" />

        <button
          className="btn primary block"
          style={{ minHeight: 54, fontSize: 16 }}
          onClick={startAll}
          disabled={readyCount === 0}
        >
          {readyCount === 0 ? 'Nothing due right now' : `Start session · ${readyCount} positions`}
        </button>

        {readyCount === 0 && totalItems > 0 && (
          <div className="tiny faint center" style={{ marginTop: 8 }}>
            Next review {nextDueText(allCards, now)}. You can still drill a repertoire below.
          </div>
        )}

        <div className="section-title">Repertoires</div>
        {perRep.map((entry) => (
          <RepertoireRow key={entry.rep.id} entry={entry} onStart={startRep} />
        ))}

        <div className="section-title">Next 7 days</div>
        <div className="card">
          <div className="forecast">
            {week.map((count, i) => (
              <div className="day" key={i}>
                <div
                  className={`bar${i === 0 ? ' today' : ''}`}
                  style={{ height: `${Math.max(3, (count / maxWeek) * 100)}%` }}
                  title={`${count} cards`}
                />
                <div className="lbl">{i === 0 ? 'now' : dayLabel(now + i * DAY)}</div>
              </div>
            ))}
          </div>
        </div>

        <div className="section-title">Coverage</div>
        <div className="card">
          <div className="row between small" style={{ marginBottom: 8 }}>
            <span className="muted">{totalItems} decision points</span>
            <span className="muted">
              {ret === null ? 'No reviews yet' : `${Math.round(ret * 100)}% recall`}
            </span>
          </div>
          <div className="bar-stack">
            <i style={{ width: `${pct(mastery.mature, totalItems)}%`, background: 'var(--good)' }} />
            <i style={{ width: `${pct(mastery.young, totalItems)}%`, background: 'var(--accent)' }} />
            <i style={{ width: `${pct(mastery.learning, totalItems)}%`, background: 'var(--purple)' }} />
          </div>
          <div className="row wrap" style={{ gap: 12, marginTop: 10 }}>
            <Legend colour="var(--good)" label="Mature" value={mastery.mature} />
            <Legend colour="var(--accent)" label="Young" value={mastery.young} />
            <Legend colour="var(--purple)" label="Learning" value={mastery.learning} />
            <Legend colour="var(--surface-3)" label="Unseen" value={totalItems - allCards.length + mastery.unseen} />
          </div>
        </div>
      </div>
    </>
  );
}

function RepertoireRow({
  entry,
  onStart,
}: {
  entry: { rep: Repertoire; items: TrainingItem[]; counts: ReturnType<typeof countDue>; unseen: number; total: number };
  onStart: (entry: never, mode: 'due' | 'cram' | 'new') => void;
}) {
  const { rep, counts, unseen, total } = entry;
  const seen = total - unseen;
  return (
    <div className="card">
      <div className="row between">
        <div className="grow" style={{ minWidth: 0 }}>
          <div className="row" style={{ gap: 7 }}>
            <span className={`chip ${rep.color === 'w' ? 'white-side' : 'black-side'}`}>
              {rep.color === 'w' ? 'White' : 'Black'}
            </span>
            <span className="truncate" style={{ fontWeight: 650 }}>{rep.name}</span>
          </div>
          <div className="tiny faint" style={{ marginTop: 5 }}>
            {total} positions · {seen} seen · {counts.due} due
          </div>
        </div>
      </div>
      <div className="row" style={{ gap: 7, marginTop: 11 }}>
        <button
          className="btn sm grow"
          disabled={counts.due === 0}
          onClick={() => onStart(entry as never, 'due')}
        >
          Review {counts.due > 0 ? counts.due : ''}
        </button>
        <button className="btn sm grow" disabled={unseen === 0} onClick={() => onStart(entry as never, 'new')}>
          Learn new
        </button>
        <button className="btn sm grow" onClick={() => onStart(entry as never, 'cram')}>
          Drill all
        </button>
      </div>
    </div>
  );
}

function Legend({ colour, label, value }: { colour: string; label: string; value: number }) {
  return (
    <span className="row tiny" style={{ gap: 5 }}>
      <i style={{ width: 8, height: 8, borderRadius: 4, background: colour, display: 'block' }} />
      <span className="faint">
        {label} {value}
      </span>
    </span>
  );
}

function pct(n: number, total: number) {
  return total ? (n / total) * 100 : 0;
}

function dayLabel(ts: number) {
  return new Date(ts).toLocaleDateString(undefined, { weekday: 'narrow' });
}

function nextDueText(cards: { due: number }[], now: number) {
  const future = cards.map((c) => c.due).filter((d) => d > now).sort((a, b) => a - b);
  if (!future.length) return 'not scheduled';
  const delta = future[0] - now;
  if (delta < 3600_000) return `in ${Math.max(1, Math.round(delta / 60000))} min`;
  if (delta < DAY) return `in ${Math.round(delta / 3600_000)} h`;
  return `in ${Math.round(delta / DAY)} d`;
}
