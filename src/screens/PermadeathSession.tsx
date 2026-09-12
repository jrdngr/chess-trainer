import { useEffect, useMemo, useRef, useState } from 'react';
import { Board } from '../components/Board';
import { haptic, IconButton, Icons } from '../components/ui';
import { applySan, type LegalMove, type Square } from '../chess/core';
import { referenceIndex } from '../model/referenceIndex';
import {
  currentFen,
  expectedMoves,
  lineName,
  isComplete,
  isUsersTurn,
  opponentReply,
  play,
  revealText,
  startRun,
  type Run,
} from '../model/permadeath';
import { mulberry32 } from '../model/session';
import { repertoireList, useStore } from '../store/useStore';

export interface PermadeathSessionProps {
  onExit: () => void;
}

type Phase = 'playing' | 'dead' | 'survived';

/**
 * One secret line, played until the first mistake.
 *
 * Nothing on screen names the line while it is running — no opening name, no
 * move list, no explore. The reveal is the reward for dying.
 */
export function PermadeathSession({ onExit }: PermadeathSessionProps) {
  const state = useStore();
  const reps = repertoireList(state);
  const endRun = useStore((s) => s.endPermadeathRun);
  const missed = useStore((s) => s.missedInPermadeath);
  const record = useStore((s) => s.permadeath);

  const [run, setRun] = useState<Run | null>(() => startRun(reps));
  const [phase, setPhase] = useState<Phase>('playing');
  const [death, setDeath] = useState<{ played: string; expected: string[] } | null>(null);
  const [thinking, setThinking] = useState(false);
  const picker = useRef(mulberry32(Math.floor(Math.random() * 2 ** 31)));
  const settled = useRef(false);

  const rep = run ? state.repertoires[run.repertoireId] : null;
  const fen = rep && run ? currentFen(rep, run) : null;
  const myTurn = rep && run ? isUsersTurn(rep, run) : false;

  // The opponent answers on its own, after a beat.
  useEffect(() => {
    if (!rep || !run || phase !== 'playing' || myTurn || run.over) return;
    if (expectedMoves(rep, run).length === 0) return;
    setThinking(true);
    const timer = setTimeout(() => {
      setThinking(false);
      setRun(opponentReply(rep, run, picker.current));
    }, 420);
    return () => clearTimeout(timer);
  }, [rep, run, myTurn, phase]);

  /**
   * Reaching the end of the line without a mistake is a win. Lines finish on
   * the user's own move, so the position that ends a run is the opponent's
   * turn with nothing prepared — checking whose turn it is would miss it.
   */
  useEffect(() => {
    if (!rep || !run || phase !== 'playing' || settled.current) return;
    if (isComplete(rep, run)) {
      settled.current = true;
      setPhase('survived');
      endRun(run.survived, true);
    }
  }, [rep, run, phase, endRun]);

  /**
   * The line gets its real name once the run is over — the opening and ECO
   * code for the whole secret line, not just the repertoire it came from.
   * Computed only when the run ends, so nothing can leak mid-run.
   */
  const named = useMemo(() => {
    if (!rep || !run || phase === 'playing') return null;
    return lineName(referenceIndex(), rep, run);
  }, [rep, run, phase]);

  const lastMove = useMemo(() => {
    if (!run || run.played.length === 0) return null;
    const prefix = run.played.slice(0, -1);
    let cursor = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
    for (const san of prefix) {
      const step = applySan(cursor, san);
      if (!step) return null;
      cursor = step.after;
    }
    const move = applySan(cursor, run.played[run.played.length - 1]);
    return move ? { from: move.from, to: move.to } : null;
  }, [run]);

  const highlights = useMemo(() => {
    if (phase !== 'dead' || !death || !fen) return [];
    const out: { square: Square; kind: 'good' | 'bad' | 'hint' }[] = [];
    const wrong = applySan(fen, death.played);
    if (wrong) out.push({ square: wrong.from, kind: 'bad' }, { square: wrong.to, kind: 'bad' });
    const right = applySan(fen, death.expected[0]);
    if (right) out.push({ square: right.from, kind: 'good' }, { square: right.to, kind: 'good' });
    return out;
  }, [phase, death, fen]);

  if (!run || !rep || !fen) {
    return (
      <div className="app">
        <div className="appbar compact">
          <IconButton label="Close" onClick={onExit}>
            <Icons.close size={20} />
          </IconButton>
          <div className="appbar-title"><div className="line">Permadeath</div></div>
          <span style={{ width: 38 }} />
        </div>
        <div className="screen no-nav">
          <div className="empty">
            <div className="t">No line long enough</div>
            <div className="h">Add a few more moves to a repertoire and try again.</div>
          </div>
        </div>
      </div>
    );
  }

  const onMove = (move: LegalMove) => {
    if (phase !== 'playing' || !myTurn) return;
    const result = play(rep, run, move.san);
    if (result.ok) {
      if (state.settings.hapticFeedback) haptic(10);
      setRun(result.run);
      return;
    }
    if (state.settings.hapticFeedback) haptic([22, 60, 22]);
    settled.current = true;
    setDeath({ played: result.played, expected: result.expected });
    setRun(result.run);
    setPhase('dead');
    endRun(run.survived, false);
    missed(rep.id, fen, result.played, result.expected[0] ?? '');
  };

  const restart = () => {
    settled.current = false;
    setDeath(null);
    setPhase('playing');
    setRun(startRun(reps));
  };

  const over = phase !== 'playing';
  const survivedLabel = run.survived === 1 ? '1 move' : `${run.survived} moves`;

  return (
    <div className="app">
      <div className="appbar compact">
        <IconButton label="Close" onClick={onExit}>
          <Icons.close size={20} />
        </IconButton>
        <div className="appbar-title">
          <div className="line">Permadeath</div>
          <div className="sub">
            {phase === 'survived' ? 'Survived' : phase === 'dead' ? 'Run over' : 'Secret line'}
          </div>
        </div>
        <span className="chip" style={{ minWidth: 38, justifyContent: 'center' }}>
          {run.survived}
        </span>
      </div>

      <div className="screen no-nav">
        <Board
          fen={fen}
          orientation={rep.color}
          interactive={phase === 'playing' && myTurn && !thinking}
          movableFor={rep.color}
          onMove={onMove}
          lastMove={phase === 'dead' ? null : lastMove}
          highlights={highlights}
          showCoordinates={state.settings.showCoordinates}
          theme={state.settings.boardTheme}
          dimmed={over}
        />

        <div className="spacer" />

        {phase === 'playing' && (
          <div className="prompt">
            <div className="who">
              {thinking ? <span className="spinner" /> : <span className={`side ${rep.color}`} />}
              {thinking ? 'Reply' : 'Your move'}
            </div>
            <div className="ctx">One mistake ends the run</div>
          </div>
        )}

        {phase === 'survived' && (
          <>
            <div className="verdict ok">
              <span className="ico"><Icons.check size={18} /></span>
              Line complete
            </div>
            <div className="center muted small" style={{ marginTop: 2 }}>
              You played the whole line — {survivedLabel} without a slip.
            </div>
          </>
        )}

        {phase === 'dead' && death && (
          <>
            <div className="verdict no">
              <span className="ico"><Icons.cross size={18} /></span>
              Run over
            </div>
            <div className="compare" style={{ marginTop: 10 }}>
              <div className="good">
                <div className="k">Repertoire</div>
                <div className="v">{death.expected[0] ?? '—'}</div>
              </div>
              <div className="bad">
                <div className="k">You played</div>
                <div className="v">{death.played}</div>
              </div>
            </div>
            {death.expected.length > 1 && (
              <div className="center faint tiny" style={{ marginTop: 8 }}>
                Also prepared: {death.expected.slice(1).join(', ')}
              </div>
            )}
          </>
        )}

        {over && (
          <>
            <div className="section">The line</div>
            <div className="card">
              <div className="row between" style={{ gap: 10 }}>
                <span className="grow" style={{ minWidth: 0 }}>
                  <div style={{ fontWeight: 700, fontSize: 16, letterSpacing: '-0.01em' }}>
                    {named?.name ?? run.repertoireName}
                  </div>
                  <div className="faint tiny" style={{ marginTop: 2 }}>
                    {named?.specific ? `${run.repertoireName} · ` : ''}
                    {phase === 'survived' ? 'played in full' : `${run.survived} correct`}
                  </div>
                </span>
                {named?.eco && <span className="chip">{named.eco}</span>}
              </div>
              <div className="divider" />
              <div className="movetext">{revealText(rep, run)}</div>
            </div>

            <div className="section">Record</div>
            <div className="list">
              <div className="list-row">
                <span className="grow"><div className="title">Best run</div></span>
                <span className="val num">{record.best}</span>
              </div>
              <div className="list-row">
                <span className="grow"><div className="title">Runs</div></span>
                <span className="val num">{record.runs}</span>
              </div>
              <div className="list-row">
                <span className="grow"><div className="title">Lines completed</div></span>
                <span className="val num">{record.survivals}</span>
              </div>
            </div>

            <div className="spacer" />
            <button className="btn primary block xl" onClick={restart}>
              New run
            </button>
            <button className="btn plain block" style={{ marginTop: 8 }} onClick={onExit}>
              Done
            </button>
          </>
        )}
      </div>
    </div>
  );
}
