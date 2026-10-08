import { useMemo, useState, type ReactNode } from 'react';
import { Icons, Section, Sheet, Toggle } from '../components/ui';
import { SelectionBar } from '../components/Selection';
import { ScoreStrip } from '../components/ScoreBar';
import { nodeById, openingTree } from '../model/openingTree';
import { itemsInRegion, repertoiresIn } from '../model/selection';
import { growthRows } from '../model/growth';
import { streak } from '../model/scoring';
import { NO_HISTORY, pickRound, type AutoRound } from '../store/recommendation';
import { acrossRegions, regionsBySide } from '../model/anyFavorite';
import { roundLabel } from '../model/autopilot';
import { levelById } from '../model/play';
import { referenceIndex } from '../model/referenceIndex';
import { countDue } from '../model/srs';
import { itemsFor, repertoireList, useStore } from '../store/useStore';

export type ModeId = 'drill' | 'survival' | 'growth' | 'play' | 'autopilot';

export interface HomeScreenProps {
  onOpenMode: (mode: ModeId) => void;
  onOpenSettings: () => void;
}

export function HomeScreen({ onOpenMode, onOpenSettings }: HomeScreenProps) {
  const state = useStore();
  const selection = state.settings.selection;
  const tree = openingTree(referenceIndex());
  const favorites = state.settings.favoriteOpenings;
  const regions = useMemo(() => regionsBySide(tree, selection, favorites), [tree, selection, favorites]);
  const reps = repertoiresIn(repertoireList(state), selection.color);
  const [autoSettings, setAutoSettings] = useState(false);
  const survival = state.survival.global;

  /** Drill's waiting work in the selection: cards due now, and positions never seen. */
  const drill = useMemo(() => {
    const items = acrossRegions(regions, reps, (r, node) => itemsInRegion(tree, node, itemsFor(r)), (i) => i.cardId);
    const cards = items.map((i) => state.cards[i.cardId]).filter(Boolean);
    return { total: items.length, due: countDue(cards, Date.now()).due, unseen: items.length - cards.length };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [reps, state.cards, regions]);

  // What is waiting, not what one sitting will cover — a session runs until you
  // stop it.
  const readyCount = drill.due + Math.min(drill.unseen, state.settings.drill.newPerSession);

  /**
   * Replies the database plays that nothing in the repertoire answers, grouped
   * the way Growth's own lobby groups them — so the count on the tile and the
   * row Growth would start on are the same piece of work.
   */
  const growthPrefs = state.settings.growth;
  const growth = useMemo(
    () =>
      acrossRegions(
        regions,
        reps,
        (rep, node) =>
          growthRows([rep], referenceIndex(), {
            minShare: growthPrefs.minShare,
            maxPly: growthPrefs.maxPly,
            starred: state.settings.favoriteOpenings,
            region: { tree, node },
          }),
        (row) => row.id,
      ),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [reps, growthPrefs.minShare, growthPrefs.maxPly, state.settings.favoriteOpenings, regions],
  );
  const gapCount = growth.reduce((sum, row) => sum + row.holes.length + row.ends.length, 0);

  /** What Autopilot would start with, said on its button — or that there is nothing to drill. */
  const first = useMemo(() => pickRound(state, NO_HISTORY).round, [state]);
  const days = streak(state.score.global);

  return (
    <>
      <div className="screen home">
        <StorageWarning />
        <SelectionBar
          trailing={
            <button className="pick gear" aria-label="Settings" onClick={onOpenSettings}>
              <Icons.gear size={20} />
            </button>
          }
        />
        <ScoreStrip />

        <div className="autopilot-wrap">
          <button className="autopilot" onClick={() => onOpenMode(first ? 'autopilot' : 'growth')}>
            <span className="ico">
              <Icons.bolt size={22} />
            </span>
            <span className="grow" style={{ minWidth: 0 }}>
              <span className="kicker">Autopilot</span>
              <span className="name">{first ? roundLabel(first.mode, first.mode === 'survival' ? first.pick.start : undefined) : 'Build'}</span>
              <span className="first truncate">
                {first ? firstUp(first) : 'Nothing to practice yet · open Growth'}
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
          <button className="autopilot-gear" aria-label="Autopilot settings" onClick={() => setAutoSettings(true)}>
            <Icons.gear size={16} />
          </button>
        </div>

        <div className="mode-grid">
          <Tile
            name="Survival"
            icon={<Icons.flame size={20} />}
            tag={survival.runs > 0 ? { text: `best ${survival.best}` } : { text: 'new', tone: 'accent' }}
            onClick={() => onOpenMode('survival')}
          />
          <Tile
            name="Drill"
            icon={<Icons.cards size={20} />}
            tag={
              drill.total === 0
                ? { text: 'empty' }
                : readyCount > 0
                  ? { text: `${readyCount} ready`, tone: 'accent' }
                  : { text: 'clear', tone: 'good' }
            }
            onClick={() => onOpenMode('drill')}
          />
          <Tile
            name="Growth"
            icon={<Icons.sprout size={20} />}
            tag={
              drill.total === 0
                ? { text: 'empty' }
                : gapCount === 0
                  ? { text: 'clear', tone: 'good' }
                  : { text: `${gapCount}`, tone: 'warn' }
            }
            onClick={() => onOpenMode('growth')}
          />
          <Tile
            name="Play"
            icon={<Icons.play size={20} />}
            tag={{ text: levelById(state.settings.play.level).name }}
            onClick={() => onOpenMode('play')}
          />
        </div>
      </div>

      {/* Outside the scrolling screen: on iOS its touch scrolling makes a layer the tab bar would cover. */}
      <AutopilotSettings open={autoSettings} onClose={() => setAutoSettings(false)} />
    </>
  );
}

/* ── the grid ───────────────────────────────────────────────────────────── */

interface Tag {
  text: string;
  tone?: 'accent' | 'good' | 'warn';
}

/**
 * What the first round is about, under its mode's name. A
 * Survival run from move one is a side and nothing more, since it follows
 * whatever is played; one that starts inside an opening is that opening.
 */
function firstUp(round: AutoRound): string {
  const side = (color: 'w' | 'b') => (color === 'w' ? 'White' : 'Black');
  const tree = openingTree(referenceIndex());
  const about = (() => {
    switch (round.mode) {
      case 'survival':
        return round.pick.start === 'inside' ? round.pick.opening.name : `${side(round.pick.color)}, from move one`;
      case 'growth':
        return round.launch.opening.name;
      default: {
        const opening = nodeById(tree, round.openingId);
        return opening.depth === 0 ? side(round.color) : opening.name;
      }
    }
  })();
  return about;
}

/** One mode as a short tile: its icon, its name, and where you stand in it. */
function Tile({ name, icon, tag, onClick }: { name: string; icon: ReactNode; tag: Tag; onClick: () => void }) {
  return (
    <button className="mode-tile" onClick={onClick}>
      <span className="ico">{icon}</span>
      <span className="name truncate">{name}</span>
      <span className={`tag${tag.tone ? ` ${tag.tone}` : ''}`}>{tag.text}</span>
    </button>
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

/**
 * Autopilot's own options: matters of taste only. Everything else about a
 * round is Autopilot's to decide, and no mode's setup reaches it — see
 * `autopilotPrefs.ts`.
 */
function AutopilotSettings({ open, onClose }: { open: boolean; onClose: () => void }) {
  const prefs = useStore((s) => s.settings.autopilot);
  const setModePrefs = useStore((s) => s.setModePrefs);
  return (
    <Sheet open={open} onClose={onClose} title="Autopilot">
      <div className="tiny faint" style={{ marginBottom: 12 }}>
        Autopilot picks every round and how it plays. Your Survival, Drill and Growth setups never change it.
      </div>
      <Section title="Survival feedback" />
      <div className="list">
        <Toggle
          label="Move scores"
          hint="What each move the engine judges cost you, in centipawns, over its square"
          on={prefs.moveScores}
          onToggle={() => setModePrefs('autopilot', { moveScores: !prefs.moveScores })}
        />
        <Toggle
          label="Board glow"
          hint="The board's edge tints green when you are better and red when you are worse"
          on={prefs.boardGlow}
          onToggle={() => setModePrefs('autopilot', { boardGlow: !prefs.boardGlow })}
        />
      </div>
      <Section title="Testing" />
      <div className="list">
        <Toggle
          label="Mode Testing"
          on={prefs.modeTesting}
          onToggle={() => setModePrefs('autopilot', { modeTesting: !prefs.modeTesting })}
        />
      </div>
    </Sheet>
  );
}
