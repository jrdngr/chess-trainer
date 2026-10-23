import { useMemo, useState, type ReactNode } from 'react';
import { Icons, Section, Sheet, Toggle } from '../components/ui';
import { SelectionBar, selectionTrail } from '../components/Selection';
import { PlateBoard, PrepSegments, SideSquare } from '../components/OpeningPlate';
import { ScoreStrip } from '../components/ScoreBar';
import { FavoritesLadder, MilestonesCard, SurvivalRuns } from '../components/HomeWidgets';
import { NO_HISTORY, pickRound } from '../store/recommendation';
import { roundSpan } from '../model/autopilot';
import { repertoireList, useStore } from '../store/useStore';

export type ModeId = 'drill' | 'survival' | 'growth' | 'play' | 'autopilot';

export interface HomeScreenProps {
  onOpenMode: (mode: ModeId) => void;
  onOpenSettings: () => void;
}

export function HomeScreen({ onOpenMode, onOpenSettings }: HomeScreenProps) {
  const state = useStore();
  const [autoSettings, setAutoSettings] = useState(false);

  /** What Autopilot would start with, said on its button — or that there is nothing to drill. */
  const first = useMemo(() => pickRound(state, NO_HISTORY).round, [state]);
  /** How far into your prep it would start, for the segments along the button's bottom edge. */
  const span = useMemo(() => {
    if (!first) return null;
    const rep = repertoireList(state).find((r) => r.color === first.pick.color) ?? null;
    return roundSpan(rep, first.pick, first.at);
  }, [state, first]);

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
          {first ? (
            <button className="autopilot plate" onClick={() => onOpenMode('autopilot')}>
              <PlateBoard sans={first.pick.opening.sans} color={first.pick.color} size={176} />
              <span className="plate-tag">
                <Icons.bolt size={11} />
                Autopilot
              </span>
              <SideSquare color={first.pick.color} />
              <span className="name truncate">{selectionTrail(first.pick.opening.id).at(-1)}</span>
              <PrepSegments span={span} className="edge" />
            </button>
          ) : (
            <button className="autopilot" onClick={() => onOpenMode('growth')}>
              <span className="ico">
                <Icons.bolt size={22} />
              </span>
              <span className="grow" style={{ minWidth: 0 }}>
                <span className="kicker">Autopilot</span>
                <span className="name">Build</span>
                <span className="first truncate">Nothing to practice yet · open Growth</span>
              </span>
              <Icons.chevron size={20} />
            </button>
          )}
          <button className="autopilot-gear" aria-label="Autopilot settings" onClick={() => setAutoSettings(true)}>
            <Icons.gear size={16} />
          </button>
        </div>

        <div className="mode-grid">
          <Tile
            name="Survival"
            icon={<Icons.flame size={20} />}
            onClick={() => onOpenMode('survival')}
          />
          <Tile
            name="Drill"
            icon={<Icons.cards size={20} />}
            onClick={() => onOpenMode('drill')}
          />
          <Tile
            name="Growth"
            icon={<Icons.sprout size={20} />}
            onClick={() => onOpenMode('growth')}
          />
          <Tile
            name="Play"
            icon={<Icons.play size={20} />}
            onClick={() => onOpenMode('play')}
          />
        </div>

        <div className="home-cards">
          <SurvivalRuns />
          <FavoritesLadder />
          <MilestonesCard />
        </div>
      </div>

      {/* Outside the scrolling screen: on iOS its touch scrolling makes a layer the tab bar would cover. */}
      <AutopilotSettings open={autoSettings} onClose={() => setAutoSettings(false)} />
    </>
  );
}

/* ── the grid ───────────────────────────────────────────────────────────── */


/** One mode as a short tile: its icon and its name. */
function Tile({ name, icon, onClick }: { name: string; icon: ReactNode; onClick: () => void }) {
  return (
    <button className="mode-tile" onClick={onClick}>
      <span className="ico">{icon}</span>
      <span className="name truncate">{name}</span>
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
