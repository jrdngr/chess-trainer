import { useEffect, useMemo, useRef, useState } from 'react';
import { Board } from '../components/Board';
import { haptic, IconButton, Icons } from '../components/ui';
import { applySan, type LegalMove, type Square } from '../chess/core';
import { referenceIndex } from '../model/referenceIndex';
import {
  beginRun,
  isComplete,
  isUsersTurn,
  lineName,
  movesHere,
  opponentReply,
  play,
  playableRepertoires,
  revealText,
  type ColorChoice,
  type LineSource,
  type Run,
  type SourceKind,
} from '../model/permadeath';
import { mulberry32 } from '../model/session';
import { repertoireList, useStore } from '../store/useStore';

export interface PermadeathSessionProps {
  onExit: () => void;
}

type Phase = 'setup' | 'playing' | 'dead' | 'survived';

/**
 * One secret line, played until the first mistake.
 *
 * Nothing on screen names the line while it is running — no opening name, no
 * move list, no explore. The reveal is the reward for dying.
 */
export function PermadeathSession({ onExit }: PermadeathSessionProps) {
  const state = useStore();
  const reps = repertoireList(state);
  const settings = state.settings;
  const setSettings = useStore((s) => s.setSettings);
  const endRun = useStore((s) => s.endPermadeathRun);
  const missed = useStore((s) => s.missedInPermadeath);
  const record = useStore((s) => s.permadeath);

  const [phase, setPhase] = useState<Phase>('setup');
  const [game, setGame] = useState<{ source: LineSource; run: Run } | null>(null);
  const [death, setDeath] = useState<{ played: string; expected: string[] } | null>(null);
  const [thinking, setThinking] = useState(false);
  const picker = useRef(mulberry32(Math.floor(Math.random() * 2 ** 31)));
  const settled = useRef(false);

  const source = game?.source ?? null;
  const run = game?.run ?? null;
  const myTurn = run ? isUsersTurn(run) : false;

  // The opponent answers on its own, after a beat.
  useEffect(() => {
    if (!source || !run || phase !== 'playing' || myTurn || run.over) return;
    if (movesHere(source, run).length === 0) return;
    setThinking(true);
    const timer = setTimeout(() => {
      setThinking(false);
      setGame((g) => (g ? { ...g, run: opponentReply(g.source, g.run, picker.current) } : g));
    }, 420);
    return () => clearTimeout(timer);
  }, [source, run, myTurn, phase]);

  /**
   * Lines finish on the user's own move, so the position that ends a run is the
   * opponent's turn with nothing left — checking whose turn it is would miss it.
   */
  useEffect(() => {
    if (!source || !run || phase !== 'playing' || settled.current) return;
    if (isComplete(source, run)) {
      settled.current = true;
      setPhase('survived');
      endRun(run.survived, true);
    }
  }, [source, run, phase, endRun]);

  /** The line is named only once the run is over, so nothing leaks mid-run. */
  const named = useMemo(
    () => (source && run && phase !== 'playing' && phase !== 'setup' ? lineName(referenceIndex(), source, run) : null),
    [source, run, phase],
  );

  const lastMove = useMemo(() => {
    if (!run || run.played.length === 0) return null;
    const { fens } = walk(run.played.slice(0, -1));
    const move = applySan(fens[fens.length - 1], run.played[run.played.length - 1]);
    return move ? { from: move.from, to: move.to } : null;
  }, [run]);

  const highlights = useMemo(() => {
    if (phase !== 'dead' || !death || !run) return [];
    const out: { square: Square; kind: 'good' | 'bad' | 'hint' }[] = [];
    const wrong = applySan(run.fen, death.played);
    if (wrong) out.push({ square: wrong.from, kind: 'bad' }, { square: wrong.to, kind: 'bad' });
    const right = death.expected[0] ? applySan(run.fen, death.expected[0]) : null;
    if (right) out.push({ square: right.from, kind: 'good' }, { square: right.to, kind: 'good' });
    return out;
  }, [phase, death, run]);

  const start = (colour: ColorChoice, kind: SourceKind) => {
    const next = beginRun({ kind, reps, index: referenceIndex(), color: colour });
    if (!next) return;
    settled.current = false;
    setDeath(null);
    setGame(next);
    setPhase('playing');
  };

  if (phase === 'setup' || !run || !source) {
    return (
      <Setup
        colour={settings.permadeathColor}
        kind={settings.permadeathSource}
        reps={reps}
        record={record}
        onChange={(patch) => setSettings(patch)}
        onStart={start}
        onExit={onExit}
      />
    );
  }

  const onMove = (move: LegalMove) => {
    if (phase !== 'playing' || !myTurn) return;
    const result = play(source, run, move.san);
    if (result.ok) {
      if (settings.hapticFeedback) haptic(10);
      setGame({ source, run: result.run });
      return;
    }
    if (settings.hapticFeedback) haptic([22, 60, 22]);
    settled.current = true;
    setDeath({ played: result.played, expected: result.expected });
    setGame({ source, run: result.run });
    setPhase('dead');
    endRun(run.survived, false);
    if (run.repertoireId) {
      missed(run.repertoireId, run.fen, result.played, result.expected[0] ?? '');
    }
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
        <span className="chip" style={{ minWidth: 38, justifyContent: 'center' }}>{run.survived}</span>
      </div>

      <div className="screen no-nav">
        <Board
          fen={run.fen}
          orientation={run.color}
          interactive={phase === 'playing' && myTurn && !thinking}
          movableFor={run.color}
          onMove={onMove}
          lastMove={phase === 'dead' ? null : lastMove}
          highlights={highlights}
          showCoordinates={settings.showCoordinates}
          theme={settings.boardTheme}
          dimmed={over}
        />

        <div className="spacer" />

        {phase === 'playing' && (
          <div className="prompt">
            <div className="who">
              {thinking ? <span className="spinner" /> : <span className={`side ${run.color}`} />}
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
                <div className="k">{run.source === 'book' ? 'Book' : 'Repertoire'}</div>
                <div className="v">{death.expected[0] ?? '—'}</div>
              </div>
              <div className="bad">
                <div className="k">You played</div>
                <div className="v">{death.played}</div>
              </div>
            </div>
            {death.expected.length > 1 && (
              <div className="center faint tiny" style={{ marginTop: 8 }}>
                Also playable: {death.expected.slice(1, 5).join(', ')}
                {death.expected.length > 5 ? '…' : ''}
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
                    {named?.name ?? run.sourceLabel}
                  </div>
                  <div className="faint tiny" style={{ marginTop: 2 }}>
                    {named?.specific ? `${run.sourceLabel} · ` : ''}
                    {phase === 'survived' ? 'played in full' : `${run.survived} correct`}
                  </div>
                </span>
                {named?.eco && <span className="chip">{named.eco}</span>}
              </div>
              <div className="divider" />
              <div className="movetext">{revealText(source, run)}</div>
            </div>

            <div className="section">Record</div>
            <div className="list">
              <Stat label="Best run" value={record.best} />
              <Stat label="Runs" value={record.runs} />
              <Stat label="Lines completed" value={record.survivals} />
            </div>

            <div className="spacer" />
            <button
              className="btn primary block xl"
              onClick={() => start(settings.permadeathColor, settings.permadeathSource)}
            >
              New run
            </button>
            <button className="btn plain block" style={{ marginTop: 8 }} onClick={() => setPhase('setup')}>
              Change options
            </button>
          </>
        )}
      </div>
    </div>
  );
}

function Stat({ label, value }: { label: string; value: number }) {
  return (
    <div className="list-row">
      <span className="grow"><div className="title">{label}</div></span>
      <span className="val num">{value}</span>
    </div>
  );
}

function walk(sans: string[]) {
  const fens = ['rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'];
  for (const san of sans) {
    const move = applySan(fens[fens.length - 1], san);
    if (!move) break;
    fens.push(move.after);
  }
  return { fens };
}

/* ── options ────────────────────────────────────────────────────────────── */

interface SetupProps {
  colour: ColorChoice;
  kind: SourceKind;
  reps: ReturnType<typeof repertoireList>;
  record: { best: number; runs: number; survivals: number };
  onChange: (patch: { permadeathColor?: ColorChoice; permadeathSource?: SourceKind }) => void;
  onStart: (colour: ColorChoice, kind: SourceKind) => void;
  onExit: () => void;
}

function Setup({ colour, kind, reps, record, onChange, onStart, onExit }: SetupProps) {
  const available = playableRepertoires(reps, colour);
  const blocked = kind === 'repertoire' && available.length === 0;

  return (
    <div className="app">
      <div className="appbar compact">
        <IconButton label="Close" onClick={onExit}>
          <Icons.close size={20} />
        </IconButton>
        <div className="appbar-title">
          <div className="line">Permadeath</div>
          <div className="sub">One secret line. One mistake.</div>
        </div>
        <span style={{ width: 38 }} />
      </div>

      <div className="screen no-nav">
        <div className="section">Play as</div>
        <div className="segmented">
          {(['w', 'b', 'random'] as ColorChoice[]).map((value) => (
            <button
              key={value}
              className={colour === value ? 'active' : ''}
              onClick={() => onChange({ permadeathColor: value })}
            >
              {value === 'w' ? 'White' : value === 'b' ? 'Black' : 'Random'}
            </button>
          ))}
        </div>

        <div className="section">Lines</div>
        <div className="list">
          <button
            className="list-row"
            onClick={() => onChange({ permadeathSource: 'repertoire' })}
          >
            <span className="grow">
              <div className="title">My repertoire</div>
              <div className="meta">
                {available.length === 0
                  ? 'No repertoire for that colour'
                  : `${available.map((r) => r.name.replace(/^\s*(white|black)\s*[—–\-:]\s*/i, '')).join(', ')}`}
              </div>
            </span>
            {kind === 'repertoire' && <Icons.check size={18} />}
          </button>
          <button className="list-row" onClick={() => onChange({ permadeathSource: 'book' })}>
            <span className="grow">
              <div className="title">Book</div>
              <div className="meta">Every line in the reference database</div>
            </span>
            {kind === 'book' && <Icons.check size={18} />}
          </button>
        </div>

        <div className="card" style={{ marginTop: 12 }}>
          <div className="small muted">
            {kind === 'repertoire'
              ? 'A line is drawn from your repertoire. Any move you have prepared from a position counts — the run ends the moment you leave your own prep.'
              : 'Any move played in the reference database keeps you alive, so the book forgives more than your repertoire does. It is a curated sample, not every game ever played.'}
          </div>
        </div>

        <div className="spacer" />
        <button
          className="btn primary block xl"
          disabled={blocked}
          onClick={() => onStart(colour, kind)}
        >
          {blocked ? 'No lines for that colour' : 'Start run'}
        </button>

        {record.runs > 0 && (
          <>
            <div className="section">Record</div>
            <div className="list">
              <Stat label="Best run" value={record.best} />
              <Stat label="Runs" value={record.runs} />
              <Stat label="Lines completed" value={record.survivals} />
            </div>
          </>
        )}
      </div>
    </div>
  );
}
