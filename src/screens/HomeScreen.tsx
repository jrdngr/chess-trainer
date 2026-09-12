import { useMemo, useState } from 'react';
import { AppBar, IconButton, Icons, Section, Sheet } from '../components/ui';
import { lineRecords } from '../model/openingRun';
import { displayName } from '../model/repertoire';
import type { SessionMode, TrainingItem } from '../model/session';
import { countDue, DAY, forecast, masteryBuckets, retention } from '../model/srs';
import { itemsFor, repertoireList, useStore } from '../store/useStore';
import type { Repertoire } from '../model/types';

export interface HomeScreenProps {
  onStart: (items: TrainingItem[], mode: SessionMode, title: string) => void;
  onStartOpeningRun: () => void;
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

export function HomeScreen({ onStart, onStartOpeningRun, onOpenSettings }: HomeScreenProps) {
  const state = useStore();
  const reps = repertoireList(state);
  const now = Date.now();
  const [pick, setPick] = useState<RepEntry | null>(null);
  const openingRun = state.openingRun;
  /** The opening you have gone deepest in — the one stat worth naming. */
  const strongest = useMemo(() => {
    const best = lineRecords(openingRun)[0];
    return best && best.best > 0 ? best : null;
  }, [openingRun]);

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

  const startAll = () => {
    onStart(perRep.flatMap((r) => r.items), 'due', 'Review');
  };

  const startRep = (entry: RepEntry, mode: Mode) => {
    setPick(null);
    onStart(entry.items, mode, displayName(entry.rep.name));
  };

  // What is waiting, not what one sitting will cover — a session runs until you
  // stop it.
  const readyCount = totalDue + Math.min(totalUnseen, state.settings.newCardsPerSession);
  const unseenTotal = totalItems - allCards.length + mastery.unseen;

  return (
    <>
      <AppBar
        large
        actions={
          <IconButton label="Settings" onClick={onOpenSettings}>
            <Icons.gear size={20} />
          </IconButton>
        }
      />

      <div className="screen">
        <StorageWarning />

        <Section title="Drill" />
        <div className="hero">
          <div className="big">{readyCount}</div>
          <div className="lbl">
            {readyCount === 0
              ? totalItems > 0
                ? `All clear · next ${nextDueText(allCards, now)}`
                : 'Nothing to drill yet'
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

        <Section title="Opening Run" />
        <div className="hero">
          <div className="big">{openingRun.runs === 0 ? '\u2014' : openingRun.best}</div>
          <div className="lbl">
            {openingRun.runs === 0
              ? 'One secret line. One mistake.'
              : `${openingRun.best === 1 ? 'move' : 'moves'} deep at your best`}
          </div>
          {openingRun.runs > 0 && (
            <div className="pills">
              <span className="pill">
                <b>{openingRun.runs}</b> {openingRun.runs === 1 ? 'run' : 'runs'}
              </span>
              <span className="pill">
                <b>{openingRun.survivals}</b> completed
              </span>
              <span className="pill">
                last <b>{openingRun.lastDepth}</b>
              </span>
            </div>
          )}
          {strongest && (
            <div className="faint tiny" style={{ marginTop: 12 }}>
              Deepest in the {strongest.label} — {strongest.best}{' '}
              {strongest.best === 1 ? 'move' : 'moves'}
            </div>
          )}
          <button
            className="btn primary block xl"
            style={{ marginTop: 18 }}
            onClick={onStartOpeningRun}
          >
            {openingRun.runs === 0 ? 'Start a run' : 'New run'}
          </button>
        </div>

        <Section title="Repertoires" />
        <div className="list">
          {perRep.map((entry) => (
            <RepertoireRow key={entry.rep.id} entry={entry} onOpen={() => setPick(entry)} />
          ))}
        </div>

        <Section title="This week" aside={`${week.reduce((a, b) => a + b, 0)} reviews`} />
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

        <Section
          title="Mastery"
          aside={ret === null ? `${totalItems} positions` : `${Math.round(ret * 100)}% recall`}
        />
        <div className="card">
          <div className="bar-stack">
            <i style={{ width: `${pct(mastery.mature, totalItems)}%`, background: 'var(--good)' }} />
            <i style={{ width: `${pct(mastery.young, totalItems)}%`, background: '#7dd3fc' }} />
            <i style={{ width: `${pct(mastery.learning, totalItems)}%`, background: 'var(--warn)' }} />
            <i style={{ width: `${pct(unseenTotal, totalItems)}%`, background: 'var(--surface-3)' }} />
          </div>
          <div className="pills mt-12">
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
