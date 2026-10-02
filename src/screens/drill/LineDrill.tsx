import { useEffect, useMemo, useRef, useState } from 'react';
import { Board } from '../../components/Board';
import { AppBar, haptic, Icons, Strip, type StripItem } from '../../components/ui';
import { ClockHud, useMoveClock } from '../../components/Clock';
import { selectionText } from '../../components/Selection';
import { applySan, positionKey, walkSan, type LegalMove, type Square } from '../../chess/core';
import { DEFAULT_DRILL, type DrillPrefs } from '../../model/modes';
import { clockSeconds, weaknessFromCards } from '../../model/openingRun';
import { deepestNodeWithin, nodeById, openingTree } from '../../model/openingTree';
import { referenceIndex } from '../../model/referenceIndex';
import { continueLine, drawLines, yoursAt, type DrillLine, type LineLean } from '../../model/lineDrill';
import { checkAnswer, mulberry32, type TrainingItem } from '../../model/session';
import { createCard, gradeForTime } from '../../model/srs';
import type { Card, Grade } from '../../model/types';
import type { Color } from '../../chess/core';
import { evidenceIn, withSelection } from '../../store/recommendation';
import { itemsFor, repertoireList, useStore } from '../../store/useStore';
import { GRADE_LABELS, WhySheet } from './DrillSession';

/** How long a correct move stays on the board before the line goes on. */
const FLASH_MS = 500;
/** How long the opponent takes over their move. */
const REPLY_MS = 450;
/** Lines drawn at a time in a sitting with no end. */
const BATCH = 5;

type Phase = 'play' | 'flash' | 'wrong' | 'done';

/** A correct answer this line, kept so the line's one grade can re-grade it. */
interface Answered {
  item: TrainingItem;
  before: Card;
  grade: Grade;
  played: string;
}

export interface LineDrillProps {
  /** The side, and the opening the lines are drawn inside. */
  color: Color;
  openingId: string;
  /** Lines in the sitting; a sitting from Drill's own setup draws for as long as you want. */
  count?: number;
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
 * and each of yours is asked. A correct answer is graded by the clock and the
 * line goes on. A miss shows your prep's move beside the one you played, with
 * Why? to see it refuted, and Continue plays your prep's move and carries on
 * — a slip early in a line still leaves the rest of it to practise. Playing
 * another move your prep has is right, and the line follows that move
 * instead.
 *
 * At the end of the line there is one grade for the whole of it: how it felt,
 * from Guessed to Easy, applied to every position you got right on the way.
 * A line with no miss is a clean finish. Nothing here moves a rating.
 */
export function LineDrill({ color, openingId, count, lean, only, prefs, onExit, onNext }: LineDrillProps) {
  const options: DrillPrefs = { ...DEFAULT_DRILL, ...prefs };
  const state = useStore();
  const settings = state.settings;
  const grade = useStore((s) => s.grade);
  const regrade = useStore((s) => s.regrade);
  const ensureCard = useStore((s) => s.ensureCard);
  const logMistake = useStore((s) => s.logMistake);
  const recordMove = useStore((s) => s.recordMove);
  const endRound = useStore((s) => s.endRound);
  const tree = openingTree(referenceIndex());
  const region = nodeById(tree, openingId);
  const rand = useRef(mulberry32(Math.floor(Math.random() * 2 ** 31)));

  const draw = (): DrillLine[] => {
    const now = useStore.getState();
    const rep = repertoireList(now).find((r) => r.color === color);
    if (!rep) return [];
    const scoped = withSelection(now, { color, opening: openingId });
    return drawLines({
      rep,
      tree,
      region,
      index: referenceIndex(),
      lean,
      weakness: weaknessFromCards(now.cards, evidenceIn(scoped)),
      only,
      count: count ?? BATCH,
      rand: rand.current,
    });
  };

  const [batch, setBatch] = useState<DrillLine[]>(draw);
  const [at, setAt] = useState(0);
  const [line, setLine] = useState<DrillLine | null>(batch[0] ?? null);
  const [ply, setPly] = useState(0);
  const [phase, setPhase] = useState<Phase>('play');
  const [played, setPlayed] = useState<LegalMove | null>(null);
  const [why, setWhy] = useState(false);
  const [misses, setMisses] = useState(0);
  const [answered, setAnswered] = useState<Answered[]>([]);
  const [ease, setEase] = useState<Grade | null>(null);
  /** Lines finished this sitting, for the counter. */
  const [finished, setFinished] = useState(0);

  const rep = line ? state.repertoires[line.repertoireId] : undefined;
  const fens = useMemo(() => (line ? walkSan(line.sans).fens : []), [line]);
  const fen = fens[ply] ?? fens[fens.length - 1] ?? '';
  const mine = !!line && ply < line.sans.length && yoursAt(color, ply);

  /** Your prep at the position in front of you, as Drill's item for it. */
  const item = useMemo<TrainingItem | null>(() => {
    if (!rep || !mine) return null;
    const key = positionKey(fen);
    return itemsFor(rep).find((candidate) => candidate.key === key) ?? null;
  }, [rep, mine, fen]);

  const clock = useMoveClock({
    seconds: clockSeconds(options.clock),
    turnKey: `${at}:${ply}`,
    active: phase === 'play' && mine && !why,
  });

  useEffect(() => {
    if (item) ensureCard(item);
  }, [item, ensureCard]);

  /** The opponent's moves play themselves, after a beat. */
  useEffect(() => {
    if (!line || phase !== 'play' || mine || ply >= line.sans.length) return;
    const timer = window.setTimeout(() => setPly((p) => p + 1), REPLY_MS);
    return () => window.clearTimeout(timer);
  }, [line, phase, mine, ply]);

  /** The end of the line: counted once, as a round of its own. */
  useEffect(() => {
    if (!line || phase !== 'play' || ply < line.sans.length) return;
    const asked = answered.length + misses;
    endRound({
      mode: 'drill',
      openingId: deepestNodeWithin(tree, region, line.sans).id,
      color,
      answered: asked,
      correct: answered.length,
      perfect: misses === 0 && asked > 0,
      line: line.sans,
    });
    setFinished((n) => n + 1);
    setPhase('done');
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [line, phase, ply]);

  const buzz = (pattern: number | number[]) => {
    if (settings.hapticFeedback) haptic(pattern);
  };

  const expected = line && mine ? line.sans[ply] : null;
  const expectedMove = useMemo(() => (expected ? applySan(fen, expected) : null), [expected, fen]);

  const onBoardMove = (move: LegalMove) => {
    if (!line || !rep || phase !== 'play' || !mine) return;
    const right = item ? checkAnswer(item, move.san).correct : move.san === expected;
    setPlayed(move);
    const asked = line.sans.slice(0, ply);
    recordMove({ mode: 'drill', line: right ? [...asked, move.san] : asked, color, correct: right, rated: false });
    if (right) {
      buzz(12);
      if (item) {
        const card = state.cards[item.cardId];
        const auto = gradeForTime(clock.elapsedNow());
        grade(item, auto, move.san, true);
        setAnswered((list) => [
          ...list,
          { item, before: card ?? createCard(item.cardId, item.repertoireId, item.key, item.fen), grade: auto, played: move.san },
        ]);
      }
      // Another move your prep has: right, and the line follows it.
      if (move.san !== expected) {
        const along = continueLine(rep, [...asked, move.san]);
        if (along) setLine(along);
      }
      setPhase('flash');
      window.setTimeout(() => {
        setPlayed(null);
        setPly((p) => p + 1);
        setPhase('play');
      }, FLASH_MS);
      return;
    }
    buzz([18, 50, 18]);
    setMisses((n) => n + 1);
    if (item) {
      grade(item, 'again', move.san, false);
      logMistake({
        source: 'drill',
        repertoireId: item.repertoireId,
        key: item.key,
        fen: item.fen,
        path: asked,
        played: move.san,
        expected: expected ?? '',
      });
    }
    setPhase('wrong');
  };

  /** After a miss: your prep's move is played, and the line goes on. */
  const carryOn = () => {
    setPlayed(null);
    setWhy(false);
    setPly((p) => p + 1);
    setPhase('play');
  };

  /** One grade for the whole line, over the clock's grade for each position. */
  const gradeLine = (value: Grade) => {
    for (const answer of answered) {
      if (answer.grade !== value) regrade(answer.item, answer.before, value, answer.played);
    }
    setAnswered((list) => list.map((answer) => ({ ...answer, grade: value })));
    setEase(value);
  };

  const lastOfRound = count !== undefined && at + 1 >= batch.length;

  const nextLine = () => {
    let lines = batch;
    let next = at + 1;
    if (next >= lines.length) {
      lines = draw();
      next = 0;
      setBatch(lines);
    }
    setAt(next);
    setLine(lines[next] ?? null);
    setPly(0);
    setPhase('play');
    setPlayed(null);
    setMisses(0);
    setAnswered([]);
    setEase(null);
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
        <AppBar title="Drill" subtitle={subtitle} onClose={onExit} />
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
      <AppBar
        title="Drill"
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
          interactive={phase === 'play' && mine}
          movableFor={color}
          onMove={onBoardMove}
          highlights={highlights}
          showCoordinates={settings.showCoordinates}
          theme={settings.boardTheme}
          dimmed={phase === 'wrong'}
          captured
        />

        {phase === 'done' && (
          <div className="next-row">
            <button className="btn primary block" onClick={lastOfRound && onNext ? onNext : nextLine}>
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
              Line {count !== undefined ? `${at + 1} of ${batch.length}` : finished + 1}
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
              <button className="btn primary sm" onClick={carryOn}>
                Continue
                <Icons.next size={16} />
              </button>
            </div>
            <div className="compare mt-8">
              <div className="good">
                <div className="k">Repertoire</div>
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
            {answered.length > 0 && (
              <>
                <div className="note center mt-12">How did that line feel?</div>
                <div className="grades sm mt-8">
                  {(['again', 'hard', 'good', 'easy'] as Grade[]).map((g) => (
                    <button
                      key={g}
                      className={`${g}${ease === g ? ' selected' : ''}`}
                      aria-pressed={ease === g}
                      onClick={() => gradeLine(g)}
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
