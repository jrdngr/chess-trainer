import { useMemo } from 'react';
import { START_FEN } from '../../chess/core';
import { AppBar, Icons, Section, Segmented, toast } from '../../components/ui';
import { SelectionBar } from '../../components/Selection';
import { openingTree } from '../../model/openingTree';
import { colorsOf, regionOf, repertoiresIn } from '../../model/selection';
import { growthRows, optionsAt, recommended, type GrowthRow } from '../../model/growth';
import { GROWTH_DEPTHS, SHARE_STEPS, shareLabel } from '../../model/modes';
import { referenceIndex } from '../../model/referenceIndex';
import { createRepertoire } from '../../model/repertoire';
import { repertoireList, useStore } from '../../store/useStore';

/** Stands in for a side with no tree yet, until the first move is kept. */
const STAND_IN = 'growth_stand_in_';

/**
 * Where the work is, shallowest first.
 *
 * Depth is the urgency signal: the shallower a hole, the more games fall into
 * it. An unanswered 1...e5 costs you a quarter of your games as White; one at
 * move nine costs almost none.
 *
 * This is also where a repertoire starts. Autopilot drills what you have and
 * adds nothing, so a side with nothing in it is grown from nothing here: as
 * Black, the first moves you would meet are the first holes; as White, your
 * first move is not a reply to anything, so it is picked from the book, and
 * Black's answers to it are the holes from there.
 */
export function Lobby({ onStart, onExit }: { onStart: (row: GrowthRow) => void; onExit: () => void }) {
  const state = useStore();
  const setModePrefs = useStore((s) => s.setModePrefs);
  const ensureRepertoire = useStore((s) => s.ensureRepertoire);
  const addLine = useStore((s) => s.addLine);
  const prefs = state.settings.growth;
  const selection = state.settings.selection;
  const index = referenceIndex();
  const tree = openingTree(index);
  const node = regionOf(tree, selection);

  /** One tree per side the selection asks for, an empty stand-in where there is none. */
  const reps = useMemo(() => {
    const have = repertoiresIn(repertoireList(state), selection.color);
    return colorsOf(selection.color).map(
      (color) =>
        have.find((rep) => rep.color === color) ??
        createRepertoire(color === 'w' ? 'White' : 'Black', color, `${STAND_IN}${color}`),
    );
    // Derived from these alone; the state object itself changes every render.
  }, [state.repertoires, state.repertoireOrder, selection.color]);

  /** A side that exists but has no moves in it yet cannot be grown. */
  const hasMoves = reps.some((rep) => Object.keys(rep.nodes).length > 0);
  /** White with nothing yet: the first move has to be chosen before there is anything to answer. */
  const whiteEmpty = reps.some((rep) => rep.color === 'w' && Object.keys(rep.nodes).length === 0);
  const firstMoves = useMemo(() => (whiteEmpty ? optionsAt(index, START_FEN, 5) : []), [whiteEmpty, index]);

  /** A row on a stand-in starts on the real tree, made on the spot. */
  const start = (row: GrowthRow) => {
    if (!row.repertoireId.startsWith(STAND_IN)) return onStart(row);
    onStart({ ...row, repertoireId: ensureRepertoire(row.color) });
  };

  const keepFirstMove = (san: string) => {
    addLine(ensureRepertoire('w'), [san], 'reference');
    toast(`1.${san} kept · now answer Black's replies`);
  };

  const starred = state.settings.favoriteOpenings;
  const rows = useMemo(
    () =>
      growthRows(reps, index, {
        minShare: prefs.minShare,
        maxPly: prefs.maxPly,
        starred,
        region: { tree, node },
      }),
    [reps, index, prefs.minShare, prefs.maxPly, starred, tree, node],
  );
  const pick = recommended(rows);

  return (
    <>
      <AppBar
        title="Growth"
        subtitle={rows.length === 1 ? '1 opening to extend' : `${rows.length} openings to extend`}
        onClose={onExit}
      />

      <div className="screen no-nav">
        <SelectionBar />

        {pick && (
          <button className="btn primary block xl" onClick={() => start(pick)}>
            Start
          </button>
        )}

        {whiteEmpty && (
          <>
            <Section title="Your first move as White" aside="from the book" />
            <div className="empty" style={{ paddingTop: 0 }}>
              <div className="h">
                Growth answers replies, and your first move is not a reply to anything. Pick it,
                and Black's answers to it are what there is to grow.
              </div>
            </div>
            <div className="list">
              {firstMoves.map((move) => (
                <button key={move.san} className="list-row" onClick={() => keepFirstMove(move.san)}>
                  <span className="side w" />
                  <span className="grow" style={{ minWidth: 0 }}>
                    <div className="title">1.{move.san}</div>
                    <div className="meta">{move.share}% of games</div>
                  </span>
                  <Icons.chevron size={18} />
                </button>
              ))}
            </div>
          </>
        )}

        {rows.length === 0 ? (
          hasMoves && (
            <div className="empty">
              <div className="t">Nothing to extend</div>
              <div className="h">
                {`Your repertoire meets every reply played in ${prefs.minShare}% of games or more${node.depth > 0 ? ` in ${node.name}` : ''}, down to ${Math.ceil(prefs.maxPly / 2)} moves. Lower the threshold below, or widen the opening, to keep going.`}
              </div>
            </div>
          )
        ) : (
          <>
            <Section title="Or pick one" aside="most worth doing first" />
            <div className="list">
              {rows.map((row) => (
                <button key={row.id} className="list-row" onClick={() => start(row)}>
                  <span className={`side ${row.color}`} />
                  <span className="grow" style={{ minWidth: 0 }}>
                    <div className="title truncate">
                      {row.starred && (
                        <span style={{ color: 'var(--accent)', marginRight: 5 }}>
                          <Icons.star size={12} filled />
                        </span>
                      )}
                      {row.name}
                    </div>
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

        <Section title="Nudge toward" />
        <Segmented
          value={prefs.nudgePriority}
          options={[
            { value: 'transposition', label: 'Transpositions' },
            { value: 'habit', label: 'Habits' },
          ]}
          onChange={(nudgePriority) => setModePrefs('growth', { nudgePriority })}
        />
        <div className="note">
          {prefs.nudgePriority === 'transposition'
            ? 'A move that lands in a line you have wins the green arrow; failing that, one you already play in this opening.'
            : 'A move you already play in this opening wins the green arrow; failing that, one that lands in a line you have.'}{' '}
          Red marks the move that closes off your lines or that you keep choosing against. Run's new moves follow this too.
        </div>

        <Section title="Pawn structure" />
        <Segmented
          value={prefs.nudgePawns ? 'on' : 'off'}
          options={[
            { value: 'off', label: 'Off' },
            { value: 'on', label: 'Counts as a habit' },
          ]}
          onChange={(on) => setModePrefs('growth', { nudgePawns: on === 'on' })}
        />

        {hasMoves && (
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
