import { useMemo, useState, type ReactNode } from 'react';
import { AppBar, IconButton, Icons, Section, Sheet } from '../components/ui';
import { findGaps } from '../model/gaps';
import { GRADES, gradeLabel, type RunGrade } from '../model/openingRun';
import { referenceIndex } from '../model/referenceIndex';
import { displayName } from '../model/repertoire';
import type { SessionMode, TrainingItem } from '../model/session';
import { countDue, DAY, forecast, masteryBuckets, retention } from '../model/srs';
import { itemsFor, repertoireList, useStore } from '../store/useStore';
import type { Repertoire } from '../model/types';

export type ModeId = 'drill' | 'openingRun' | 'punish' | 'gap';

export interface HomeScreenProps {
  /** Launching one repertoire straight into a session, from the sheet below. */
  onStart: (items: TrainingItem[], mode: SessionMode, title: string) => void;
  onOpenMode: (mode: ModeId) => void;
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

export function HomeScreen({ onStart, onOpenMode, onOpenSettings }: HomeScreenProps) {
  const state = useStore();
  const reps = repertoireList(state);
  const now = Date.now();
  const [pick, setPick] = useState<RepEntry | null>(null);
  const openingRun = state.openingRun;

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
  const mastery = masteryBuckets(allCards);
  const ret = retention(allCards);
  const week = forecast(allCards, 7, now);
  const weekTotal = week.reduce((a, b) => a + b, 0);
  const maxWeek = Math.max(1, ...week);

  const startRep = (entry: RepEntry, mode: Mode) => {
    setPick(null);
    onStart(entry.items, mode, displayName(entry.rep.name));
  };

  // What is waiting, not what one sitting will cover — a session runs until you
  // stop it.
  const readyCount = totalDue + Math.min(totalUnseen, state.settings.drill.newPerSession);
  const unseenTotal = totalItems - allCards.length + mastery.unseen;

  /** Replies the database plays that nothing in the repertoire answers. */
  const gapPrefs = state.settings.gap;
  const gapCount = useMemo(
    () =>
      perRep.reduce(
        (sum, entry) =>
          sum +
          findGaps(entry.rep, referenceIndex(), {
            minShare: gapPrefs.minShare,
            maxPly: gapPrefs.maxPly,
          }).length,
        0,
      ),
    [perRep, gapPrefs.minShare, gapPrefs.maxPly],
  );
  /**
   * Gaps against the breadth of the prep they sit in. A repertoire with two
   * holes in four hundred positions should not read the same as one with two
   * holes in six.
   */
  const coverage = totalItems > 0 ? totalItems / (totalItems + gapCount) : 1;

  const punish = state.punish;

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

        <div className="mode-grid">
          <Tile
            name="Drill"
            tag={
              readyCount > 0
                ? { text: `${readyCount} ready`, tone: 'accent' }
                : { text: 'clear', tone: 'good' }
            }
            art={
              <Gauge
                parts={[
                  { width: pct(mastery.mature, totalItems), color: 'var(--good)' },
                  { width: pct(mastery.young, totalItems), color: '#7dd3fc' },
                  { width: pct(mastery.learning, totalItems), color: 'var(--warn)' },
                ]}
              />
            }
            onClick={() => onOpenMode('drill')}
          />
          <Tile
            name="Opening Run"
            tag={
              openingRun.runs > 0
                ? { text: `best ${openingRun.best}` }
                : { text: 'new', tone: 'accent' }
            }
            art={<GradeBar grades={openingRun.grades} />}
            onClick={() => onOpenMode('openingRun')}
          />
          <Tile
            name="Punish"
            tag={
              punish.seen > 0
                ? { text: `${Math.round((punish.solved / punish.seen) * 100)}%` }
                : { text: 'new', tone: 'accent' }
            }
            art={
              <Gauge
                parts={[
                  {
                    width: punish.seen ? (punish.solved / punish.seen) * 100 : 0,
                    color: 'var(--good)',
                  },
                ]}
              />
            }
            onClick={() => onOpenMode('punish')}
          />
          <Tile
            name="Gap"
            tag={
              gapCount === 0
                ? { text: 'clear', tone: 'good' }
                : { text: `${gapCount}`, tone: 'warn' }
            }
            art={
              <Gauge
                parts={[
                  { width: coverage * 100, color: 'var(--good)' },
                  { width: (1 - coverage) * 100, color: 'var(--warn)' },
                ]}
              />
            }
            onClick={() => onOpenMode('gap')}
          />
        </div>

        <Section title="Repertoires" />
        <div className="list">
          {perRep.map((entry) => (
            <RepertoireRow key={entry.rep.id} entry={entry} onOpen={() => setPick(entry)} />
          ))}
        </div>

        <Section title="This week" aside={`${weekTotal} reviews`} />
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

/* ── the grid ───────────────────────────────────────────────────────────── */

interface Tag {
  text: string;
  tone?: 'accent' | 'good' | 'warn';
}

/**
 * One mode as a square.
 *
 * The name says what it is, the tag says where you stand, and the graphic at
 * the foot says it again in a shape you can read without counting. Tapping it
 * opens that mode's own setup screen.
 */
function Tile({
  name,
  tag,
  art,
  onClick,
}: {
  name: string;
  tag: Tag;
  art: ReactNode;
  onClick: () => void;
}) {
  return (
    <button className="mode-tile" onClick={onClick}>
      <div className="head">
        <span className="name">{name}</span>
        <span className={`tag${tag.tone ? ` ${tag.tone}` : ''}`}>{tag.text}</span>
      </div>
      <div className="fill" />
      <div className="art">{art}</div>
    </button>
  );
}

/** A segmented bar. Parts are percentages of the whole width. */
function Gauge({ parts }: { parts: { width: number; color: string }[] }) {
  return (
    <span className="gauge">
      {parts.map((part, i) => (
        <i key={i} style={{ width: `${Math.max(0, part.width)}%`, background: part.color }} />
      ))}
    </span>
  );
}

/** How runs have ended, in the four colours the grades already use. */
function GradeBar({ grades }: { grades: Record<RunGrade, number> }) {
  const total = GRADES.reduce((sum, grade) => sum + grades[grade], 0);
  if (total === 0) {
    return <Gauge parts={[{ width: 100, color: 'var(--surface-3)' }]} />;
  }
  return (
    <span className="gauge" title={GRADES.map((g) => `${gradeLabel(g)} ${grades[g]}`).join(' · ')}>
      {GRADES.map((grade) => (
        <i
          key={grade}
          style={{ width: `${(grades[grade] / total) * 100}%`, background: GRADE_COLORS[grade] }}
        />
      ))}
    </span>
  );
}

const GRADE_COLORS: Record<RunGrade, string> = {
  green: 'var(--good)',
  yellow: 'var(--warn)',
  red: 'var(--bad)',
  purple: 'var(--accent)',
};

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
