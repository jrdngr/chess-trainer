import { useMemo, useState } from 'react';
import { BarList, LineChart } from '../components/charts';
import { MilestoneBar } from '../components/ScoreBar';
import { ColorSquare } from '../components/Selection';
import { AppBar, Icons, Section, Segmented } from '../components/ui';
import { sansToMoveText } from '../chess/core';
import {
  ancestorsOf,
  nodeById,
  openingTree,
  orderedChildren,
  type OpeningNode,
} from '../model/openingTree';
import { MODE_NAMES } from '../model/recommend';
import { referenceIndex } from '../model/referenceIndex';
import {
  accuracy,
  ladderMultiplier,
  MILESTONES,
  milestoneOf,
  nodeStats,
  SCORE_MODES,
  streak,
  type NodeStats,
} from '../model/scoring';
import { cumulativeScore, favouriteness, rollingAccuracy, topOpenings } from '../model/stats';
import { useStore } from '../store/useStore';

const WINDOWS = [
  { value: '30', label: '30 days' },
  { value: '90', label: '90 days' },
  { value: '365', label: 'Year' },
];

/**
 * Stats: the whole game, and any opening in it.
 *
 * The tab opens on the global page; every opening row, and every stats
 * button in the opening picker, opens that opening's page over it. Each page
 * is the same shape — score, the milestone ladder, how it climbed, accuracy,
 * games by mode — so the reader learns one page and can read them all.
 */
export function StatsScreen({ target, onConsumedTarget }: { target?: string; onConsumedTarget?: () => void }) {
  const [openingId, setOpeningId] = useState<string | null>(target ?? null);
  const [days, setDays] = useState('30');
  const score = useStore((s) => s.score);
  const tree = openingTree(referenceIndex());

  if (target !== undefined && target !== openingId) {
    setOpeningId(target);
    onConsumedTarget?.();
  }

  if (openingId !== null && openingId !== '') {
    return (
      <OpeningPage
        node={nodeById(tree, openingId)}
        days={Number(days)}
        onDays={setDays}
        onOpen={setOpeningId}
        onBack={() => setOpeningId(null)}
      />
    );
  }

  const stats = score.global;
  const milestone = milestoneOf(stats.score);
  const top = topOpenings(tree, score);
  const daysPlayed = streak(stats);

  return (
    <>
      <AppBar title="Stats" large />
      <div className="screen">
        <div className="hero">
          <div className="big">{score.total}</div>
          <div className="lbl">points</div>
          <div className="pills">
            <span className="pill">
              <b>{rounds(stats)}</b> {rounds(stats) === 1 ? 'round' : 'rounds'}
            </span>
            {daysPlayed > 0 && (
              <span className="pill">
                <i style={{ background: 'var(--warn)' }} />
                <b>{daysPlayed}</b> day streak
              </span>
            )}
            {accuracy(stats) !== null && (
              <span className="pill">
                <b>{Math.round((accuracy(stats) ?? 0) * 100)}%</b> accuracy
              </span>
            )}
          </div>
          <div className="spacer" />
          <Ladder milestone={milestone} score={stats.score} />
        </div>

        <Section title="Window" />
        <Segmented value={days} options={WINDOWS} onChange={setDays} />

        <Charts stats={stats} days={Number(days)} />

        <Section title="By mode" />
        <div className="card">
          <BarList
            rows={SCORE_MODES.map((mode) => ({ label: MODE_NAMES[mode], value: stats.byMode[mode].score }))}
            color="var(--accent)"
          />
        </div>

        <Section title="Openings" aside={top.length ? 'by score' : undefined} />
        {top.length === 0 ? (
          <div className="card small muted">
            Nothing scored yet. Every point a game earns is credited to the opening it was played in,
            and to every opening above it.
          </div>
        ) : (
          <div className="list">
            {top.map(({ node, stats: own, trail }) => (
              <button className="list-row" key={node.id} onClick={() => setOpeningId(node.id)}>
                <span className="grow" style={{ minWidth: 0 }}>
                  <div className="title truncate">{node.name}</div>
                  <div className="meta truncate">{trail || sansToMoveText(node.sans)}</div>
                </span>
                <Tier stats={own} depth={node.depth} />
                <span className="val num">{own.score}</span>
                <Icons.chevron size={18} />
              </button>
            ))}
          </div>
        )}
        <div className="spacer" />
      </div>
    </>
  );
}

function rounds(stats: NodeStats): number {
  return SCORE_MODES.reduce((sum, mode) => sum + stats.byMode[mode].rounds, 0);
}

/** The colour an opening holds, as a dot. */
function Tier({ stats, depth }: { stats: NodeStats; depth: number }) {
  const held = milestoneOf(stats.score, ladderMultiplier(depth)).held;
  if (!held) return null;
  return <span className="side" style={{ background: held.color }} title={held.name} />;
}

/** Where a score stands on its ladder, and the colours already held. */
function Ladder({ milestone, score }: { milestone: ReturnType<typeof milestoneOf>; score: number }) {
  return (
    <div className="milestone-bar">
      <MilestoneBar
        milestone={milestone}
        centre={
          <span className="num">
            {score}/{milestone.ceiling}
          </span>
        }
      />
      <div className="ladder" aria-hidden>
        {MILESTONES.map((tier, i) => (
          <i key={tier.name} className={i < milestone.reached ? 'held' : ''} style={{ background: tier.color }} />
        ))}
      </div>
    </div>
  );
}

function Charts({ stats, days }: { stats: NodeStats; days: number }) {
  const climb = useMemo(() => cumulativeScore(stats, days), [stats, days]);
  const acc = useMemo(() => rollingAccuracy(stats, days), [stats, days]);
  return (
    <>
      <Section title="Score over time" />
      <div className="card">
        <LineChart points={climb} color="var(--accent)" />
      </div>
      <Section title="Accuracy" aside="seven-day average" />
      <div className="card">
        <LineChart points={acc} color="var(--good)" max={1} percent />
      </div>
    </>
  );
}

function OpeningPage({
  node,
  days,
  onDays,
  onOpen,
  onBack,
}: {
  node: OpeningNode;
  days: number;
  onDays: (days: string) => void;
  onOpen: (id: string) => void;
  onBack: () => void;
}) {
  const score = useStore((s) => s.score);
  const starred = useStore((s) => s.settings.favoriteOpenings);
  const selection = useStore((s) => s.settings.selection);
  const setSelection = useStore((s) => s.setSelection);
  const toggleStar = useStore((s) => s.toggleStar);
  const tree = openingTree(referenceIndex());
  const stats = nodeStats(score, node.id);
  const milestone = milestoneOf(stats.score, ladderMultiplier(node.depth));
  const trail = ancestorsOf(tree, node.id).slice(0, -1);
  const fav = useMemo(() => favouriteness(tree, score, node.id), [tree, score, node.id]);
  const children = orderedChildren(node, starred).filter((kid) => nodeStats(score, kid.id).score > 0);
  const isStarred = starred.includes(node.id);
  const selected = selection.opening === node.id;
  const acc = accuracy(stats);

  return (
    <>
      <AppBar
        title={node.name}
        subtitle={trail.length ? trail.map((n) => n.name).join(' › ') : sansToMoveText(node.sans)}
        onBack={onBack}
        actions={
          <button
            className="icon-btn plain"
            aria-label={isStarred ? 'Unstar' : 'Star'}
            onClick={() => toggleStar(node.id)}
          >
            <Icons.star size={20} filled={isStarred} />
          </button>
        }
      />
      <div className="screen">
        <div className="hero">
          <div className="big">{stats.score}</div>
          <div className="lbl">
            points{node.eco ? ` · ${node.eco}` : ''} · {sansToMoveText(node.sans)}
          </div>
          <div className="pills">
            <span className="pill">
              <b>{rounds(stats)}</b> {rounds(stats) === 1 ? 'round' : 'rounds'}
            </span>
            {acc !== null && (
              <span className="pill">
                <b>{Math.round(acc * 100)}%</b> accuracy
              </span>
            )}
            {stats.bestRun > 0 && (
              <span className="pill">
                <b>{stats.bestRun}</b> best run
              </span>
            )}
            {stats.lastAt && (
              <span className="pill">
                last {new Date(stats.lastAt).toLocaleDateString(undefined, { month: 'short', day: 'numeric' })}
              </span>
            )}
          </div>
          <div className="spacer" />
          <Ladder milestone={milestone} score={stats.score} />
        </div>

        <div className="row gap-8 mt-12">
          <button
            className={`btn grow${selected ? ' soft' : ' primary'}`}
            disabled={selected}
            onClick={() => setSelection({ opening: node.id })}
          >
            {selected ? 'Selected' : 'Select this opening'}
          </button>
        </div>

        {fav && (
          <>
            <Section
              title="Favouriteness"
              aside={`your ${ordinal(fav.rank)} favourite${fav.parent && fav.parent.depth > 0 ? ` in ${fav.parent.name}` : ' first move'}`}
            />
            <div className="card">
              <BarList
                rows={fav.siblings.slice(0, 6).map((s) => ({
                  label: s.node.name,
                  value: s.rounds,
                  highlight: s.node.id === node.id,
                }))}
                color="var(--warn)"
                formatValue={(n) => `${n}`}
              />
              <div className="note">Rounds in the last 30 days, among the openings you have played here.</div>
            </div>
          </>
        )}

        <Section title="Window" />
        <Segmented value={String(days)} options={WINDOWS} onChange={onDays} />

        <Charts stats={stats} days={days} />

        <Section title="By mode" />
        <div className="list">
          {SCORE_MODES.map((mode) => {
            const tally = stats.byMode[mode];
            return (
              <div className="list-row kv" key={mode}>
                <span className="k grow">{MODE_NAMES[mode]}</span>
                <span className="meta">
                  {tally.rounds === 1 ? '1 round' : `${tally.rounds} rounds`}
                  {tally.answered ? ` · ${Math.round((tally.correct / tally.answered) * 100)}%` : ''}
                </span>
                <span className="v num" style={{ minWidth: 40, textAlign: 'right' }}>{tally.score}</span>
              </div>
            );
          })}
        </div>

        {children.length > 0 && (
          <>
            <Section title={node.depth === 1 ? 'Openings' : 'Variations'} aside="by score" />
            <div className="list">
              {children
                .sort((a, b) => nodeStats(score, b.id).score - nodeStats(score, a.id).score)
                .map((kid) => (
                  <button className="list-row" key={kid.id} onClick={() => onOpen(kid.id)}>
                    <span className="grow" style={{ minWidth: 0 }}>
                      <div className="title truncate">{kid.name}</div>
                      <div className="meta truncate">{kid.eco ? `${kid.eco} · ` : ''}{sansToMoveText(kid.sans)}</div>
                    </span>
                    <Tier stats={nodeStats(score, kid.id)} depth={kid.depth} />
                    <span className="val num">{nodeStats(score, kid.id).score}</span>
                    <Icons.chevron size={18} />
                  </button>
                ))}
            </div>
          </>
        )}

        {stats.lastAt && (
          <div className="note center mt-12">
            <ColorSquare choice={selection.color} size={10} /> Points here come from every game played through this
            position, in any mode.
          </div>
        )}
        <div className="spacer" />
      </div>
    </>
  );
}

function ordinal(n: number): string {
  const suffix = n % 100 >= 11 && n % 100 <= 13 ? 'th' : ['th', 'st', 'nd', 'rd'][n % 10] ?? 'th';
  return `${n}${suffix}`;
}
