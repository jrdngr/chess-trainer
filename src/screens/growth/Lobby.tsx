import { useMemo } from 'react';
import { AppBar, Icons, Section, Segmented } from '../../components/ui';
import { growthRows, type GrowthRow } from '../../model/growth';
import { GROWTH_DEPTHS, SHARE_STEPS, shareLabel } from '../../model/modes';
import { referenceIndex } from '../../model/referenceIndex';
import { repertoireList, useStore } from '../../store/useStore';

/**
 * Where the work is, shallowest first.
 *
 * Depth is the urgency signal: the shallower a hole, the more games fall into
 * it. An unanswered 1...e5 costs you a quarter of your games as White; one at
 * move nine costs almost none.
 */
export function Lobby({
  onStart,
  onNoWork,
  onExit,
}: {
  onStart: (row: GrowthRow) => void;
  onNoWork: () => void;
  onExit: () => void;
}) {
  const state = useStore();
  const setModePrefs = useStore((s) => s.setModePrefs);
  const prefs = state.settings.growth;
  const reps = repertoireList(state);
  const index = referenceIndex();

  /** A side that exists but has no moves in it yet cannot be grown. */
  const hasMoves = reps.some((rep) => Object.keys(rep.nodes).length > 0);

  const rows = useMemo(
    () => growthRows(reps, index, { minShare: prefs.minShare, maxPly: prefs.maxPly }),
    [reps, index, prefs.minShare, prefs.maxPly],
  );

  if (reps.length === 0) {
    return (
      <>
        <AppBar title="Growth" onClose={onExit} />
        <div className="screen no-nav">
          <div className="empty">
            <div className="t">Nothing to grow yet</div>
            <div className="h">
              Growth extends prep you already have. Survive a line in Run, or save the opening
              from a game in Play, and it will have something to work on.
            </div>
          </div>
          <button className="btn primary block xl" onClick={onNoWork}>
            Back to the modes
          </button>
        </div>
      </>
    );
  }

  return (
    <>
      <AppBar
        title="Growth"
        subtitle={rows.length === 1 ? '1 opening to extend' : `${rows.length} openings to extend`}
        onClose={onExit}
      />

      <div className="screen no-nav">
        {rows.length === 0 ? (
          <>
            <div className="empty">
              <div className="t">Nothing to extend</div>
              <div className="h">
                {hasMoves
                  ? `Your repertoire meets every reply played in ${prefs.minShare}% of games or more, down to ${Math.ceil(prefs.maxPly / 2)} moves. Lower the threshold below to keep going.`
                  : 'Growth answers replies, and your first move as White is not a reply to anything. Play a game or survive a line first, then come back to extend it.'}
              </div>
            </div>
            {!hasMoves && (
              <button className="btn primary block xl" onClick={onNoWork}>
                Back to the modes
              </button>
            )}
          </>
        ) : (
          <>
            <Section title="Pick an opening" aside="shallowest first" />
            <div className="list">
              {rows.map((row) => (
                <button key={row.id} className="list-row" onClick={() => onStart(row)}>
                  <span className={`side ${row.color}`} />
                  <span className="grow" style={{ minWidth: 0 }}>
                    <div className="title truncate">{row.name}</div>
                    <div className="meta">
                      {depthLabel(row.depth)} ·{' '}
                      {row.holes.length === 1 ? '1 reply' : `${row.holes.length} replies`}{' '}
                      unanswered · up to {row.topShare}% of games
                    </div>
                  </span>
                  <Icons.chevron size={18} />
                </button>
              ))}
            </div>
          </>
        )}

        <Section title="Worth answering" />
        <Segmented
          value={String(prefs.minShare)}
          options={SHARE_STEPS.map((share) => ({
            value: String(share),
            label: shareLabel(share),
          }))}
          onChange={(share) => setModePrefs('growth', { minShare: Number(share) })}
        />

        <Section title="How deep" />
        <Segmented
          value={String(prefs.maxPly)}
          options={GROWTH_DEPTHS.map((ply) => ({
            value: String(ply),
            label: `${Math.ceil(ply / 2)} moves`,
          }))}
          onChange={(ply) => setModePrefs('growth', { maxPly: Number(ply) })}
        />

        {reps.length > 0 && (
          <>
            <Section title="What you have" />
            <div className="list">
              {reps.map((rep) => (
                <div className="list-row kv" key={rep.id}>
                  <span className={`side ${rep.color}`} />
                  <span className="k grow">{rep.color === 'w' ? 'As White' : 'As Black'}</span>
                  <span className="v num">{Object.keys(rep.nodes).length}</span>
                </div>
              ))}
            </div>
          </>
        )}
      </div>
    </>
  );
}

function depthLabel(plies: number): string {
  if (plies === 0) return 'from move 1';
  return `after ${Math.ceil(plies / 2)} ${plies <= 2 ? 'move' : 'moves'}`;
}
