import { useEffect, useMemo, useRef, useState } from 'react';
import { Board } from '../../components/Board';
import { AppBar, haptic, Icons, Strip, type StripItem } from '../../components/ui';
import { ClockHud, useMoveClock } from '../../components/Clock';
import { selectionText } from '../../components/Selection';
import { applySan, positionKey, walkSan, type LegalMove, type Square } from '../../chess/core';
import { DEFAULT_DRILL, type DrillPrefs } from '../../model/modes';
import { clockSeconds } from '../../model/openingRun';
import { nodeById, openingTree } from '../../model/openingTree';
import { referenceIndex } from '../../model/referenceIndex';
import { drawLines, LINE_BUDGET, MAX_LINES, yoursAt, type DrillLine, type LineLean } from '../../model/lineDrill';
import { mulberry32, type TrainingItem } from '../../model/session';
import {
  answer as answerLine,
  beginLines,
  carryOn,
  expectedHere,
  graded as markGraded,
  lineDone,
  needsDraw,
  nextLine,
  regrade,
  theirMove,
  yourMove,
  type LineDrillState,
  type LineStep,
} from '../../model/lineDrillController';
import type { Grade } from '../../model/types';
import type { Color } from '../../chess/core';
import { itemsFor, repertoireList, useStore } from '../../store/useStore';
import { GRADE_LABELS, WhySheet } from './DrillSession';
import { introOpening, useRoundIntro } from '../../components/RoundIntro';
import { env } from '../../model/env';

/** How long a correct move stays on the board before the line goes on. */
const FLASH_MS = 500;
/** How long the opponent takes over their move. */
const REPLY_MS = 450;
/** Lines drawn at a time in a sitting with no end. */
const BATCH = 5;

export interface LineDrillProps {
  /** The side, and the opening the lines are drawn inside. */
  color: Color;
  openingId: string;
  /** Lines in the sitting; a sitting from Drill's own setup draws for as long as you want. */
  count?: number;
  /** The most of your own moves across the sitting's lines — see `drawLines`. */
  budget?: number;
  /** Your lines by how often you would meet them, or your weakest. */
  lean: LineLean;
  /** Tip ids to hold the draw to, when any of them are in reach. */
  only?: Set<string> | null;
  prefs?: Partial<DrillPrefs>;
  onExit: () => void;
  /** Autopilot's next round, offered once the sitting's lines are done. */
  onNext?: () => void;
}

/**
 * Drill, a line at a time.
 *
 * Each line is played from move one: the opponent's moves are played for you,
 * and each of yours is asked. A correct answer is timed and the line goes on.
 * A miss shows your prep's move beside the one you played, with Why? to see
 * it refuted, and Continue plays your prep's move and carries on
 * — a slip early in a line still leaves the rest of it to practise. Playing
 * another move your prep has is right, and the line follows that move
 * instead.
 *
 * At the end of the line there is one grade for the whole of it, and it goes
 * to the line's own card — position cards are Drill positions' alone. It is
 * given for you from the clock (Guessed after any miss, otherwise the average
 * time of your correct moves, on Drill positions' scale) and shown selected;
 * tapping another grade changes it. A line with no miss is a clean finish.
 * Nothing here moves a rating.
 *
 * With Batch similar lines on, lines come in groups that share most of their
 * moves, sized by `LINE_BUDGET`; a sitting from Drill's own setup plays a
 * group, then starts the next one somewhere else.
 */
export function LineDrill({ color, openingId, count, budget, lean, only, prefs, onExit, onNext }: LineDrillProps) {
  const options: DrillPrefs = { ...DEFAULT_DRILL, ...prefs };
  const state = useStore();
  const settings = state.settings;
  const gradeLine = useStore((s) => s.gradeLine);
  const clearMistake = useStore((s) => s.clearMistake);
  const logMistake = useStore((s) => s.logMistake);
  const recordMove = useStore((s) => s.recordMove);
  const endRound = useStore((s) => s.endRound);
  const tree = openingTree(referenceIndex());
  const region = nodeById(tree, openingId);
  const [rand] = useState(() => ({ current: mulberry32(Math.floor(env.random() * 2 ** 31)) }));

  const grouped = options.batchSimilar;

  const draw = (avoid?: Set<string>): DrillLine[] => {
    const now = useStore.getState();
    const rep = repertoireList(now).find((r) => r.color === color);
    if (!rep) return [];
    return drawLines({
      rep,
      tree,
      region,
      index: referenceIndex(),
      lean,
      cards: now.lineCards,
      draw: options.draw,
      only,
      avoid,
      count: count ?? (grouped ? MAX_LINES : BATCH),
      budget: budget ?? (grouped ? LINE_BUDGET : undefined),
      similar: grouped,
      rand: rand.current,
    });
  };

  /** The sitting, as the controller has it. The ref is always the latest, for timers. */
  const [lines, setLines] = useState<LineDrillState>(() => beginLines(draw()));
  const linesRef = useRef(lines);
  const update = (next: LineDrillState) => {
    if (next === linesRef.current) return;
    linesRef.current = next;
    setLines(next);
  };
  const { batch, group, at, line, ply, phase, played, misses, times, graded: gradedLine, finished } = lines;
  const [why, setWhy] = useState(false);

  const rep = line ? state.repertoires[line.repertoireId] : undefined;
  const fens = useMemo(() => (line ? walkSan(line.sans).fens : []), [line]);
  const fen = fens[ply] ?? fens[fens.length - 1] ?? '';
  const mine = yourMove(lines, color);

  /** The sitting is announced, and the opening stays over the board until your first move. */
  const [sitting] = useState(() => env.random());
  const intro = useRoundIntro(
    line
      ? {
          key: sitting,
          mode: 'Drill lines',
          opening: region.depth > 0 ? openingId : introOpening(openingId, line.sans),
          color,
          path: [],
        }
      : null,
    finished > 0 || times.length > 0 || misses > 0,
  );

  /** Your prep at the position in front of you, as Drill's item for it. */
  const item = useMemo<TrainingItem | null>(() => {
    if (!rep || !mine) return null;
    const key = positionKey(fen);
    return itemsFor(rep).find((candidate) => candidate.key === key) ?? null;
  }, [rep, mine, fen]);

  const clock = useMoveClock({
    seconds: clockSeconds(options.clock),
    turnKey: `${at}:${ply}`,
    active: phase === 'play' && mine && !why && !intro.held,
  });

  /** Do what the controller asks, in order. */
  const run = ({ state: next, effects }: LineStep) => {
    update(next);
    for (const effect of effects) {
      switch (effect.kind) {
        case 'record':
          recordMove({ mode: 'drill', line: effect.line, color, correct: effect.correct, rated: false });
          break;
        case 'buzz':
          buzz(effect.pattern);
          break;
        case 'clearMistake':
          clearMistake(effect.id);
          break;
        case 'mistake':
          logMistake(effect.mistake);
          break;
        case 'flash':
          window.setTimeout(() => update(carryOn(linesRef.current)), FLASH_MS);
          break;
        case 'round':
          endRound(effect.round);
          break;
        case 'gradeLine': {
          const before = gradeLine(effect.repertoireId, effect.tipId, effect.grade, effect.before);
          if (!effect.before) update(markGraded(linesRef.current, before, effect.grade));
          break;
        }
      }
    }
  };

  /** The opponent's moves play themselves, after a beat. */
  useEffect(() => {
    if (!line || phase !== 'play' || mine || ply >= line.sans.length || intro.held) return;
    const timer = window.setTimeout(() => update(theirMove(linesRef.current, color)), REPLY_MS);
    return () => window.clearTimeout(timer);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [line, phase, mine, ply, intro.held]);

  /** The end of the line: counted once, as a round of its own. */
  useEffect(() => {
    run(lineDone(linesRef.current, color, tree, region));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [line, phase, ply]);

  const buzz = (pattern: number | number[]) => {
    if (settings.hapticFeedback) haptic(pattern);
  };

  const expected = expectedHere(lines, color);
  const expectedMove = useMemo(() => (expected ? applySan(fen, expected) : null), [expected, fen]);

  const onBoardMove = (move: LegalMove) => {
    if (!rep) return;
    run(answerLine(linesRef.current, color, move, clock.elapsedNow(), rep, item, state.mistakes.map((m) => m.id)));
  };

  /** After a miss: your prep's move is played, and the line goes on. */
  const carryOnAfterMiss = () => {
    setWhy(false);
    update(carryOn(linesRef.current));
  };

  /** Change the line's grade: its card goes back to before and takes the new one. */
  const regradeLine = (value: Grade) => run(regrade(linesRef.current, value));

  const lastOfRound = count !== undefined && at + 1 >= batch.length;

  const nextLine_ = () => {
    const now = linesRef.current;
    update(nextLine(now, needsDraw(now) ? draw(grouped ? new Set(now.batch.map((done) => done.tipId)) : undefined) : undefined));
  };

  const highlights = useMemo(() => {
    const out: { square: Square; kind: 'good' | 'bad' }[] = [];
    if (phase === 'wrong' && played) {
      out.push({ square: played.from, kind: 'bad' }, { square: played.to, kind: 'bad' });
      if (expectedMove) out.push({ square: expectedMove.from, kind: 'good' }, { square: expectedMove.to, kind: 'good' });
    }
    if (phase === 'flash' && played) out.push({ square: played.from, kind: 'good' }, { square: played.to, kind: 'good' });
    return out;
  }, [phase, played, expectedMove]);

  const strip = useMemo<StripItem[]>(() => {
    if (!line) return [];
    return line.sans.slice(0, ply).map((san, i) => ({
      san,
      label: i % 2 === 0 ? `${i / 2 + 1}.` : undefined,
      tone: yoursAt(color, i) ? 'mine' : 'theirs',
    }));
  }, [line, ply, color]);

  const subtitle = selectionText(color, openingId);

  if (!line) {
    return (
      <>
        <AppBar title="Drill lines" subtitle={subtitle} onClose={onExit} />
        <div className="screen no-nav">
          <div className="empty">
            <div className="t">No lines to drill here</div>
            <div className="h">Build a line in Growth.</div>
          </div>
          {onNext && (
            <button className="btn primary block xl" onClick={onNext}>
              Next round
              <Icons.next size={18} />
            </button>
          )}
        </div>
      </>
    );
  }

  const boardFen = phase === 'flash' && played ? played.after : fen;

  return (
    <>
      {intro.cover}
      <AppBar
        title="Drill lines"
        subtitle={subtitle}
        onClose={onExit}
        actions={
          <span className="row gap-6">
            {phase === 'play' && mine && <ClockHud clock={clock} />}
            <span className="chip num wide">
              {count !== undefined ? `${Math.min(at + 1, batch.length)}/${batch.length}` : finished}
            </span>
          </span>
        }
      />

      <div className="screen no-nav">
        <Board
          fen={boardFen}
          orientation={color}
          interactive={phase === 'play' && mine && !intro.held}
          movableFor={color}
          onMove={onBoardMove}
          highlights={highlights}
          overlay={intro.overlay}
          showCoordinates={settings.showCoordinates}
          theme={settings.boardTheme}
          dimmed={phase === 'wrong'}
          captured
        />

        {phase === 'done' && (
          <div className="next-row">
            <button className="btn primary block" onClick={lastOfRound && onNext ? onNext : nextLine_}>
              {lastOfRound && onNext ? 'Next round' : 'Next line'}
              <Icons.next size={18} />
            </button>
          </div>
        )}

        <div className="spacer sm" />
        {strip.length > 0 && <Strip items={strip} />}
        <div className="spacer sm" />

        {phase !== 'done' && phase !== 'wrong' && (
          <div className="prompt">
            <div className="who">
              <span className={`side ${mine ? color : color === 'w' ? 'b' : 'w'}`} />
              {mine ? 'Your move' : 'Their move'}
            </div>
            <div className="ctx">
              {count === undefined && grouped
                ? `${group > 1 && at === 0 ? 'New group' : `Group ${group}`} · line ${at + 1} of ${batch.length}`
                : `Line ${count !== undefined ? `${at + 1} of ${batch.length}` : finished + 1}`}
              {misses > 0 ? ` · ${misses} miss${misses === 1 ? '' : 'es'}` : ''}
            </div>
          </div>
        )}

        {phase === 'wrong' && (
          <>
            <div className="row between">
              <div className="verdict no" style={{ padding: 0 }}>
                <span className="ico">
                  <Icons.cross size={14} />
                </span>
                Off your prep
              </div>
              <button className="btn primary sm" onClick={carryOnAfterMiss}>
                Continue
                <Icons.next size={16} />
              </button>
            </div>
            <div className="compare mt-8">
              <div className="good">
                <div className="k">Playbook</div>
                <div className="v">{expected}</div>
              </div>
              <div className="bad">
                <div className="k">Played</div>
                <div className="v">{played?.san}</div>
              </div>
            </div>
            {options.explain && (
              <button className="btn soft block mt-8" onClick={() => setWhy(true)}>
                Why?
              </button>
            )}
          </>
        )}

        {phase === 'done' && (
          <>
            <div className={`verdict ${misses === 0 ? 'ok' : 'warn'}`} style={{ padding: 0 }}>
              <span className="ico">{misses === 0 ? <Icons.check size={16} /> : <Icons.warn size={16} />}</span>
              {misses === 0 ? 'Line finished clean' : `Line finished · ${misses} miss${misses === 1 ? '' : 'es'}`}
            </div>
            {gradedLine && (
              <>
                <div className="note center mt-12">How did that line feel?</div>
                <div className="grades sm mt-8">
                  {(['again', 'hard', 'good', 'easy'] as Grade[]).map((g) => (
                    <button
                      key={g}
                      className={`${g}${gradedLine.grade === g ? ' selected' : ''}`}
                      aria-pressed={gradedLine.grade === g}
                      onClick={() => regradeLine(g)}
                    >
                      {GRADE_LABELS[g]}
                    </button>
                  ))}
                </div>
              </>
            )}
          </>
        )}
      </div>

      {played && expected && phase === 'wrong' && (
        <WhySheet
          open={why}
          onClose={() => setWhy(false)}
          fen={fen}
          side={color}
          played={played}
          expected={expectedMove}
          expectedSan={expected}
          theme={settings.boardTheme}
          showCoordinates={settings.showCoordinates}
        />
      )}
    </>
  );
}
