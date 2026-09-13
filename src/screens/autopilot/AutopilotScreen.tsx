import { useEffect, useRef, useState } from 'react';
import { AppBar, Icons } from '../../components/ui';
import { ColorSquare } from '../../components/Selection';
import { GAME_SIZE, type GamePlan, type GameSummary } from '../../model/autopilot';
import { nodeById, openingTree } from '../../model/openingTree';
import { MODE_NAMES, type Recommendation } from '../../model/recommend';
import { referenceIndex } from '../../model/referenceIndex';
import { colorLabel } from '../../model/selection';
import { useStore } from '../../store/useStore';
import { recommendNow } from '../../store/recommendation';
import { DrillScreen } from '../drill/DrillScreen';
import { GrowthScreen } from '../growth/GrowthScreen';
import { OpeningRunScreen } from '../openingRun/OpeningRunScreen';
import { RepairScreen } from '../repair/RepairScreen';

/** One game in the session, as it will be remembered. */
interface Played {
  pick: Recommendation;
  summary: GameSummary;
}

/**
 * Autopilot.
 *
 * The engine picks a game, the mode plays it, and when it is over a bar
 * offers the next one by name: no Home in between, no setup screens, one
 * tap per game. Stop is always the close button in the app bar, and stopping
 * shows what the session added up to.
 */
export function AutopilotScreen({ onExit, onImport }: { onExit: () => void; onImport: () => void }) {
  const [pick, setPick] = useState<Recommendation>(() => recommendNow(useStore.getState()));
  /** Bumped per game so the mode screen mounts fresh. */
  const [round, setRound] = useState(1);
  const [over, setOver] = useState<GameSummary | null>(null);
  const [next, setNext] = useState<Recommendation | null>(null);
  const [played, setPlayed] = useState<Played[]>([]);
  const [tally, setTally] = useState(false);
  const milestones = useRef<string[]>([]);
  const feed = useStore((s) => s.feed);

  /** Milestones crossed during the session, for the tally. */
  useEffect(() => {
    if (feed.milestone?.heldLabel) milestones.current.push(feed.milestone.heldLabel);
  }, [feed]);

  const gameOver = (summary: GameSummary) => {
    setOver(summary);
    setPlayed((list) => [...list, { pick, summary }]);
    // Decided now, while the reveal is still up, so the bar can say what it is.
    setNext(recommendNow(useStore.getState()));
  };

  const advance = () => {
    if (!next) return;
    setPick(next);
    setNext(null);
    setOver(null);
    setRound((n) => n + 1);
  };

  const stop = () => {
    if (played.length === 0) onExit();
    else setTally(true);
  };

  if (tally) return <Tally played={played} milestones={milestones.current} onDone={onExit} />;

  const plan: GamePlan = { color: pick.color, steer: pick.opening.id };
  const props = { auto: true, plan, onGameOver: gameOver, onExit: stop, key: round };

  return (
    <>
      {pick.mode === 'run' && <OpeningRunScreen {...props} />}
      {pick.mode === 'drill' && <DrillScreen {...props} limit={GAME_SIZE.drill} />}
      {pick.mode === 'growth' && <GrowthScreen {...props} />}
      {pick.mode === 'repair' && (
        <RepairScreen {...props} limit={GAME_SIZE.repair} onImport={onImport} />
      )}
      {over && next && <NextBar earned={over.score} perfect={over.perfect} next={next} onNext={advance} />}
    </>
  );
}

/** "Next: Drill · Sicilian: Najdorf", over the end of the last game. */
function NextBar({
  earned,
  perfect,
  next,
  onNext,
}: {
  earned: number;
  perfect: boolean;
  next: Recommendation;
  onNext: () => void;
}) {
  return (
    <div className={`next-bar${perfect ? ' perfect' : ''}`}>
      <div className="earned">
        <span className="pts num">+{earned}</span>
        <span className="lbl">{perfect ? 'Perfect game' : 'this game'}</span>
      </div>
      <button className="go" onClick={onNext}>
        <span className="grow" style={{ minWidth: 0 }}>
          <span className="kicker">Next</span>
          <span className="what truncate">
            {MODE_NAMES[next.mode]} · {next.opening.name}
          </span>
        </span>
        <ColorSquare choice={next.color} size={18} />
        <Icons.next size={20} />
      </button>
    </div>
  );
}

/** What the session added up to. */
function Tally({
  played,
  milestones,
  onDone,
}: {
  played: Played[];
  milestones: string[];
  onDone: () => void;
}) {
  const tree = openingTree(referenceIndex());
  const total = played.reduce((sum, p) => sum + p.summary.score, 0);
  const perfect = played.filter((p) => p.summary.perfect).length;
  const openings = [...new Set(played.map((p) => p.summary.openingId))].map((id) => nodeById(tree, id));
  const byMode = played.reduce<Record<string, number>>((acc, p) => {
    acc[p.summary.mode] = (acc[p.summary.mode] ?? 0) + 1;
    return acc;
  }, {});

  return (
    <>
      <AppBar title="Session" onClose={onDone} />
      <div className="screen no-nav">
        <div className="hero">
          <div className="big">+{total}</div>
          <div className="lbl">{played.length === 1 ? '1 game' : `${played.length} games`}</div>
          <div className="pills">
            {Object.entries(byMode).map(([mode, n]) => (
              <span className="pill" key={mode}>
                <b>{n}</b> {MODE_NAMES[mode as keyof typeof MODE_NAMES]}
              </span>
            ))}
            {perfect > 0 && (
              <span className="pill">
                <i style={{ background: 'var(--good)' }} />
                <b>{perfect}</b> perfect
              </span>
            )}
          </div>
        </div>

        {milestones.length > 0 && (
          <>
            <div className="section">Milestones</div>
            <div className="list">
              {milestones.map((name, i) => (
                <div className="list-row" key={i}>
                  <span className="grow title">{name}</span>
                </div>
              ))}
            </div>
          </>
        )}

        <div className="section">Openings</div>
        <div className="list">
          {openings.map((node) => {
            const games = played.filter((p) => p.summary.openingId === node.id);
            const score = games.reduce((sum, p) => sum + p.summary.score, 0);
            return (
              <div className="list-row" key={node.id}>
                <ColorSquare choice={games[0].summary.color} size={14} />
                <span className="grow">
                  <div className="title truncate">{node.name}</div>
                  <div className="meta">
                    {games.length === 1 ? '1 game' : `${games.length} games`} ·{' '}
                    {games.map((p) => `${MODE_NAMES[p.summary.mode]} as ${colorLabel(p.summary.color)}`).join(', ')}
                  </div>
                </span>
                <span className="val num">+{score}</span>
              </div>
            );
          })}
        </div>

        <div className="spacer" />
        <button className="btn primary block xl" onClick={onDone}>
          Done
        </button>
      </div>
    </>
  );
}
