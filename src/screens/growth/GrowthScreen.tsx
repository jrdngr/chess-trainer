import { useEffect, useMemo, useState } from 'react';
import { Board } from '../../components/Board';
import { AppBar, haptic, Icons, Section, Strip, toast, type StripItem } from '../../components/ui';
import { applySan, lastMoveOf, sansToMoveText, type LegalMove } from '../../chess/core';
import {
  advance,
  answerHole,
  atHole,
  enterHole,
  isUsersTurn,
  growthRows,
  lineFor,
  MAX_ADDS,
  movesToDraw,
  nextHole,
  optionsAt,
  preparedHere,
  startGrowth,
  steer,
  type GrowthRow,
  type GrowthRun,
} from '../../model/growth';
import { formatGameCount } from '../../model/reference';
import { referenceIndex } from '../../model/referenceIndex';
import { openingTree } from '../../model/openingTree';
import { regionOf, repertoiresIn } from '../../model/selection';
import { selectionText } from '../../components/Selection';
import { repertoireList, useStore } from '../../store/useStore';
import { PlayOn } from '../openingRun/PlayOn';
import { Lobby } from './Lobby';

export interface GrowthScreenProps {
  /** Skip the lobby and extend the worst hole — Next Up started this. */
  auto?: boolean;
  onExit: () => void;
}

export function GrowthScreen({ auto, onExit }: GrowthScreenProps) {
  const state = useStore();
  // The lobby's own order: shallowest hole first, because that is the one the
  // most games fall into. Next Up picks the top of the same list.
  const [row, setRow] = useState<GrowthRow | null>(() => {
    if (!auto) return null;
    const tree = openingTree(referenceIndex());
    const selection = state.settings.selection;
    return (
      growthRows(repertoiresIn(repertoireList(state), selection.color), tree.index, {
        ...state.settings.growth,
        starred: state.settings.favoriteOpenings,
        region: { tree, node: regionOf(tree, selection) },
      })[0] ?? null
    );
  });
  if (!row) return <Lobby onStart={setRow} onNoWork={onExit} onExit={onExit} />;
  // A run nobody chose has no lobby to fall back to.
  return <Run row={row} onExit={() => (auto ? onExit() : setRow(null))} />;
}

type Phase = 'walking' | 'hole' | 'answered' | 'done' | 'lost';

function Run({ row, onExit }: { row: GrowthRow; onExit: () => void }) {
  const state = useStore();
  const settings = state.settings;
  const addLine = useStore((s) => s.addLine);
  const noteActivity = useStore((s) => s.noteActivity);
  const index = referenceIndex();
  const rep = state.repertoires[row.repertoireId];

  /** The tree as it was when the run began, so adding a move cannot re-steer it. */
  const [tree] = useState(() => rep);
  const [run, setRun] = useState<GrowthRun>(() => startGrowth(tree, row));
  const [phase, setPhase] = useState<Phase>('walking');
  const [wrong, setWrong] = useState<string | null>(null);
  /** Which plies of the line you added, so the strip can mark them. */
  const [added, setAdded] = useState<number[]>([]);
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
    // A filled hole is what counts as having done Growth. Reaching one and
    // backing out is not work, and Next Up would stop offering the mode on it.
    noteActivity('growth');
    setAdded((plies) => [...plies, run.path.length]);
    setAnswer(move);
    setRun(next);
    setPhase(added.length + 1 >= MAX_ADDS ? 'done' : 'answered');
    if (settings.hapticFeedback) haptic(10);
    toast(`${san} added`);
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
        <AppBar title="Growth" onClose={onExit} />
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
        title={row.name}
        subtitle={selectionText(run.color, settings.selection.opening)}
        onClose={onExit}
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
              {added.length} of {MAX_ADDS} added
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

        {phase === 'hole' && (
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
              aside={added.length > 0 ? `${added.length} of ${MAX_ADDS} added` : undefined}
            />
            {options.length === 0 ? (
              <div className="card small muted">
                The database has nothing here. Add a move from the Repertoire screen instead.
              </div>
            ) : (
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
            )}
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
              <div className="verdict ok" style={{ padding: 0 }}>
                <span className="ico"><Icons.check size={16} /></span>
                {addedSans.length === 1 ? `${addedSans[0]} added` : `${addedSans.length} moves added`}
              </div>
              <button className="btn primary sm" onClick={onExit}>
                New run
                <Icons.next size={16} />
              </button>
            </div>
            <Section title="The line now" />
            <div className="card">
              <div className="movetext">{sansToMoveText(run.path)}</div>
            </div>
            <button className="btn block mt-12" onClick={() => setPlayFrom(run.fen)}>
              <Icons.play size={18} />
              Play from here
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
