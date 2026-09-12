import { useEffect, useMemo, useRef, useState } from 'react';
import { Board } from '../components/Board';
import { haptic, IconButton, Icons } from '../components/ui';
import { applySan, type LegalMove, type Square } from '../chess/core';
import { referenceIndex } from '../model/referenceIndex';
import {
  beginRun,
  clockDescription,
  clockLabel,
  clockSpec,
  CLOCK_MODES,
  HINT_BUDGETS,
  isComplete,
  isUsersTurn,
  lineName,
  lineRecords,
  movesHere,
  opponentReply,
  other,
  outcomeOf,
  play,
  playableRepertoires,
  revealText,
  takeHint,
  timeOut,
  weaknessFromCards,
  type ClockMode,
  type ColorChoice,
  type DeathCause,
  type LineSource,
  type PermadeathOptions,
  type PermadeathRecord,
  type Run,
  type SourceKind,
} from '../model/permadeath';
import { mulberry32 } from '../model/session';
import { displayName } from '../model/repertoire';
import type { Repertoire } from '../model/types';
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
  const cards = state.cards;
  const setSettings = useStore((s) => s.setSettings);
  const endRun = useStore((s) => s.endPermadeathRun);
  const missed = useStore((s) => s.missedInPermadeath);
  const record = useStore((s) => s.permadeath);

  const options = useMemo<PermadeathOptions>(
    () => ({
      kind: settings.permadeathSource,
      color: settings.permadeathColor,
      repertoireId: settings.permadeathRepertoire,
      reverse: settings.permadeathReverse,
      weakFirst: settings.permadeathWeakFirst,
      clock: settings.permadeathClock,
      hints: settings.permadeathHints,
    }),
    [settings],
  );

  const [phase, setPhase] = useState<Phase>('setup');
  const [game, setGame] = useState<{ source: LineSource; run: Run } | null>(null);
  const [death, setDeath] = useState<{ cause: DeathCause; played?: string; expected: string[] } | null>(
    null,
  );
  const [thinking, setThinking] = useState(false);
  const [hintSquare, setHintSquare] = useState<Square | null>(null);
  const picker = useRef(mulberry32(Math.floor(Math.random() * 2 ** 31)));
  const settled = useRef(false);

  const source = game?.source ?? null;
  const run = game?.run ?? null;
  const myTurn = run ? isUsersTurn(run) : false;

  /* ── clock ─────────────────────────────────────────────────────────────
   * Only your own thinking is charged, so the opponent's beat is free. A
   * per-move budget is refilled at the start of each of your turns; a per-run
   * budget carries what is left of it from turn to turn.
   */
  const spec = useMemo(() => clockSpec(options.clock), [options.clock]);
  const budget = useRef<number | null>(null);
  const [shown, setShown] = useState<number | null>(null);
  const expire = useRef<() => void>(() => {});

  useEffect(() => {
    if (phase !== 'playing' || !myTurn || thinking || budget.current === null) return;
    if (spec.perMove !== null) budget.current = spec.perMove;
    const from = budget.current;
    const startedAt = Date.now();
    setShown(from);
    const timer = setInterval(() => {
      const left = from - (Date.now() - startedAt) / 1000;
      setShown(Math.max(0, left));
      if (left <= 0) {
        clearInterval(timer);
        expire.current();
      }
    }, 100);
    return () => {
      clearInterval(timer);
      // Charge only the time actually spent on this turn.
      budget.current = Math.max(0, from - (Date.now() - startedAt) / 1000);
    };
  }, [phase, myTurn, thinking, spec.perMove]);

  const finish = (ended: Run, completed: boolean) => {
    settled.current = true;
    endRun(outcomeOf(ended, completed));
  };

  expire.current = () => {
    if (!run || !source || settled.current || phase !== 'playing') return;
    if (settings.hapticFeedback) haptic([22, 60, 22]);
    setDeath({ cause: 'time', expected: movesHere(source, run) });
    setGame({ source, run: timeOut(run) });
    setPhase('dead');
    finish(run, false);
  };

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
      setPhase('survived');
      finish(run, true);
    }
  }, [source, run, phase]);

  /** A hint belongs to one position only. */
  useEffect(() => {
    setHintSquare(null);
  }, [run?.fen]);

  /** The line is named only once the run is over, so nothing leaks mid-run. */
  const named = useMemo(
    () =>
      source && run && phase !== 'playing' && phase !== 'setup'
        ? lineName(referenceIndex(), source, run)
        : null,
    [source, run, phase],
  );

  const lastMove = useMemo(() => {
    if (!run || run.played.length === 0) return null;
    const { fens } = walk(run.played.slice(0, -1));
    const move = applySan(fens[fens.length - 1], run.played[run.played.length - 1]);
    return move ? { from: move.from, to: move.to } : null;
  }, [run]);

  const highlights = useMemo(() => {
    const out: { square: Square; kind: 'good' | 'bad' | 'hint' }[] = [];
    if (phase === 'playing') {
      if (hintSquare) out.push({ square: hintSquare, kind: 'hint' });
      return out;
    }
    if (phase !== 'dead' || !death || !run) return out;
    if (death.played) {
      const wrong = applySan(run.fen, death.played);
      if (wrong) out.push({ square: wrong.from, kind: 'bad' }, { square: wrong.to, kind: 'bad' });
    }
    const right = death.expected[0] ? applySan(run.fen, death.expected[0]) : null;
    if (right) out.push({ square: right.from, kind: 'good' }, { square: right.to, kind: 'good' });
    return out;
  }, [phase, death, run, hintSquare]);

  const start = (next: PermadeathOptions) => {
    const started = beginRun({
      ...next,
      reps,
      index: referenceIndex(),
      weakness: weaknessFromCards(cards),
    });
    if (!started) return;
    settled.current = false;
    setDeath(null);
    setHintSquare(null);
    const fresh = clockSpec(next.clock);
    budget.current = fresh.perRun ?? fresh.perMove;
    setShown(budget.current);
    setGame(started);
    setPhase('playing');
  };

  if (phase === 'setup' || !run || !source) {
    return (
      <Setup
        options={options}
        reps={reps}
        record={record}
        perLine={settings.permadeathPerLine}
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
    setDeath({ cause: 'move', played: result.played, expected: result.expected });
    setGame({ source, run: result.run });
    setPhase('dead');
    finish(run, false);
    // A reversed run is judged on the side you prepared against, so its
    // positions are not decision points and must not touch the schedule.
    if (run.repertoireId && !run.reverse) {
      missed(run.repertoireId, run.fen, result.played, result.expected[0] ?? '');
    }
  };

  const onHint = () => {
    if (phase !== 'playing' || !myTurn || !run.hints) return;
    const taken = takeHint(source, run);
    if (!taken) return;
    if (settings.hapticFeedback) haptic(8);
    setHintSquare(taken.from);
    setGame({ source, run: taken.run });
  };

  const over = phase !== 'playing';
  const survivedLabel = run.survived === 1 ? '1 move' : `${run.survived} moves`;
  const urgent = shown !== null && shown <= 5;

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
        {!over && shown !== null && (
          <span
            className={`chip${urgent ? ' bad' : ''} num`}
            style={{ minWidth: 52, justifyContent: 'center' }}
          >
            {formatClock(shown)}
          </span>
        )}
        <span className="chip" style={{ minWidth: 38, justifyContent: 'center' }}>
          {run.survived}
        </span>
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
          <>
            <div className="prompt">
              <div className="who">
                {thinking ? <span className="spinner" /> : <span className={`side ${run.color}`} />}
                {thinking ? 'Reply' : 'Your move'}
              </div>
              <div className="ctx">
                {hintSquare
                  ? `The move starts on ${hintSquare}`
                  : run.reverse
                    ? 'Play the side your repertoire prepares against'
                    : 'One mistake ends the run'}
              </div>
            </div>
            {run.hints > 0 && (
              <>
                <div className="spacer sm" />
                <button
                  className="btn soft block"
                  disabled={!myTurn || thinking || hintSquare !== null}
                  onClick={onHint}
                >
                  <Icons.bolt size={18} />
                  {hintSquare ? 'Hint spent' : `Hint (${run.hints} left)`}
                </button>
              </>
            )}
          </>
        )}

        {phase === 'survived' && (
          <>
            <div className="verdict ok">
              <span className="ico">
                <Icons.check size={18} />
              </span>
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
              <span className="ico">
                <Icons.cross size={18} />
              </span>
              {death.cause === 'time' ? 'Out of time' : 'Run over'}
            </div>
            <div className="compare" style={{ marginTop: 10 }}>
              <div className="good">
                <div className="k">{run.source === 'book' ? 'Book' : 'Repertoire'}</div>
                <div className="v">{death.expected[0] ?? '—'}</div>
              </div>
              <div className={death.cause === 'time' ? '' : 'bad'}>
                <div className="k">{death.cause === 'time' ? 'You played' : 'You played'}</div>
                <div className="v">{death.played ?? '—'}</div>
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
                    {run.reverse ? 'reversed · ' : ''}
                    {phase === 'survived' ? 'played in full' : `${run.survived} correct`}
                    {run.hintsUsed > 0
                      ? ` · ${run.hintsUsed} hint${run.hintsUsed === 1 ? '' : 's'}`
                      : ''}
                  </div>
                </span>
                {named?.eco && <span className="chip">{named.eco}</span>}
              </div>
              <div className="divider" />
              <div className="movetext">{revealText(source, run)}</div>
            </div>

            <Record record={record} perLine={settings.permadeathPerLine} />

            <div className="spacer" />
            <button className="btn primary block xl" onClick={() => start(options)}>
              New run
            </button>
            <button
              className="btn plain block"
              style={{ marginTop: 8 }}
              onClick={() => setPhase('setup')}
            >
              Change options
            </button>
          </>
        )}
      </div>
    </div>
  );
}

function formatClock(seconds: number): string {
  const whole = Math.ceil(seconds);
  if (whole < 60) return `${whole}s`;
  return `${Math.floor(whole / 60)}:${String(whole % 60).padStart(2, '0')}`;
}

function Stat({ label, value }: { label: string; value: number }) {
  return (
    <div className="list-row">
      <span className="grow">
        <div className="title">{label}</div>
      </span>
      <span className="val num">{value}</span>
    </div>
  );
}

/** The global tally, optionally broken down by opening and side. */
function Record({ record, perLine }: { record: PermadeathRecord; perLine: boolean }) {
  const lines = perLine ? lineRecords(record) : [];
  return (
    <>
      <div className="section">Record</div>
      <div className="list">
        <Stat label="Best run" value={record.best} />
        <Stat label="Runs" value={record.runs} />
        <Stat label="Lines completed" value={record.survivals} />
      </div>
      {perLine && (
        <>
          <div className="section">By opening</div>
          {lines.length === 0 ? (
            <div className="card small muted">
              Nothing yet. Each opening keeps its own best once you have played it.
            </div>
          ) : (
            <div className="list">
              {lines.map((line) => (
                <div className="list-row" key={line.key}>
                  <span className={`side ${line.color}`} />
                  <span className="grow" style={{ minWidth: 0 }}>
                    <div className="title truncate">{line.label}</div>
                    <div className="meta">
                      {line.runs} run{line.runs === 1 ? '' : 's'}
                      {line.survivals > 0 ? ` · ${line.survivals} completed` : ''}
                    </div>
                  </span>
                  <span className="val num">{line.best}</span>
                </div>
              ))}
            </div>
          )}
        </>
      )}
    </>
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

type SettingsPatch = {
  permadeathColor?: ColorChoice;
  permadeathSource?: SourceKind;
  permadeathRepertoire?: string;
  permadeathReverse?: boolean;
  permadeathWeakFirst?: boolean;
  permadeathClock?: ClockMode;
  permadeathHints?: number;
  permadeathPerLine?: boolean;
};

interface SetupProps {
  options: PermadeathOptions;
  reps: Repertoire[];
  record: PermadeathRecord;
  perLine: boolean;
  onChange: (patch: SettingsPatch) => void;
  onStart: (options: PermadeathOptions) => void;
  onExit: () => void;
}

function Setup({ options, reps, record, perLine, onChange, onStart, onExit }: SetupProps) {
  const repertoire = options.kind === 'repertoire';
  const pool = playableRepertoires(reps, options.color, { reverse: options.reverse });
  // A repertoire the colour no longer allows quietly falls back to "any".
  const chosenId = pool.some((r) => r.id === options.repertoireId) ? options.repertoireId : '';
  const effective = { ...options, repertoireId: chosenId };
  const blocked = repertoire && pool.length === 0;

  /** Picking an opening settles which side you are on, so say so. */
  const chooseRepertoire = (rep: Repertoire | null) => {
    if (!rep) {
      onChange({ permadeathRepertoire: '' });
      return;
    }
    onChange({
      permadeathRepertoire: rep.id,
      permadeathColor: options.reverse ? other(rep.color) : rep.color,
    });
  };

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
              className={options.color === value ? 'active' : ''}
              onClick={() => onChange({ permadeathColor: value })}
            >
              {value === 'w' ? 'White' : value === 'b' ? 'Black' : 'Random'}
            </button>
          ))}
        </div>

        <div className="section">Lines</div>
        <div className="list">
          <button className="list-row" onClick={() => onChange({ permadeathSource: 'repertoire' })}>
            <span className="grow" style={{ minWidth: 0 }}>
              <div className="title">My repertoire</div>
              <div className="meta truncate">
                {pool.length > 0
                  ? pool.map((r) => displayName(r.name)).join(', ')
                  : options.reverse
                    ? 'Nothing prepared against that side'
                    : 'No repertoire for that colour'}
              </div>
            </span>
            {repertoire && <Icons.check size={18} />}
          </button>
          <button className="list-row" onClick={() => onChange({ permadeathSource: 'book' })}>
            <span className="grow">
              <div className="title">Book</div>
              <div className="meta">Every line in the reference database</div>
            </span>
            {!repertoire && <Icons.check size={18} />}
          </button>
        </div>

        {repertoire && pool.length > 1 && (
          <>
            <div className="section">Opening</div>
            <div className="list">
              <button className="list-row" onClick={() => chooseRepertoire(null)}>
                <span className="grow">
                  <div className="title">Any of mine</div>
                  <div className="meta">Drawn across every repertoire that fits</div>
                </span>
                {chosenId === '' && <Icons.check size={18} />}
              </button>
              {pool.map((rep) => (
                <button key={rep.id} className="list-row" onClick={() => chooseRepertoire(rep)}>
                  <span className={`side ${options.reverse ? other(rep.color) : rep.color}`} />
                  <span className="grow" style={{ minWidth: 0 }}>
                    <div className="title truncate">{displayName(rep.name)}</div>
                  </span>
                  {chosenId === rep.id && <Icons.check size={18} />}
                </button>
              ))}
            </div>
          </>
        )}

        <div className="section">Clock</div>
        <div className="segmented">
          {CLOCK_MODES.map((mode) => (
            <button
              key={mode}
              className={options.clock === mode ? 'active' : ''}
              onClick={() => onChange({ permadeathClock: mode })}
            >
              {clockLabel(mode)}
            </button>
          ))}
        </div>
        <div className="faint tiny" style={{ margin: '6px 4px 0' }}>
          {clockDescription(options.clock)}
        </div>

        <div className="section">Hints</div>
        <div className="segmented">
          {HINT_BUDGETS.map((n) => (
            <button
              key={n}
              className={options.hints === n ? 'active' : ''}
              onClick={() => onChange({ permadeathHints: n })}
            >
              {n === 0 ? 'None' : `${n} hint${n === 1 ? '' : 's'}`}
            </button>
          ))}
        </div>
        <div className="faint tiny" style={{ margin: '6px 4px 0' }}>
          {options.hints === 0
            ? 'No help. The position is the whole question.'
            : 'A hint shows the square the move starts from — never where it lands.'}
        </div>

        <div className="section">Extras</div>
        <div className="list">
          {repertoire && (
            <>
              <Toggle
                label="Target weak spots"
                hint="Draw lines you get wrong or have let lapse more often"
                on={options.weakFirst}
                onToggle={() => onChange({ permadeathWeakFirst: !options.weakFirst })}
              />
              <Toggle
                label="Play the other side"
                hint="Sit on the side your repertoire prepares against"
                on={options.reverse}
                onToggle={() =>
                  onChange({ permadeathReverse: !options.reverse, permadeathRepertoire: '' })
                }
              />
            </>
          )}
          <Toggle
            label="Per-opening records"
            hint="Keep a separate best for each opening and side"
            on={perLine}
            onToggle={() => onChange({ permadeathPerLine: !perLine })}
          />
        </div>

        <div className="card" style={{ marginTop: 12 }}>
          <div className="small muted">
            {!repertoire
              ? 'Any move played in the reference database keeps you alive, so the book forgives more than your repertoire does. It is a curated sample, not every game ever played.'
              : options.reverse
                ? 'You play the side your repertoire answers. Staying alive means knowing what your opponent is meant to do — the run ends on any move you have not prepared for.'
                : 'A line is drawn from your repertoire. Any move you have prepared from a position counts — the run ends the moment you leave your own prep.'}
          </div>
        </div>

        <div className="spacer" />
        <button className="btn primary block xl" disabled={blocked} onClick={() => onStart(effective)}>
          {!blocked ? 'Start run' : options.reverse ? 'Nothing to play against' : 'No lines for that colour'}
        </button>

        {record.runs > 0 && <Record record={record} perLine={perLine} />}
      </div>
    </div>
  );
}

function Toggle({
  label,
  hint,
  on,
  onToggle,
}: {
  label: string;
  hint?: string;
  on: boolean;
  onToggle: () => void;
}) {
  return (
    <button className="list-row" onClick={onToggle}>
      <span className="grow" style={{ minWidth: 0 }}>
        <div className="title">{label}</div>
        {hint && <div className="meta">{hint}</div>}
      </span>
      <span className={`switch${on ? ' on' : ''}`}>
        <i />
      </span>
    </button>
  );
}
