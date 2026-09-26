import { useMemo, useState } from 'react';
import { BarList, LineChart } from '../components/charts';
import { RankBar, ratingText } from '../components/ScoreBar';
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
  ACTIVITY_MODES,
  nodeStats,
  rankOf,
  streak,
  TIERS,
  UNRATED,
  type NodeStats,
} from '../model/scoring';
import { dailyRounds, favouriteness, ratingOverTime, rollingAccuracy, starredOpenings } from '../model/stats';
import { useStore } from '../store/useStore';

const WINDOWS = [
  { value: '30', label: '30 days' },
  { value: '90', label: '90 days' },
  { value: '365', label: 'Year' },
];

/**
 * Stats: your starred openings, and any opening in the book.
 *
 * There is no global score to open on any more — a rating belongs to one
 * opening — so the tab opens on the openings you have starred, each with the
 * piece it holds, and the activity that is true of the whole game underneath.
 * Every row, and every stats button in the opening picker, opens that
 * opening's own page over it.
 */
export function StatsScreen({ target, onConsumedTarget }: { target?: string; onConsumedTarget?: () => void }) {
  const [openingId, setOpeningId] = useState<string | null>(target ?? null);
  const [days, setDays] = useState('30');
  const tree = openingTree(referenceIndex());

  if (target !== undefined && target !== openingId) {
    setOpeningId(target);
    onConsumedTarget?.();
  }

  // Each page is its own component, so switching between them is a remount
  // rather than one component rendering a different set of hooks.
  return openingId !== null && openingId !== '' ? (
    <OpeningPage
      node={nodeById(tree, openingId)}
      days={Number(days)}
      onDays={setDays}
      onOpen={setOpeningId}
      onBack={() => setOpeningId(null)}
    />
  ) : (
    <YourOpenings days={days} onDays={setDays} onOpen={setOpeningId} />
  );
}

/**
 * The tab's own page: the openings you have starred, each with the piece it
 * holds, and under them the activity that is true of the whole game.
 */
function YourOpenings({
  days,
  onDays,
  onOpen,
}: {
  days: string;
  onDays: (days: string) => void;
  onOpen: (id: string) => void;
}) {
  const score = useStore((s) => s.score);
  const starred = useStore((s) => s.settings.favoriteOpenings);
  const tree = openingTree(referenceIndex());
  const stats = score.global;
  const mine = useMemo(() => starredOpenings(tree, score, starred), [tree, score, starred]);
  const daily = useMemo(() => dailyRounds(stats, Number(days)), [stats, days]);
  const daysPlayed = streak(stats);
  const acc = accuracy(stats);

  return (
    <>
      <AppBar title="Stats" large />
      <div className="screen">
        <Section title="Your openings" aside={mine.length ? 'by rating' : undefined} />
        {mine.length === 0 ? (
          <div className="card small muted">
            Nothing starred yet. Star an opening in the picker and it gets a rating of its own,
            which Autopilot moves up when you find your prep and down when you miss it.
          </div>
        ) : (
          <div className="list">
            {mine.map(({ node, stats: own, trail }) => {
              const rank = rankOf(own.rating);
              return (
                <button className="list-row" key={node.id} onClick={() => onOpen(node.id)}>
                  <span className="side" style={{ background: (rank.held ?? UNRATED).color }} />
                  <span className="grow" style={{ minWidth: 0 }}>
                    <div className="title truncate">{node.name}</div>
                    <div className="meta truncate">
                      {rank.heldLabel}
                      {trail ? ` \u00b7 ${trail}` : ''}
                    </div>
                  </span>
                  <span className="val num">{own.rated === 0 ? '\u2014' : ratingText(own.rating)}</span>
                  <Icons.chevron size={18} />
                </button>
              );
            })}
          </div>
        )}

        <Section title="Activity" />
        <div className="hero">
          <div className="big">{rounds(stats)}</div>
          <div className="lbl">{rounds(stats) === 1 ? 'round' : 'rounds'}</div>
          <div className="pills">
            {daysPlayed > 0 && (
              <span className="pill">
                <i style={{ background: 'var(--warn)' }} />
                <b>{daysPlayed}</b> day streak
              </span>
            )}
            {acc !== null && (
              <span className="pill">
                <b>{Math.round(acc * 100)}%</b> accuracy
              </span>
            )}
            <span className="pill">
              <b>{stats.answered}</b> answered
            </span>
          </div>
        </div>

        <Section title="Window" />
        <Segmented value={days} options={WINDOWS} onChange={onDays} />

        <Section title="Rounds a day" />
        <div className="card">
          <LineChart points={daily} color="var(--accent)" />
        </div>
        <Accuracy stats={stats} days={Number(days)} />

        <Section title="By mode" aside="rounds" />
        <div className="card">
          <BarList
            rows={ACTIVITY_MODES.map((mode) => ({ label: MODE_NAMES[mode], value: stats.byMode[mode].rounds }))}
            color="var(--accent)"
          />
        </div>
        <div className="note center mt-12">
          Only Autopilot moves a rating. Survival, Drill, Growth and Repair are counted here and
          nowhere else.
        </div>
        <div className="spacer" />
      </div>
    </>
  );
}

function rounds(stats: NodeStats): number {
  return ACTIVITY_MODES.reduce((sum, mode) => sum + stats.byMode[mode].rounds, 0);
}

/** The piece an opening holds, as a dot. Nothing at all while it is unrated. */
function Tier({ stats }: { stats: NodeStats }) {
  const held = rankOf(stats.rating).held;
  if (!held) return null;
  return <span className="side" style={{ background: held.color }} title={held.name} />;
}

/** Where a rating stands on its ladder, and the pieces already held. */
function Ladder({ stats }: { stats: NodeStats }) {
  const rank = rankOf(stats.rating);
  return (
    <div className="milestone-bar">
      <RankBar
        rank={rank}
        centre={
          <span className="num">{stats.rated === 0 ? 'Unrated' : `${ratingText(stats.rating)}/${rank.ceiling}`}</span>
        }
      />
      <div className="ladder" aria-hidden>
        {TIERS.map((tier, i) => (
          <i key={tier.name} className={i < rank.reached ? 'held' : ''} style={{ background: tier.color }} />
        ))}
      </div>
    </div>
  );
}

function Accuracy({ stats, days }: { stats: NodeStats; days: number }) {
  const acc = useMemo(() => rollingAccuracy(stats, days), [stats, days]);
  return (
    <>
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
  const rank = rankOf(stats.rating);
  const trail = ancestorsOf(tree, node.id).slice(0, -1);
  const fav = useMemo(() => favouriteness(tree, score, node.id), [tree, score, node.id]);
  const children = orderedChildren(node, starred).filter((kid) => nodeStats(score, kid.id).answered > 0);
  const isStarred = starred.includes(node.id);
  const selected = selection.opening === node.id;
  const acc = accuracy(stats);
  const climb = useMemo(() => ratingOverTime(stats, days), [stats, days]);

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
          <div className="big">{stats.rated === 0 ? '—' : ratingText(stats.rating)}</div>
          <div className="lbl">
            {rank.heldLabel}
            {node.eco ? ` · ${node.eco}` : ''} · {sansToMoveText(node.sans)}
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
          <Ladder stats={stats} />
        </div>

        {!isStarred && (
          <div className="card small muted">
            {stats.rated > 0
              ? 'Not starred, so this rating is resting. Star it again and it picks up where it left off.'
              : 'Not starred, so it has no rating. Star it and Autopilot will start one.'}
          </div>
        )}

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
              title="Favoriteness"
              aside={`your ${ordinal(fav.rank)} favorite${fav.parent && fav.parent.depth > 0 ? ` in ${fav.parent.name}` : ' first move'}`}
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

        {climb.length > 0 && (
          <>
            <Section title="Rating over time" />
            <div className="card">
              <LineChart points={climb} color="var(--accent)" />
            </div>
          </>
        )}
        <Accuracy stats={stats} days={days} />

        <Section title="By mode" aside="rounds" />
        <div className="list">
          {ACTIVITY_MODES.map((mode) => {
            const tally = stats.byMode[mode];
            return (
              <div className="list-row kv" key={mode}>
                <span className="k grow">{MODE_NAMES[mode]}</span>
                <span className="meta">
                  {tally.rounds === 1 ? '1 round' : `${tally.rounds} rounds`}
                  {tally.answered ? ` · ${Math.round((tally.correct / tally.answered) * 100)}%` : ''}
                </span>
              </div>
            );
          })}
        </div>

        {children.length > 0 && (
          <>
            <Section title={node.depth === 1 ? 'Openings' : 'Variations'} aside="by rounds" />
            <div className="list">
              {children
                .sort((a, b) => rounds(nodeStats(score, b.id)) - rounds(nodeStats(score, a.id)))
                .map((kid) => (
                  <button className="list-row" key={kid.id} onClick={() => onOpen(kid.id)}>
                    <span className="grow" style={{ minWidth: 0 }}>
                      <div className="title truncate">{kid.name}</div>
                      <div className="meta truncate">{kid.eco ? `${kid.eco} · ` : ''}{sansToMoveText(kid.sans)}</div>
                    </span>
                    <Tier stats={nodeStats(score, kid.id)} />
                    <span className="val num">{rounds(nodeStats(score, kid.id))}</span>
                    <Icons.chevron size={18} />
                  </button>
                ))}
            </div>
          </>
        )}

        {stats.lastAt && (
          <div className="note center mt-12">
            <ColorSquare choice={selection.color} size={10} /> Rounds and accuracy here count every game played
            through this position, in any mode. Only Autopilot moves the rating.
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
