import { useEffect, useMemo, useState } from 'react';
import { Board } from '../../components/Board';
import { AppBar, haptic, Icons, Section, Strip, toast, type StripItem } from '../../components/ui';
import { applySan, lastMoveOf, sansToMoveText, type LegalMove } from '../../chess/core';
import {
  advance,
  atHole,
  enterHole,
  isUsersTurn,
  lineFor,
  optionsAt,
  preparedHere,
  startGrowth,
  steer,
  type GrowthRow,
  type GrowthRun,
} from '../../model/growth';
import { formatGameCount } from '../../model/reference';
import { referenceIndex } from '../../model/referenceIndex';
import { displayName } from '../../model/repertoire';
import { useStore } from '../../store/useStore';
import { PlayOn } from '../openingRun/PlayOn';
import { Lobby } from './Lobby';

export interface GrowthScreenProps {
  onExit: () => void;
}

export function GrowthScreen({ onExit }: GrowthScreenProps) {
  const [row, setRow] = useState<GrowthRow | null>(null);
  if (!row) return <Lobby onStart={setRow} onNoWork={onExit} onExit={onExit} />;
  return <Run row={row} onExit={() => setRow(null)} />;
}

type Phase = 'walking' | 'hole' | 'added' | 'lost';

function Run({ row, onExit }: { row: GrowthRow; onExit: () => void }) {
  const state = useStore();
  const settings = state.settings;
  const addLine = useStore((s) => s.addLine);
  const index = referenceIndex();
  const rep = state.repertoires[row.repertoireId];

  /** The tree as it was when the run began, so adding a move cannot re-steer it. */
  const [tree] = useState(() => rep);
  const [run, setRun] = useState<GrowthRun>(() => startGrowth(tree, row));
  const [phase, setPhase] = useState<Phase>('walking');
  const [wrong, setWrong] = useState<string | null>(null);
  const [added, setAdded] = useState<string | null>(null);
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

  const onMove = (move: LegalMove) => {
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

  /** The position the new move leads to — where a carry-on game would start. */
  const afterAdded = useMemo(
    () => (added ? (applySan(run.fen, added)?.after ?? null) : null),
    [added, run.fen],
  );

  const choose = (san: string) => {
    addLine(row.repertoireId, lineFor(run, san), 'reference');
    setAdded(san);
    setPhase('added');
    toast(`${san} added`);
  };

  const strip: StripItem[] = run.path.map((san, i) => ({
    san,
    label: i % 2 === 0 ? `${Math.floor(i / 2) + 1}.` : undefined,
    tone: (i % 2 === 0) === (run.color === 'w') ? 'mine' : 'theirs',
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
        subtitle={displayName(rep.name) === row.name ? undefined : displayName(rep.name)}
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
          interactive={phase === 'walking' && isUsersTurn(run)}
          movableFor={run.color}
          onMove={onMove}
          lastMove={lastMoveOf(run.path)}
          showCoordinates={settings.showCoordinates}
          theme={settings.boardTheme}
          dimmed={phase === 'lost'}
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
            <div className="ctx">
              {isUsersTurn(run) ? 'Play your prepared move' : 'Walking toward the gap'}
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
              <div className="ctx">
                {run.hole
                  ? `${run.hole.share}% of games · ${formatGameCount(run.hole.games)}`
                  : 'Nothing prepared at this position'}
              </div>
            </div>

            <Section title="Answer it" aside="one move, then done" />
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
          </>
        )}

        {phase === 'added' && (
          <>
            <div className="row between">
              <div className="verdict ok" style={{ padding: 0 }}>
                <span className="ico"><Icons.check size={16} /></span>
                {added} added
              </div>
              <button className="btn primary sm" onClick={onExit}>
                New run
                <Icons.next size={16} />
              </button>
            </div>
            <Section title="The line now" />
            <div className="card">
              <div className="movetext">{sansToMoveText(lineFor(run, added ?? ''))}</div>
            </div>
            <button
              className="btn block mt-12"
              onClick={() => setPlayFrom(afterAdded ?? run.fen)}
            >
              <Icons.play size={18} />
              Play from here
            </button>
            <div className="note">
              Drill will start asking about it, and the next run goes one move further.
            </div>
          </>
        )}
      </div>
    </>
  );
}

function other(color: 'w' | 'b'): 'w' | 'b' {
  return color === 'w' ? 'b' : 'w';
}
