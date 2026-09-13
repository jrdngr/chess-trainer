import { useMemo, useState, type ReactNode } from 'react';
import { AppBar, Icons, Section, Sheet } from '../components/ui';
import { SelectionBar } from '../components/Selection';
import { openingTree } from '../model/openingTree';
import { itemsInRegion, lineInRegion, regionOf, repertoiresIn } from '../model/selection';
import { measureCoverage } from '../model/gameAnalysis';
import { growthRows } from '../model/growth';
import { MODE_NAMES } from '../model/recommend';
import { streak } from '../model/scoring';
import { recommendNow } from '../store/recommendation';
import { levelById } from '../model/play';
import { buildRepairs } from '../model/repair';
import { GRADES, gradeLabel, type RunGrade } from '../model/openingRun';
import { referenceIndex } from '../model/referenceIndex';
import { displayName } from '../model/repertoire';
import type { SessionMode, TrainingItem } from '../model/session';
import { countDue, DAY, forecast, masteryBuckets, retention } from '../model/srs';
import { itemsFor, repertoireList, useStore } from '../store/useStore';
import type { Repertoire } from '../model/types';

export type ModeId = 'drill' | 'openingRun' | 'repair' | 'growth' | 'play' | 'autopilot';

export interface HomeScreenProps {
  /** Launching one side's prep straight into a session, from the sheet below. */
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
  const selection = state.settings.selection;
  const tree = openingTree(referenceIndex());
  const region = regionOf(tree, selection);
  const reps = repertoiresIn(repertoireList(state), selection.color);
  const now = Date.now();
  const [pick, setPick] = useState<RepEntry | null>(null);
  const openingRun = state.openingRun;

  const perRep = useMemo<RepEntry[]>(
    () =>
      reps.map((rep) => {
        const items = itemsInRegion(tree, region, itemsFor(rep));
        const cards = items.map((i) => state.cards[i.cardId]).filter(Boolean);
        const unseen = items.length - cards.length;
        const counts = countDue(cards, now);
        return { rep, items, counts, unseen, total: items.length, mastery: masteryBuckets(cards) };
      }),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [reps, state.cards, region],
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

  /**
   * Replies the database plays that nothing in the repertoire answers, grouped
   * the way Growth's own lobby groups them — so the count on the tile and the
   * opening Next Up would start on are the same piece of work.
   */
  const growthPrefs = state.settings.growth;
  const growth = useMemo(
    () =>
      growthRows(reps, referenceIndex(), {
        minShare: growthPrefs.minShare,
        maxPly: growthPrefs.maxPly,
        starred: state.settings.favoriteOpenings,
        region: { tree, node: region },
      }),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [reps, growthPrefs.minShare, growthPrefs.maxPly, state.settings.favoriteOpenings, region],
  );
  const gapCount = growth.reduce((sum, row) => sum + row.holes.length, 0);
  /**
   * Gaps against the breadth of the prep they sit in. A repertoire with two
   * holes in four hundred positions should not read the same as one with two
   * holes in six.
   */
  const coverage = totalItems > 0 ? totalItems / (totalItems + gapCount) : 1;

  /**
   * What your own games disagree with your prep about, and how much of your
   * real play the prep covered at all.
   */
  const repairPrefs = state.settings.repair;
  const repairs = useMemo(
    () =>
      buildRepairs(state.importedGames, reps, {
        kinds: repairPrefs.kinds,
        minGames: repairPrefs.minGames,
        lossesOnly: repairPrefs.lossesOnly,
        mistakes: state.mistakes,
      }).filter((item) => lineInRegion(tree, region, item.path)),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [state.importedGames, state.mistakes, reps, repairPrefs, region],
  );
  const repairCount = repairs.length;
  const inPrep = useMemo(() => {
    const totals = reps.map((rep) => measureCoverage(state.importedGames, rep));
    const games = totals.reduce((sum, c) => sum + c.games, 0);
    if (!games) return 0;
    return totals.reduce((sum, c) => sum + c.inPrep, 0) / games;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [state.importedGames, reps]);

  /** What Autopilot would start with, said on its button. */
  const first = useMemo(() => recommendNow(state), [state]);
  const days = streak(state.score.global);

  return (
    <>
      <AppBar large />

      <div className="screen">
        <StorageWarning />
        <SelectionBar />

        <button className="autopilot" onClick={() => onOpenMode('autopilot')}>
          <span className="ico">
            <Icons.bolt size={22} />
          </span>
          <span className="grow" style={{ minWidth: 0 }}>
            <span className="kicker">Autopilot</span>
            <span className="name">Play</span>
            <span className="first truncate">
              First up: {MODE_NAMES[first.mode]} · {first.opening.name}
            </span>
          </span>
          {days > 0 && (
            <span className="chip warn streak">
              {days}
              {days === 1 ? ' day' : ' days'}
            </span>
          )}
          <Icons.chevron size={20} />
        </button>

        <div className="mode-grid">
          <Tile
            name="Run"
            tag={
              openingRun.runs > 0
                ? { text: `best ${openingRun.best}` }
                : { text: 'start here', tone: 'accent' }
            }
            art={<GradeBar grades={openingRun.grades} />}
            onClick={() => onOpenMode('openingRun')}
          />
          <Tile
            name="Drill"
            tag={
              totalItems === 0
                ? { text: 'empty' }
                : readyCount > 0
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
            name="Repair"
            tag={
              state.importedGames.length === 0 && state.mistakes.length === 0
                ? { text: 'import', tone: 'accent' }
                : repairCount > 0
                  ? { text: `${repairCount}`, tone: 'warn' }
                  : { text: 'clear', tone: 'good' }
            }
            art={
              <Gauge
                parts={
                  state.importedGames.length === 0
                    ? []
                    : [
                        { width: inPrep * 100, color: 'var(--good)' },
                        { width: (1 - inPrep) * 100, color: 'var(--warn)' },
                      ]
                }
              />
            }
            onClick={() => onOpenMode('repair')}
          />
          <Tile
            name="Growth"
            tag={
              totalItems === 0
                ? { text: 'empty' }
                : gapCount === 0
                  ? { text: 'clear', tone: 'good' }
                  : { text: `${gapCount}`, tone: 'warn' }
            }
            art={
              <Gauge
                parts={
                  totalItems === 0
                    ? []
                    : [
                        { width: coverage * 100, color: 'var(--good)' },
                        { width: (1 - coverage) * 100, color: 'var(--warn)' },
                      ]
                }
              />
            }
            onClick={() => onOpenMode('growth')}
          />
          {/* Play is where the repertoire comes from, so it spans the row rather
              than sitting alone in a corner of it. */}
          <Tile
            wide
            name="Play"
            tag={{ text: levelById(state.settings.play.level).name }}
            onClick={() => onOpenMode('play')}
          />
        </div>

        <Section title="Repertoire" />
        {perRep.length === 0 ? (
          <div className="card small muted">
            Nothing prepared yet. Play a game and save the opening, or survive a line in Run —
            both write into your repertoire, and everything else here works from it.
          </div>
        ) : (
          <div className="list">
            {perRep.map((entry) => (
              <RepertoireRow key={entry.rep.id} entry={entry} onOpen={() => setPick(entry)} />
            ))}
          </div>
        )}

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

        <button className="btn block mt-16" onClick={onOpenSettings}>
          Settings
        </button>
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
  wide,
  onClick,
}: {
  name: string;
  tag: Tag;
  /** The gauge or bar under the name. Play has no queue to draw. */
  art?: ReactNode;
  /** Spans both columns, for a mode that is an action rather than a queue. */
  wide?: boolean;
  onClick: () => void;
}) {
  return (
    <button className={`mode-tile${wide ? ' wide' : ''}`} onClick={onClick}>
      <div className="head">
        <span className="name">{name}</span>
        <span className={`tag${tag.tone ? ` ${tag.tone}` : ''}`}>{tag.text}</span>
      </div>
      <div className="fill" />
      {art && <div className="art">{art}</div>}
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
