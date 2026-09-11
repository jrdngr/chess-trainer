import { useMemo, useState } from 'react';
import { IconButton, Icons, Sheet } from '../components/ui';
import { displayName } from '../model/repertoire';
import { buildSession, type TrainingItem } from '../model/session';
import { countDue, DAY, forecast, masteryBuckets, retention } from '../model/srs';
import { itemsFor, repertoireList, useStore } from '../store/useStore';
import type { Repertoire } from '../model/types';

export interface TrainHomeProps {
  onStart: (queue: TrainingItem[], title: string) => void;
  onOpenSettings: () => void;
}

type Mode = 'due' | 'cram' | 'new';

interface RepEntry {
  rep: Repertoire;
  items: TrainingItem[];
  counts: ReturnType<typeof countDue>;
  unseen: number;
  total: number;
  mastery: ReturnType<typeof masteryBuckets>;
}

export function TrainHome({ onStart, onOpenSettings }: TrainHomeProps) {
  const state = useStore();
  const reps = repertoireList(state);
  const now = Date.now();
  const [pick, setPick] = useState<RepEntry | null>(null);

  const perRep = useMemo<RepEntry[]>(
    () =>
      reps.map((rep) => {
        const items = itemsFor(rep);
        const cards = items.map((i) => state.cards[i.cardId]).filter(Boolean);
        const unseen = items.length - cards.length;
        const counts = countDue(cards, now);
        return { rep, items, counts, unseen, total: items.length, mastery: masteryBuckets(cards) };
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

  const sessionOpts = (mode: Mode) => ({
    mode,
    now,
    maxItems: state.settings.maxSessionLength,
    maxNew: state.settings.newCardsPerSession,
    seed: Math.floor(now / 60000),
  });

  const startAll = () => {
    const items = perRep.flatMap((r) => r.items);
    onStart(buildSession(items, state.cards, sessionOpts('due')), 'Review');
  };

  const startRep = (entry: RepEntry, mode: Mode) => {
    setPick(null);
    onStart(buildSession(entry.items, state.cards, sessionOpts(mode)), displayName(entry.rep.name));
  };

  const readyCount = Math.min(
    state.settings.maxSessionLength,
    totalDue + Math.min(totalUnseen, state.settings.newCardsPerSession),
  );
  const unseenTotal = totalItems - allCards.length + mastery.unseen;

  return (
    <>
      <div className="appbar">
        <h1>Train</h1>
        <IconButton label="Settings" onClick={onOpenSettings}>
          <Icons.gear size={20} />
        </IconButton>
      </div>

      <div className="screen">
        <StorageWarning />

        <div className="hero">
          <div className="big">{readyCount}</div>
          <div className="lbl">
            {readyCount === 0
              ? totalItems > 0
                ? `All clear · next ${nextDueText(allCards, now)}`
                : 'Nothing to train yet'
              : readyCount === 1
                ? 'position ready'
                : 'positions ready'}
          </div>
          <div className="pills">
            <span className="pill"><i style={{ background: 'var(--accent)' }} /><b>{totalDue}</b> due</span>
            <span className="pill"><i style={{ background: 'var(--text-3)' }} /><b>{totalUnseen}</b> new</span>
            <span className="pill"><i style={{ background: 'var(--warn)' }} /><b>{learning}</b> learning</span>
          </div>
          <button
            className="btn primary block xl"
            style={{ marginTop: 18 }}
            onClick={startAll}
            disabled={readyCount === 0}
          >
            Start session
          </button>
        </div>

        <div className="section">Repertoires</div>
        <div className="list">
          {perRep.map((entry) => (
            <RepertoireRow key={entry.rep.id} entry={entry} onOpen={() => setPick(entry)} />
          ))}
        </div>

        <div className="section">
          <span>This week</span>
          <span className="faint">{week.reduce((a, b) => a + b, 0)} reviews</span>
        </div>
        <div className="card">
          <div className="forecast">
            {week.map((count, i) => (
              <div className="day" key={i}>
                <div
                  className={`bar${i === 0 ? ' today' : ''}`}
                  style={{ height: `${Math.max(4, (count / maxWeek) * 100)}%` }}
                  title={`${count}`}
                />
                <div className="lbl">{i === 0 ? 'Now' : dayLabel(now + i * DAY)}</div>
              </div>
            ))}
          </div>
        </div>

        <div className="section">
          <span>Mastery</span>
          <span className="faint">{ret === null ? `${totalItems} positions` : `${Math.round(ret * 100)}% recall`}</span>
        </div>
        <div className="card">
          <div className="bar-stack">
            <i style={{ width: `${pct(mastery.mature, totalItems)}%`, background: 'var(--good)' }} />
            <i style={{ width: `${pct(mastery.young, totalItems)}%`, background: '#7dd3fc' }} />
            <i style={{ width: `${pct(mastery.learning, totalItems)}%`, background: 'var(--warn)' }} />
            <i style={{ width: `${pct(unseenTotal, totalItems)}%`, background: 'var(--surface-3)' }} />
          </div>
          <div className="row wrap" style={{ gap: 8, marginTop: 12 }}>
            <span className="pill"><i style={{ background: 'var(--good)' }} /><b>{mastery.mature}</b> mature</span>
            <span className="pill"><i style={{ background: '#7dd3fc' }} /><b>{mastery.young}</b> young</span>
            <span className="pill"><i style={{ background: 'var(--warn)' }} /><b>{mastery.learning}</b> learning</span>
            <span className="pill"><i style={{ background: 'var(--surface-3)' }} /><b>{unseenTotal}</b> unseen</span>
          </div>
        </div>
      </div>

      <Sheet open={!!pick} onClose={() => setPick(null)} title={pick ? displayName(pick.rep.name) : ''}>
        {pick && (
          <div className="list">
            <button className="list-row" disabled={pick.counts.due === 0} onClick={() => startRep(pick, 'due')}>
              <span className="grow">
                <div className="title">Review</div>
                <div className="meta">{pick.counts.due === 0 ? 'Nothing due' : `${pick.counts.due} due`}</div>
              </span>
              <Icons.chevron size={18} />
            </button>
            <button className="list-row" disabled={pick.unseen === 0} onClick={() => startRep(pick, 'new')}>
              <span className="grow">
                <div className="title">Learn</div>
                <div className="meta">{pick.unseen === 0 ? 'All seen' : `${pick.unseen} new`}</div>
              </span>
              <Icons.chevron size={18} />
            </button>
            <button className="list-row" onClick={() => startRep(pick, 'cram')}>
              <span className="grow">
                <div className="title">Drill</div>
                <div className="meta">All {pick.total} positions, ignoring the schedule</div>
              </span>
              <Icons.chevron size={18} />
            </button>
          </div>
        )}
      </Sheet>
    </>
  );
}

/** When nothing can persist, say so instead of quietly forgetting. */
function StorageWarning() {
  const storage = useStore((s) => s.storage);
  const cloud = useStore((s) => s.cloud);
  const cloudSync = useStore((s) => s.settings.cloudSync);
  const setSettings = useStore((s) => s.setSettings);
  const syncNow = useStore((s) => s.syncNow);

  const cloudWorking = cloudSync && (cloud.kind === 'synced' || cloud.kind === 'syncing');
  if (storage.any || cloudWorking) return null;

  const canTryCloud = cloud.kind !== 'unavailable';
  return (
    <div className="banner" style={{ marginBottom: 12 }}>
      <span className="ico"><Icons.warn size={20} /></span>
      <div className="grow">
        Progress isn't being saved
        <div className="sub">Storage is blocked in this browser.</div>
      </div>
      {canTryCloud && (
        <button
          className="btn sm"
          onClick={async () => {
            setSettings({ cloudSync: true });
            await syncNow();
          }}
        >
          Sync
        </button>
      )}
    </div>
  );
}

function RepertoireRow({ entry, onOpen }: { entry: RepEntry; onOpen: () => void }) {
  const { rep, counts, total, mastery } = entry;
  return (
    <button className="list-row" onClick={onOpen}>
      <span className={`side ${rep.color}`} />
      <span className="grow">
        <div className="title truncate">{displayName(rep.name)}</div>
        <div className="mini-bar" style={{ marginTop: 6 }}>
          <i style={{ width: `${pct(mastery.mature, total)}%`, background: 'var(--good)' }} />
          <i style={{ width: `${pct(mastery.young, total)}%`, background: '#7dd3fc' }} />
          <i style={{ width: `${pct(mastery.learning, total)}%`, background: 'var(--warn)' }} />
        </div>
      </span>
      {counts.due > 0 ? (
        <span className="chip accent">{counts.due} due</span>
      ) : (
        <span className="val">{total}</span>
      )}
      <Icons.chevron size={18} />
    </button>
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
  if (!future.length) return 'later';
  const delta = future[0] - now;
  if (delta < 3600_000) return `in ${Math.max(1, Math.round(delta / 60000))} min`;
  if (delta < DAY) return `in ${Math.round(delta / 3600_000)} h`;
  return `in ${Math.round(delta / DAY)} d`;
}
