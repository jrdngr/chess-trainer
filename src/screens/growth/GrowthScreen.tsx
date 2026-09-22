import { useEffect, useMemo, useRef, useState } from 'react';
import { Board } from '../../components/Board';
import { AppBar, haptic, Icons, Section, Strip, toast, type StripItem } from '../../components/ui';
import { applySan, lastMoveOf, sansToMoveText, type LegalMove } from '../../chess/core';
import {
  addsToFit,
  advance,
  answerHole,
  atHole,
  enterHole,
  isUsersTurn,
  lineFor,
  movesToDraw,
  nextHole,
  growthRows,
  optionsAt,
  preparedHere,
  recommended,
  resumeAdding,
  startGrowth,
  startGrowthAt,
  steer,
  type GrowthRow,
  type GrowthRun,
  type Hole,
} from '../../model/growth';
import { formatGameCount } from '../../model/reference';
import type { RoundRecord } from '../../model/scoring';
import { deepestNodeWithin, nodeById, openingTree } from '../../model/openingTree';
import { regionOf } from '../../model/selection';
import { referenceIndex } from '../../model/referenceIndex';
import { selectionText } from '../../components/Selection';
import { useStore } from '../../store/useStore';
import { PlayOn } from '../openingRun/PlayOn';
import { Lobby } from './Lobby';

/**
 * Growth opened from the end of a Run or Autopilot round, by its offer to
 * grow the opening: straight into a run, never the lobby, and the way out is
 * back to the mode that sent you.
 */
export interface GrowthLaunch {
  row: GrowthRow;
  /** The hole the round ended on, when the first run starts standing on it. */
  hole: Hole | null;
  /** The opening grown, an opening tree node id: what New run looks in. */
  region: string;
  /** "Back to Autopilot" or "Back to Run". */
  backLabel: string;
  onBack: () => void;
}

export interface GrowthScreenProps {
  onExit: () => void;
  launch?: GrowthLaunch;
}

export function GrowthScreen({ onExit, launch }: GrowthScreenProps) {
  const [row, setRow] = useState<GrowthRow | null>(launch?.row ?? null);
  /**
   * Counted up for every run started, and used as the run's key: another run
   * on the same row is a run of its own, not the last one carrying on.
   */
  const [started, setStarted] = useState(0);

  const start = (next: GrowthRow) => {
    setRow(next);
    setStarted((n) => n + 1);
  };

  if (!row) return <Lobby onStart={start} onExit={onExit} />;
  return (
    <Run
      key={started}
      row={row}
      // Only the first run of a launch starts where the round ended.
      hole={launch && started === 0 ? launch.hole : null}
      region={launch?.region}
      back={launch ? { label: launch.backLabel, onBack: launch.onBack } : null}
      onAgain={start}
      onExit={launch ? launch.onBack : () => setRow(null)}
      onClose={onExit}
    />
  );
}

type Phase = 'walking' | 'hole' | 'answered' | 'done' | 'lost';

function Run({
  row,
  hole,
  region,
  back,
  onAgain,
  onExit,
  onClose,
}: {
  row: GrowthRow;
  /** Start standing at this hole rather than walking to the row's. */
  hole?: Hole | null;
  /** The opening New run looks in, when not the selection. */
  region?: string;
  /** The way back to the mode Growth was opened from, in place of the lobby. */
  back?: { label: string; onBack: () => void } | null;
  /** Start another run, on the row this one's work leaves most worth doing. */
  onAgain: (row: GrowthRow) => void;
  /** Back to the lobby. */
  onExit: () => void;
  /** The close button: out of Growth altogether. */
  onClose: () => void;
}) {
  const state = useStore();
  const settings = state.settings;
  const addLine = useStore((s) => s.addLine);
  const endRound = useStore((s) => s.endRound);
  /** The round this sitting will log, kept current until the run is left. */
  const pending = useRef<Omit<RoundRecord, 'at'> | null>(null);
  const index = referenceIndex();
  const rep = state.repertoires[row.repertoireId];

  /** The tree as it was when the run began, so adding a move cannot re-steer it. */
  const [tree] = useState(() => rep);
  const [run, setRun] = useState<GrowthRun>(() => (hole ? startGrowthAt(tree, row, hole) : startGrowth(tree, row)));
  const [phase, setPhase] = useState<Phase>(() => (hole ? 'hole' : 'walking'));
  const [wrong, setWrong] = useState<string | null>(null);
  /** Which plies of the line you added, so the strip can mark them. */
  const [added, setAdded] = useState<number[]>([]);
  /**
   * The batch being added: where it began in `added`, and how many it may add.
   *
   * Set when the run arrives at the hole the batch starts from, so the
   * allowance is measured from that depth, and cleared when the reveal is
   * asked for another batch — which is how a second batch gets the smaller
   * allowance its deeper hole has earned.
   */
  const [batch, setBatch] = useState<{ base: number; allowance: number } | null>(null);
  /** The answer just chosen, until they reply to it — the board shows it green. */
  const [answer, setAnswer] = useState<LegalMove | null>(null);
  const [thinking, setThinking] = useState(false);
  /** The position a carry-on game starts from, once one is asked for. */
  const [playFrom, setPlayFrom] = useState<string | null>(null);

  const prefs = settings.growth;
  const expected = useMemo(() => preparedHere(tree, run), [tree, run]);

  /** The opponent answers on its own, after a beat. */
  useEffect(() => {
    if (phase !== 'walking' || isUsersTurn(run)) return;
    if (atHole(tree, run)) return;
    setThinking(true);
    const timer = setTimeout(() => {
      setThinking(false);
      const reply = steer(tree, index, run, { minShare: prefs.minShare, maxPly: prefs.maxPly });
      if (!reply) {
        setPhase('hole');
        return;
      }
      if (reply.hole) {
        setRun(enterHole(run, reply.hole));
        setPhase('hole');
        return;
      }
      const next = advance(tree, run, reply.san);
      if (next) setRun(next);
      else setPhase('hole');
    }, 420);
    return () => clearTimeout(timer);
  }, [phase, run, tree, index, prefs.minShare, prefs.maxPly]);

  /** A line that ends on the opponent's move leaves you to move with nothing. */
  useEffect(() => {
    if (phase !== 'walking') return;
    if (isUsersTurn(run) && expected.length === 0) setPhase('hole');
  }, [phase, run, expected.length]);

  const options = useMemo(
    () => (phase === 'hole' ? optionsAt(index, run.fen, 4) : []),
    [phase, index, run.fen],
  );

  /** The moves drawn on the board, which are also the only ones playable on it. */
  const shown = useMemo(
    () => (phase === 'hole' ? movesToDraw(index, run.fen) : []),
    [phase, index, run.fen],
  );

  /**
   * How many this batch may add, from how deep the hole it starts at is.
   *
   * Read straight from the position until the batch is recorded, so the
   * count under the board is right on the frame the hole appears.
   */
  const allowance = batch?.allowance ?? addsToFit(run.path.length, prefs.maxPly);
  const inBatch = added.length - (batch?.base ?? added.length);

  /**
   * What another batch would answer, once the run has come to rest — null when
   * the book has nothing left there, and the reveal offers nothing.
   */
  const more = useMemo(
    () => (phase === 'done' ? resumeAdding(tree, index, run) : null),
    [phase, tree, index, run],
  );

  /**
   * A hole the book cannot answer ends the batch rather than sitting there.
   *
   * The book stops where a position stops being played often enough to
   * record, and the walk can arrive just past that edge — a King's Indian
   * Sämisch runs out at 7.Nge2 — where there is nothing to choose and no
   * reason to ask. The reveal says so and offers a new run.
   */
  useEffect(() => {
    if (phase === 'hole' && options.length === 0) setPhase('done');
  }, [phase, options.length]);

  /** A batch is measured from the first hole it is offered at. */
  useEffect(() => {
    if (phase !== 'hole' || batch) return;
    setBatch({ base: added.length, allowance: addsToFit(run.path.length, prefs.maxPly) });
  }, [phase, batch, added.length, run.path.length, prefs.maxPly]);

  const onMove = (move: LegalMove) => {
    if (phase === 'hole') {
      // The board only offers the drawn moves, and taking one is the choice.
      if (shown.some((drawn) => drawn.san === move.san)) choose(move.san);
      return;
    }
    if (phase !== 'walking' || !isUsersTurn(run)) return;
    const next = advance(tree, run, move.san);
    if (!next) {
      // Your own prep is the only thing that counts here, so anything else
      // ends the run rather than quietly becoming a new line.
      setWrong(move.san);
      setPhase('lost');
      if (settings.hapticFeedback) haptic([18, 50, 18]);
      return;
    }
    setRun(next);
    if (settings.hapticFeedback) haptic(10);
  };

  /**
   * Take a move. The run walks on rather than ending: the answer is played, and
   * unless this was the last one allowed, their commonest reply to it becomes
   * the next thing to answer.
   */
  const choose = (san: string) => {
    const move = applySan(run.fen, san);
    const next = move ? answerHole(run, san) : null;
    if (!next) return;
    addLine(row.repertoireId, lineFor(run, san), 'reference');
    setAdded((plies) => [...plies, run.path.length]);
    setAnswer(move);
    setRun(next);
    setPhase(inBatch + 1 >= allowance ? 'done' : 'answered');
    if (settings.hapticFeedback) haptic(10);
    toast(`${san} added`);
  };

  /**
   * Another run on the same side and settings, on whatever is now most worth
   * extending — the moves just added are in the repertoire, so the row is
   * worked out again rather than repeated. With nothing left to answer on this
   * side, the lobby is the honest answer, and it says so.
   */
  const again = () => {
    const live = state.repertoires[row.repertoireId];
    if (!live) return onExit();
    const catalogue = openingTree(index);
    const next = recommended(
      growthRows([live], index, {
        minShare: prefs.minShare,
        maxPly: prefs.maxPly,
        starred: settings.favoriteOpenings,
        region: { tree: catalogue, node: region ? nodeById(catalogue, region) : regionOf(catalogue, settings.selection) },
      }),
    );
    if (next) onAgain(next);
    else onExit();
  };

  /**
   * Take the reveal up on another batch. Nothing here happens on its own: the
   * run has stopped, and this is the tap that starts it answering again.
   */
  const addMore = () => {
    if (!more) return;
    setAnswer(null);
    setBatch(null);
    setRun(more);
    setPhase('hole');
    if (settings.hapticFeedback) haptic(10);
  };

  /** Their reply to the move you just added, after a beat. */
  useEffect(() => {
    if (phase !== 'answered') return;
    const timer = setTimeout(() => {
      const hole = nextHole(index, run);
      // The book knows nothing past here, so there is nothing left to answer.
      if (!hole) {
        setPhase('done');
        return;
      }
      setAnswer(null);
      setRun(enterHole(run, hole));
      setPhase('hole');
    }, 520);
    return () => clearTimeout(timer);
  }, [phase, run, index]);

  const addedSans = added.map((ply) => run.path[ply]).filter(Boolean);

  /**
   * One sitting is one round, whatever it takes: the reveal only draws up what
   * the round would be, and asking for another batch redraws it.
   */
  useEffect(() => {
    if (phase !== 'done' && phase !== 'lost') return;
    const catalogue = openingTree(index);
    const within = nodeById(catalogue, region ?? settings.selection.opening);
    pending.current = {
      mode: 'growth',
      openingId: deepestNodeWithin(catalogue, within, run.path).id,
      color: run.color,
      answered: 0,
      correct: 0,
      perfect: inBatch >= allowance,
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [phase, added.length]);

  /**
   * And it is logged on the way out rather than at the reveal, because the
   * reveal is no longer the end of anything: another batch can follow it.
   */
  useEffect(() => () => {
    if (pending.current) endRound(pending.current);
  }, [endRound]);

  const strip: StripItem[] = run.path.map((san, i) => ({
    san,
    label: i % 2 === 0 ? `${Math.floor(i / 2) + 1}.` : undefined,
    tone: added.includes(i)
      ? 'good'
      : (i % 2 === 0) === (run.color === 'w')
        ? 'mine'
        : 'theirs',
    current: i === run.path.length - 1,
  }));

  if (playFrom) {
    return (
      <PlayOn
        from={playFrom}
        color={run.color}
        label={row.name}
        onBack={() => setPlayFrom(null)}
      />
    );
  }

  if (!rep) {
    return (
      <>
        <AppBar title="Growth" onClose={onClose} />
        <div className="screen no-nav">
          <div className="empty">
            <div className="t">Those lines are gone</div>
          </div>
        </div>
      </>
    );
  }

  return (
    <>
      <AppBar
        title="Growth"
        subtitle={selectionText(run.color, region ?? settings.selection.opening)}
        onClose={onClose}
        actions={
          <span className="num muted small appbar-gap" style={{ textAlign: 'right' }}>
            {Object.keys(rep.nodes).length}
          </span>
        }
      />

      <div className="screen no-nav">
        <Board
          fen={run.fen}
          orientation={run.color}
          interactive={(phase === 'walking' && isUsersTurn(run)) || phase === 'hole'}
          movableFor={run.color}
          allowed={phase === 'hole' ? shown.map((move) => move.san) : undefined}
          arrows={shown.map((move) => ({ from: move.from, to: move.to }))}
          onMove={onMove}
          // The green highlight below stands in for the usual last-move tint on
          // the move that was just added, so the two do not compete.
          lastMove={answer ? null : lastMoveOf(run.path)}
          highlights={
            answer
              ? [
                  { square: answer.from, kind: 'good' },
                  { square: answer.to, kind: 'good' },
                ]
              : []
          }
          showCoordinates={settings.showCoordinates}
          theme={settings.boardTheme}
          dimmed={phase === 'lost'}
          captured
        />

        <div className="spacer sm" />
        {run.path.length > 0 && <Strip items={strip} />}
        <div className="spacer sm" />

        {phase === 'walking' && (
          <div className="prompt">
            <div className="who">
              <span className={`side ${isUsersTurn(run) ? run.color : other(run.color)}`} />
              {thinking ? 'Thinking…' : isUsersTurn(run) ? 'Your move' : 'Their move'}
            </div>
          </div>
        )}

        {phase === 'answered' && (
          <div className="prompt">
            <div className="who">
              <span className={`side ${other(run.color)}`} />
              Thinking…
            </div>
            <div className="ctx">
              {inBatch} of {allowance} added
            </div>
          </div>
        )}

        {phase === 'lost' && (
          <>
            <div className="row between">
              <div className="verdict no" style={{ padding: 0 }}>
                <span className="ico"><Icons.cross size={14} /></span>
                Not your prep
              </div>
              <button className="btn primary sm" onClick={onExit}>
                Back
                <Icons.next size={16} />
              </button>
            </div>
            <div className="compare mt-8">
              <div className="good">
                <div className="k">Repertoire</div>
                <div className="v">{expected.map((e) => e.san).join(' / ') || '—'}</div>
              </div>
              <div className="bad">
                <div className="k">Played</div>
                <div className="v">{wrong}</div>
              </div>
            </div>
          </>
        )}

        {phase === 'hole' && options.length > 0 && (
          <>
            <div className="prompt">
              <div className="who">
                <span className={`side ${run.color}`} />
                {run.hole ? `They played ${run.hole.san}` : 'Your prep ends here'}
              </div>
              {run.hole && (
                <div className="ctx">
                  {run.hole.share}% of games · {formatGameCount(run.hole.games)}
                </div>
              )}
            </div>

            <Section
              title="Answer it"
              aside={inBatch > 0 ? `${inBatch} of ${allowance} added` : `up to ${allowance}`}
            />
            <div className="list">
              {options.map((option) => (
                <button className="list-row" key={option.san} onClick={() => choose(option.san)}>
                  <span className="tree-san">{option.san}</span>
                  <span className="grow">
                    <div className="meta">
                      {option.share}% of replies · {formatGameCount(option.games)} games
                    </div>
                  </span>
                  <Icons.plus size={18} />
                </button>
              ))}
            </div>
            {added.length > 0 && (
              <button className="btn block mt-8" onClick={() => setPhase('done')}>
                Stop here
              </button>
            )}
          </>
        )}

        {phase === 'done' && (
          <>
            <div className="row between">
              <div className={`verdict ${addedSans.length ? 'ok' : 'warn'}`} style={{ padding: 0 }}>
                <span className="ico">
                  {addedSans.length ? <Icons.check size={16} /> : <Icons.warn size={16} />}
                </span>
                {addedSans.length === 0
                  ? 'Nothing to add here'
                  : addedSans.length === 1
                    ? `${addedSans[0]} added`
                    : `${addedSans.length} moves added`}
              </div>
              <button className="btn primary sm" onClick={again}>
                New run
                <Icons.next size={16} />
              </button>
            </div>
            <Section title="The line now" />
            <div className="card">
              <div className="movetext">{sansToMoveText(run.path)}</div>
            </div>
            {!more && (
              <div className="card small muted mt-8">
                The book ends here, so there is nothing more to answer. Add a move from the
                Repertoire screen to go deeper than the book does.
              </div>
            )}
            {more && (
              <button className="btn block mt-12" onClick={addMore}>
                <Icons.plus size={18} />
                Add more moves
              </button>
            )}
            <button className={`btn block ${more ? 'mt-8' : 'mt-12'}`} onClick={() => setPlayFrom(run.fen)}>
              <Icons.play size={18} />
              Play from here
            </button>
            <button className="btn plain block mt-8" onClick={back ? back.onBack : onExit}>
              {back ? back.label : 'Back to openings'}
            </button>
          </>
        )}
      </div>
    </>
  );
}

function other(color: 'w' | 'b'): 'w' | 'b' {
  return color === 'w' ? 'b' : 'w';
}
