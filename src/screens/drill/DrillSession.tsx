import { useEffect, useMemo, useRef, useState } from 'react';
import { Board } from '../../components/Board';
import { ExplorerPanel } from '../../components/ExplorerPanel';
import { AppBar, haptic, Icons, Sheet, Strip, type StripItem } from '../../components/ui';
import {
  applySan,
  fenTurn,
  fullmoveNumber,
  sansToMoveText,
  walkSan,
  type Color,
  type LegalMove,
  type Square,
} from '../../chess/core';
import type { BoardTheme } from '../../components/Board';
import { formatScore } from '../../engine/types';
import { useEngine } from '../../engine/useEngine';
import { checkAnswer, mulberry32, type SessionMode, type TrainingItem } from '../../model/session';
import {
  advance,
  answer as answerWith,
  beginDrill,
  continueAfterWrong,
  drillRound,
  expectedSan,
  followUpFor,
  refill,
  regradeLast,
  type DrillOptions,
  type DrillState,
  type DrillStep,
} from '../../model/drillController';
import { DEFAULT_DRILL, type DrillPrefs } from '../../model/modes';
import { clockSeconds } from '../../model/openingRun';
import type { Grade } from '../../model/types';
import { useStore } from '../../store/useStore';
import { ClockHud, useMoveClock } from '../../components/Clock';
import { introOpening, useRoundIntro } from '../../components/RoundIntro';
import { selectionText } from '../../components/Selection';

export interface DrillSessionProps {
  /** Everything in scope. The session draws from this for as long as you want. */
  items: TrainingItem[];
  mode: SessionMode;
  title: string;
  /** The mode's own options. Sessions launched from a repertoire use defaults. */
  prefs?: Partial<DrillPrefs>;
  /** The opening the round is credited to; the selection's by default. */
  openingId?: string;
  onExit: () => void;
  /** Autopilot's round: this many answers, then Next round. */
  limit?: number;
  onNext?: () => void;
}

/** How long a correct move stays on the board before the next position. */
const FLASH_MS = 650;

/**
 * What each button says.
 *
 * The stored grades are Anki's, but "again" and "good" are the names of buttons
 * in a spaced-repetition app, not descriptions of what just happened in your
 * head. These are: you didn't really know it, you got there, you knew it, it
 * was instant.
 */
export const GRADE_LABELS: Record<Grade, string> = {
  again: 'Guessed',
  hard: 'Hard',
  good: 'Knew it',
  easy: 'Easy',
};

export function DrillSession({
  items,
  mode,
  title,
  prefs,
  openingId,
  onExit,
  limit,
  onNext,
}: DrillSessionProps) {
  const options: DrillPrefs = { ...DEFAULT_DRILL, ...prefs };
  const settings = useStore((s) => s.settings);
  const cards = useStore((s) => s.cards);
  const repertoires = useStore((s) => s.repertoires);
  const grade = useStore((s) => s.grade);
  const regrade = useStore((s) => s.regrade);
  const ensureCard = useStore((s) => s.ensureCard);
  const logMistake = useStore((s) => s.logMistake);
  const recordMove = useStore((s) => s.recordMove);
  const endRound = useStore((s) => s.endRound);

  const maxNew = options.newPerSession;
  const weakFirst = options.weakFirst;
  const [shuffler] = useState(() => ({ current: mulberry32(Math.floor(Math.random() * 2 ** 31)) }));
  const drillOpts: DrillOptions = { mode, maxNew, weakFirst };
  /** The sitting, as the controller has it. The ref is always the latest, for the flash's timer. */
  const [drill, setDrill] = useState<DrillState>(() => beginDrill(items, cards, drillOpts, Date.now()));
  const drillRef = useRef(drill);
  const update = (next: DrillState) => {
    if (next === drillRef.current) return;
    drillRef.current = next;
    setDrill(next);
  };
  const { queue, index, phase, played, stats, last } = drill;
  const [revealLine, setRevealLine] = useState(false);
  const [showMoves, setShowMoves] = useState(false);
  const [explore, setExplore] = useState(false);
  const [why, setWhy] = useState(false);
  /** Logged once, however the session ends. */
  const logged = useRef(false);

  const item = queue[index];

  /** The sitting is announced, and the way to its first position is played out. */
  const [first] = useState(() => queue[0] ?? null);
  const intro = useRoundIntro(
    first
      ? {
          key: first.cardId,
          mode: 'Drill positions',
          opening: introOpening(openingId ?? settings.selection.opening, first.pathSans),
          color: first.orientation === 'black' ? 'b' : 'w',
          path: first.pathSans,
        }
      : null,
    stats.answered > 0,
  );
  /** Autopilot's round has had its answers; what is left is the last grade and Next round. */
  const roundDone = !!limit && stats.answered >= limit && phase === 'ask';

  const clock = useMoveClock({
    seconds: clockSeconds(options.clock),
    turnKey: `${index}:${item?.cardId ?? ''}`,
    active: phase === 'ask' && !!item && !explore && !showMoves && !roundDone && !intro.held,
  });

  /** Count the session as one round, against the opening it was played in. */
  const log = () => {
    if (logged.current) return;
    const round = drillRound(drillRef.current, openingId ?? settings.selection.opening);
    if (!round) return;
    logged.current = true;
    endRound(round);
  };

  const card = item ? cards[item.cardId] : undefined;
  /** True once the schedule is clear and this is practice, not a review. */
  const extra = !!card && card.stage === 'review' && card.due > Date.now();

  /**
   * Keep the queue stocked. Scheduled work first; when the schedule is clear,
   * the stalest positions, so the session only ends when you end it.
   */
  useEffect(() => {
    update(refill(drillRef.current, items, cards, drillOpts, shuffler.current, Date.now()));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [items, cards, mode, maxNew, weakFirst, index, queue.length]);

  useEffect(() => {
    if (item) ensureCard(item);
  }, [item, ensureCard]);

  useEffect(() => {
    if (roundDone) log();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [roundDone]);

  const answer = useMemo(() => (item && played ? checkAnswer(item, played.san) : null), [item, played]);

  const expectedMove = useMemo(() => {
    if (!item) return null;
    const san = expectedSan(item);
    return san ? applySan(item.fen, san) : null;
  }, [item]);

  /** The next decision point down this line, when following the line through. */
  const followUp = useMemo(
    () => (item && options.followLine ? followUpFor(item, items, repertoires[item.repertoireId]) : null),
    [item, items, repertoires, options.followLine],
  );

  /** Do what the controller asks, in order. */
  const run = ({ state: next, effects }: DrillStep) => {
    update(next);
    for (const effect of effects) {
      switch (effect.kind) {
        case 'record':
          recordMove({ mode: 'drill', line: effect.line, color: effect.color, correct: effect.correct, rated: false });
          break;
        case 'buzz':
          if (settings.hapticFeedback) haptic(effect.pattern);
          break;
        case 'grade':
          grade(effect.item, effect.grade, effect.played, effect.correct);
          break;
        case 'regrade':
          regrade(effect.item, effect.before, effect.grade, effect.played);
          break;
        case 'mistake':
          logMistake(effect.mistake);
          break;
        case 'flash':
          // A beat on the move you just made, so it registers before the board
          // changes under you.
          window.setTimeout(() => next_(effect.next ?? undefined), FLASH_MS);
          break;
      }
    }
  };

  const onBoardMove = (move: LegalMove) => {
    if (!item || phase !== 'ask') return;
    run(answerWith(drillRef.current, move, clock.elapsedNow(), card, followUp));
  };

  /** On to the next position, with the board's extras put away. */
  const next_ = (extra?: TrainingItem) => {
    setRevealLine(false);
    setShowMoves(false);
    update(advance(drillRef.current, extra));
  };

  /** End the session: log what was answered, if anything, and leave. */
  const stop = () => {
    log();
    onExit();
  };

  /** Change the grade of the last correct answer. Guessed also brings it back soon. */
  const onRegrade = (value: Grade) => run(regradeLast(drillRef.current, value));

  const highlights = useMemo(() => {
    const out: { square: Square; kind: 'good' | 'bad' | 'hint' }[] = [];
    if (phase === 'wrong' && played) {
      // Green after red, so a square both moves share reads as the right one:
      // the map keeps the last kind written for a square.
      out.push({ square: played.from, kind: 'bad' }, { square: played.to, kind: 'bad' });
      if (expectedMove) {
        out.push({ square: expectedMove.from, kind: 'good' }, { square: expectedMove.to, kind: 'good' });
      }
    }
    if (phase === 'flash' && played) {
      out.push({ square: played.from, kind: 'good' }, { square: played.to, kind: 'good' });
    }
    return out;
  }, [phase, played, expectedMove]);

  const boardFen = useMemo(() => {
    if (phase === 'ask' || !played) return item?.fen ?? '';
    if (phase === 'wrong' && !revealLine) return item?.fen ?? '';
    if (phase === 'wrong' && revealLine && expectedMove) return expectedMove.after;
    return played.after;
  }, [phase, played, revealLine, expectedMove, item]);

  if (!item) return null;

  const side = item.orientation === 'white' ? 'w' : 'b';
  const sideLabel = side === 'w' ? 'White' : 'Black';
  const alternatives = item.expected.filter((e) => !e.preferred).map((e) => e.san);

  return (
    <>
      {intro.cover}
      <AppBar
        title={title}
        subtitle={selectionText(side, openingId ?? settings.selection.opening)}
        onClose={stop}
        actions={
          <span className="row gap-6">
            {phase === 'ask' && <ClockHud clock={clock} />}
            <span className="chip num wide">{stats.answered}</span>
          </span>
        }
      />

      <div className="screen no-nav">
        <Board
          fen={intro.fen ?? boardFen}
          orientation={side}
          interactive={phase === 'ask' && !roundDone && !intro.held}
          movableFor={side}
          onMove={onBoardMove}
          highlights={intro.held ? [] : highlights}
          lastMove={intro.lastMove}
          overlay={intro.overlay}
          showCoordinates={settings.showCoordinates}
          theme={settings.boardTheme}
          dimmed={phase === 'wrong'}
          captured
        />

        {intro.below}

        <div className="spacer" />

        {phase === 'ask' && (
          <>
            {roundDone ? (
              <div className="verdict ok" style={{ padding: 0 }}>
                <span className="ico">
                  <Icons.check size={16} />
                </span>
                {stats.correct} of {stats.answered} right
              </div>
            ) : (
              <div className="prompt" style={intro.held ? { visibility: 'hidden' } : undefined}>
                <div className="who">
                  <span className={`side ${side}`} />
                  {sideLabel} to move
                </div>
                <div className="ctx">
                  Move {Math.floor(item.pathSans.length / 2) + 1}
                  {item.expected.length > 1 ? ` · ${item.expected.length} options` : ''}
                  {extra ? ' · extra practice' : ''}
                </div>
              </div>
            )}
            {last && (
              <>
                <div className="spacer sm" />
                <div className="note center">Last move{last.item.expected[0] ? ` · ${last.played}` : ''}</div>
                <div className="grades sm mt-8">
                  {(['again', 'hard', 'good', 'easy'] as Grade[]).map((g) => (
                    <button
                      key={g}
                      className={`${g}${last.grade === g ? ' selected' : ''}`}
                      aria-pressed={last.grade === g}
                      onClick={() => onRegrade(g)}
                    >
                      {GRADE_LABELS[g]}
                    </button>
                  ))}
                </div>
              </>
            )}
            {roundDone && onNext && (
              <button className="btn primary block mt-12" onClick={onNext}>
                Next round
                <Icons.next size={18} />
              </button>
            )}
            <div className="spacer" />
            {!roundDone && (
              <div className="row gap-8">
                <button className="btn soft grow" onClick={() => setShowMoves((v) => !v)}>
                  {showMoves ? 'Hide moves' : 'Moves'}
                </button>
                <button className="btn soft grow" onClick={() => setExplore(true)}>
                  Explore
                </button>
                <button className="btn soft grow" onClick={stop}>
                  Stop
                </button>
              </div>
            )}
            {showMoves && (
              <div className="card movetext mt-8">{sansToMoveText(item.pathSans) || 'Start'}</div>
            )}
          </>
        )}

        {phase === 'wrong' && (
          <>
            <div className="row between">
              <div className="verdict no" style={{ padding: 0 }}>
                <span className="ico"><Icons.cross size={14} /></span>
                Wrong
              </div>
              <button
                className="btn primary sm"
                onClick={() => {
                  setRevealLine(false);
                  setShowMoves(false);
                  update(continueAfterWrong(drillRef.current));
                }}
              >
                Continue
                <Icons.next size={16} />
              </button>
            </div>
            <div className="compare mt-8">
              <div className="good">
                <div className="k">Playbook</div>
                <div className="v">{answer?.preferred?.san}</div>
              </div>
              <div className="bad">
                <div className="k">Played</div>
                <div className="v">{played?.san}</div>
              </div>
            </div>
            <div className="spacer" />
            <div className="row gap-8">
              {options.explain && (
                <button className="btn soft grow" onClick={() => setWhy(true)}>
                  Why?
                </button>
              )}
              <button className="btn soft grow" onClick={() => setRevealLine((v) => !v)}>
                {revealLine ? 'Hide line' : 'Show line'}
              </button>
              <button className="btn soft grow" onClick={() => setExplore(true)}>
                Explore
              </button>
            </div>

            {revealLine && (
              <div className="card movetext mt-16">{sansToMoveText(item.continuation, item.fen)}</div>
            )}
            {(alternatives.length > 0 || answer?.preferred?.note) && (
              <div className="card small muted mt-8">
                {answer?.preferred?.note}
                {alternatives.length > 0 && (
                  <div className={answer?.preferred?.note ? 'mt-8 faint' : 'faint'}>
                    Also {alternatives.join(', ')}
                  </div>
                )}
              </div>
            )}
          </>
        )}
      </div>

      {played && (
        <WhySheet
          open={why}
          onClose={() => setWhy(false)}
          fen={item.fen}
          side={side}
          played={played}
          expected={expectedMove}
          expectedSan={answer?.preferred?.san}
          theme={settings.boardTheme}
          showCoordinates={settings.showCoordinates}
        />
      )}

      <Sheet open={explore} onClose={() => setExplore(false)} title="Reference">
        <div className="movetext" style={{ marginBottom: 10 }}>
          {sansToMoveText(item.pathSans) || 'Start'}
        </div>
        <ExplorerPanel
          fen={item.fen}
          path={item.pathSans}
          inRepertoire={item.expected.map((e) => e.san)}
          onPlay={() => setExplore(false)}
        />
      </Sheet>
    </>
  );
}

/* ── why a move is wrong ────────────────────────────────────────────────── */

interface Verdict {
  cp: number | null;
  mate: number | null;
  /** The engine's continuation from the position, in SAN. */
  sans: string[];
  /** Captured with the result: the live snapshot is cleared once it is done. */
  depth: number;
}

/**
 * What happens after a wrong move.
 *
 * "It isn't in your repertoire" is a fact, not a reason. The engine plays the
 * position on from the move you made and shows the reply that punishes it,
 * beside what the prepared move would have been worth — so the answer to "why"
 * is a line you can step through rather than a verdict.
 */
export function WhySheet({
  open,
  onClose,
  fen,
  side,
  played,
  expected,
  expectedSan,
  theme,
  showCoordinates,
}: {
  open: boolean;
  onClose: () => void;
  /** The position that was asked about. */
  fen: string;
  side: Color;
  played: LegalMove;
  expected: LegalMove | null;
  expectedSan?: string;
  theme: BoardTheme;
  showCoordinates: boolean;
}) {
  const [found, setFound] = useState<{ played?: Verdict; best?: Verdict }>({});
  const [cursor, setCursor] = useState(1);

  // One search at a time: the move you played first, so there is something to
  // read while the prepared move is still being weighed.
  const probe = !open
    ? null
    : !found.played
      ? played.after
      : expected && !found.best
        ? expected.after
        : null;

  const { snapshot, sanLines, backend } = useEngine(probe, {
    enabled: open,
    movetime: 1500,
    multiPv: 1,
    debounceMs: 80,
  });

  useEffect(() => {
    if (!open) return;
    setFound({});
    setCursor(1);
  }, [open, fen, played.san]);

  useEffect(() => {
    if (!open || !probe || snapshot.thinking || snapshot.fen !== probe) return;
    const line = sanLines[0];
    if (!line || (line.cp === null && line.mate === null)) return;
    const verdict: Verdict = {
      cp: line.cp,
      mate: line.mate,
      sans: line.sans,
      depth: line.depth || snapshot.depth,
    };
    setFound((current) =>
      probe === played.after ? { ...current, played: verdict } : { ...current, best: verdict },
    );
  }, [open, probe, snapshot, sanLines, played.after]);

  /**
   * Your move, then how the engine says it gets punished — five moves a side,
   * which is enough to see an idea through rather than just the first hit.
   */
  const line = useMemo(
    () => (found.played ? [played.san, ...found.played.sans.slice(0, 9)] : [played.san]),
    [found.played, played.san],
  );
  const fens = useMemo(() => walkSan(line, fen).fens, [line, fen]);
  const at = Math.min(cursor, fens.length - 1);
  const lastMove = at > 0 ? applySan(fens[at - 1], line[at - 1]) : null;

  /** Scores read from the side that was to move, not from White's. */
  const score = (v?: Verdict) =>
    !v
      ? null
      : formatScore({
          cp: v.cp === null ? null : side === 'w' ? v.cp : -v.cp,
          mate: v.mate === null ? null : side === 'w' ? v.mate : -v.mate,
        });

  const items: StripItem[] = line.map((san, i) => ({
    san,
    label: fenTurn(fens[i]) === 'w' ? `${fullmoveNumber(fens[i])}.` : undefined,
    tone: i === 0 ? 'bad' : 'ghost',
    current: at === i + 1,
    seek: i + 1,
  }));

  return (
    <Sheet open={open} onClose={onClose} title={`Why not ${played.san}?`}>
      <div className="compare">
        <div className="bad">
          <div className="k">{played.san}</div>
          <div className="v">{score(found.played) ?? '…'}</div>
        </div>
        <div className="good">
          <div className="k">{expectedSan ?? 'Playbook'}</div>
          <div className="v">{expected ? (score(found.best) ?? '…') : '—'}</div>
        </div>
      </div>

      <div className="spacer sm" />
      <Board
        fen={fens[at]}
        orientation={side}
        interactive={false}
        lastMove={lastMove ? { from: lastMove.from, to: lastMove.to } : null}
        showCoordinates={showCoordinates}
        theme={theme}
      />
      <div className="spacer sm" />
      <Strip items={items} cursor={at} max={line.length} onSeek={setCursor} />

      {/* Only what the strip cannot say for itself: that it is still coming, or
          that there is nothing to come. */}
      {(!found.played || found.played.sans.length === 0) && (
        <div className="center faint tiny" style={{ marginTop: 8 }}>
          {!found.played
            ? 'Playing it out…'
            : 'The engine finds nothing forced here — this one is a matter of plan, not tactics.'}
        </div>
      )}
      {found.played && (
        <div className="center faint tiny" style={{ marginTop: 6 }}>
          {backend === 'stockfish' ? 'Stockfish' : 'Rough estimate'} at depth{' '}
          {found.played.depth || '?'}, from the position after each move.
        </div>
      )}
    </Sheet>
  );
}
